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
  ): Promise<{ releasedCount: number; releasedAmount: number }> {
    const released = await client.query<{
      id: string;
      nurse_id: string | null;
      amount: string | number;
      currency_code: string;
    }>(
      `UPDATE financial_reservations
       SET status = 'RELEASED',
           resolved_at = statement_timestamp(),
           resolution_reason = $2
       WHERE reference_id = $1 AND status = 'HELD'
       RETURNING id, nurse_id, amount, currency_code`,
      [requestId, reason],
    );

    if (!released.rowCount) {
      return { releasedCount: 0, releasedAmount: 0 };
    }

    const nurseTotals = new Map<string, bigint>();
    let totalMinor = 0n;
    for (const row of released.rows) {
      const amtMinor = toMinor(row.amount);
      totalMinor += amtMinor;
      if (row.nurse_id) {
        nurseTotals.set(row.nurse_id, (nurseTotals.get(row.nurse_id) ?? 0n) + amtMinor);
      }
    }

    for (const [nurseId, amtMinor] of nurseTotals.entries()) {
      await client.query(
        `UPDATE nurse_financial_accounts
         SET reserved_balance = greatest(0, reserved_balance - $2::numeric),
             updated_at = statement_timestamp()
         WHERE nurse_id = $1`,
        [nurseId, fromMinor(amtMinor)],
      );
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
            releasedAmount: fromMinor(totalMinor),
          }),
        ],
      );
    }

    return {
      releasedCount: released.rowCount,
      releasedAmount: Number(fromMinor(totalMinor)),
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
    const reservations = await client.query(
      `SELECT id, nurse_id, amount, prepaid_amount, credit_amount
       FROM financial_reservations
       WHERE reference_id = $1 AND status = 'HELD'
       FOR UPDATE`,
      [requestId],
    );

    for (const reservation of reservations.rows) {
      await client.query(
        `UPDATE financial_reservations
         SET status = 'COMMITTED',
             resolved_at = statement_timestamp(),
             resolution_reason = 'INVOICE_COMMITTED'
         WHERE id = $1 AND status = 'HELD'`,
        [reservation.id],
      );
      if (reservation.nurse_id) {
        const reservedPrepaid = toMinor(reservation.prepaid_amount);
        const finalComm = toMinor(finalCommission);
        const prepaidApplied = fromMinor(
          reservedPrepaid < finalComm ? reservedPrepaid : finalComm,
        );
        if (toMinor(prepaidApplied) > 0n) {
          await ledger.postTransaction(client, {
            transactionType: 'PREPAID_COMMISSION_APPLIED',
            referenceType: 'INVOICE',
            referenceId: invoiceId,
            idempotencyKey: `invoice-prepaid:${invoiceId}:${reservation.id}`,
            currencyCode,
            legs: [
              {
                accountId: `PREPAID_LIABILITY:${reservation.nurse_id}`,
                debitAmount: prepaidApplied,
                creditAmount: 0,
              },
              {
                accountId: `NURSE_PAYABLE:${reservation.nurse_id}`,
                debitAmount: 0,
                creditAmount: prepaidApplied,
              },
            ],
          });
        }
        await client.query(
          `UPDATE nurse_financial_accounts
           SET reserved_balance = greatest(0, reserved_balance - $2),
               prepaid_balance = greatest(0, prepaid_balance - $3),
               updated_at = statement_timestamp()
           WHERE nurse_id = $1`,
          [reservation.nurse_id, reservation.amount, prepaidApplied],
        );
      }
    }
  }
}
