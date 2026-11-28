import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { fromMinor, toMinor, type LedgerService } from './ledger.service.js';

export type ReservationResolutionReason =
  | 'INVOICE_COMMITTED'
  | 'PATIENT_CANCELLED'
  | 'NO_SERVICE_DELIVERED'
  | 'SAFE_ABORT'
  | 'ADMIN_RESOLUTION';

/**
 * BUG-014: Centralized financial reservation lifecycle handler ensuring HELD
 * reservations are deterministically settled across completion, cancellation,
 * no-service visits, Safe Abort, and admin intervention without dangling balances.
 */
@Injectable()
export class FinancialReservationsService {
  async releaseForRequest(
    client: PoolClient,
    requestId: string,
    reason: ReservationResolutionReason,
    actorUserId?: string,
  ) {
    const released = await client.query<{
      id: string;
      nurse_id: string | null;
      amount: string | number;
      currency_code: string;
      currency_account_id: string | null;
    }>(
      `UPDATE financial_reservations
       SET status = 'RELEASED',
           resolved_at = statement_timestamp(),
           resolution_reason = $2
       WHERE reference_id = $1 AND status = 'HELD'
       RETURNING id, nurse_id, amount, currency_code, currency_account_id`,
      [requestId, reason],
    );

    if (!released.rowCount) {
      return { releasedCount: 0, releasedAmount: 0 };
    }

    // Resolve only the matching currency account. Legacy unscoped balances remain
    // untouched until their currency is administratively reconciled.
    let totalMinor = 0n;
    const releasedByCurrency: Record<string, string> = {};
    for (const row of released.rows.sort((a,b)=>(a.currency_account_id ?? '').localeCompare(b.currency_account_id ?? ''))) {
      const amtMinor = toMinor(row.amount);
      totalMinor += amtMinor;
      releasedByCurrency[row.currency_code] = fromMinor(
        toMinor(releasedByCurrency[row.currency_code] ?? '0') + amtMinor,
      );
      await client.query(`UPDATE nurse_financial_currency_accounts
        SET reserved_balance=greatest(0,reserved_balance-$2::numeric),
          version=version+1,updated_at=statement_timestamp()
        WHERE id=$1 AND currency_code=$3`,
      [row.currency_account_id,fromMinor(amtMinor),row.currency_code]);
    }

    const accounts=new Map(released.rows.filter(row=>row.currency_account_id && row.nurse_id)
      .map(row=>[row.currency_account_id,row]));
    for (const row of accounts.values()) {
      await client.query('SELECT recompute_nurse_financial_eligibility($1,$2)',[row.nurse_id,row.currency_code]);
    }

    if (actorUserId) {
      await client.query(
        `INSERT INTO audit_log(actor_user_id, action, target_type, target_id, detail)
         VALUES($1, 'financial.reservation_released', 'care_request', $2, $3::jsonb)`,
        [
          actorUserId,
          requestId,
          JSON.stringify({
            reason,
            releasedCount: released.rowCount,
            releasedByCurrency,
          }),
        ],
      );
    }

    return {
      releasedCount: released.rowCount,
      releasedAmount: released.rows.every(row => row.currency_code===released.rows[0]?.currency_code) ? Number(fromMinor(totalMinor)) : 0,
      releasedByCurrency,
    };
  }

  async commitForInvoice(
    client: PoolClient,
    ledger: LedgerService,
    requestId: string,
    invoiceId: string,
    finalCommission: number,
    currencyCode: string,
  ) {
    const reservations = await client.query(`SELECT * FROM financial_reservations
      WHERE reference_id=$1 AND status='HELD' AND currency_code=$2 FOR UPDATE`,
    [requestId,currencyCode]);
    for (const reservation of reservations.rows) {
      const account = reservation.currency_account_id
        ? (await client.query(`SELECT a.*,
            coalesce((SELECT sum(r.prepaid_amount) FROM financial_reservations r
              WHERE r.currency_account_id=a.id AND r.status='HELD' AND r.id<>$3),0) AS other_prepaid,
            coalesce((SELECT sum(r.credit_amount) FROM financial_reservations r
              WHERE r.currency_account_id=a.id AND r.status='HELD' AND r.id<>$3),0) AS other_credit,
            greatest(coalesce((SELECT sum(e.debit_amount-e.credit_amount)
              FROM financial_ledger_entries e WHERE e.currency=a.currency_code
              AND e.account_id IN ('CASH_HELD_BY_NURSE:'||a.nurse_id::text,'NURSE_PAYABLE:'||a.nurse_id::text)),0),0) AS dues
            FROM nurse_financial_currency_accounts a
            WHERE a.id=$1 AND a.currency_code=$2 FOR UPDATE OF a`,
          [reservation.currency_account_id,currencyCode,reservation.id])).rows[0] : null;
      const allocation = reconcileCommission({
        finalCommission: toMinor(finalCommission),
        reservedPrepaid: toMinor(reservation.prepaid_amount),
        reservedCredit: toMinor(reservation.credit_amount),
        prepaidBalance: account ? maxMinor(0n,toMinor(account.prepaid_balance)-toMinor(account.other_prepaid)) : 0n,
        financialModel: account?.financial_model ?? 'PREPAID',
        // A legacy balance with no proven currency cannot fund this invoice.
        creditAvailable: account ? maxMinor(0n,toMinor(account.credit_limit)-toMinor(account.dues)-toMinor(account.other_credit)) : 0n,
      });
      if (allocation.prepaidApplied > 0n && reservation.nurse_id) {
        await ledger.postTransaction(client, {
          transactionType: 'PREPAID_COMMISSION_APPLIED', referenceType: 'INVOICE',
          referenceId: invoiceId,idempotencyKey: `invoice-prepaid:${invoiceId}:${reservation.id}`,
          currencyCode,
          legs: [
            { accountId:`PREPAID_LIABILITY:${reservation.nurse_id}`,
              debitAmount:fromMinor(allocation.prepaidApplied),creditAmount:0 },
            { accountId:`NURSE_PAYABLE:${reservation.nurse_id}`,
              debitAmount:0,creditAmount:fromMinor(allocation.prepaidApplied) },
          ],
        });
      }
      await client.query(`INSERT INTO commission_reconciliations(
        reservation_id,invoice_id,currency_code,estimated_commission,final_commission,
        reserved_prepaid,reserved_credit,prepaid_applied,credit_applied,released_amount,uncovered_commission
      ) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
      [reservation.id,invoiceId,currencyCode,reservation.amount,fromMinor(allocation.finalCommission),
        reservation.prepaid_amount,reservation.credit_amount,fromMinor(allocation.prepaidApplied),
        fromMinor(allocation.creditApplied),fromMinor(allocation.releasedAmount),fromMinor(allocation.uncoveredCommission)]);
      if (account) {
        await client.query(`UPDATE nurse_financial_currency_accounts
          SET reserved_balance=greatest(0,reserved_balance-$2::numeric),
            prepaid_balance=prepaid_balance-$3::numeric,
            version=version+1,updated_at=statement_timestamp() WHERE id=$1 AND currency_code=$4`,
        [account.id,reservation.amount,fromMinor(allocation.prepaidApplied),currencyCode]);
      }
      // The invoice journal already recognizes the full commission. An uncovered
      // portion is a collectible position, never a second revenue posting.
      await client.query(`UPDATE financial_reservations SET status='COMMITTED',
        resolved_at=statement_timestamp(),resolution_reason='INVOICE_COMMITTED'
        WHERE id=$1 AND status='HELD'`, [reservation.id]);
      if (account && reservation.nurse_id) {
        await client.query('SELECT recompute_nurse_financial_eligibility($1,$2)',[reservation.nurse_id,currencyCode]);
      }
    }
  }
}

const maxMinor = (a: bigint,b: bigint): bigint => a>b ? a : b;

export interface CommissionReconciliationInput {
  finalCommission: bigint;
  reservedPrepaid: bigint;
  reservedCredit: bigint;
  prepaidBalance: bigint;
  creditAvailable: bigint;
  financialModel: 'PREPAID' | 'RECEIVABLES' | 'HYBRID';
}

export function reconcileCommission(input: CommissionReconciliationInput) {
  const min = (a: bigint,b: bigint) => a<b ? a : b;
  const max = (a: bigint,b: bigint) => a>b ? a : b;
  const prepaidApplied = input.financialModel==='RECEIVABLES' ? 0n
    : min(input.finalCommission,input.prepaidBalance);
  const remainder=input.finalCommission-prepaidApplied;
  const creditApplied=input.financialModel==='PREPAID' ? 0n : min(remainder,input.creditAvailable);
  return {
    ...input,prepaidApplied,creditApplied,
    releasedAmount:max(0n,input.reservedPrepaid+input.reservedCredit-input.finalCommission),
    uncoveredCommission:remainder-creditApplied,
  };
}
