import { createHash, randomUUID } from 'node:crypto';
import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import type { PoolClient } from 'pg';

export type MoneyInput = string | number;

export interface LedgerLegInput {
  accountId: string;
  debitAmount: MoneyInput;
  creditAmount: MoneyInput;
  currency?: string;
}

interface PostTransactionInput {
  legs: LedgerLegInput[];
  transactionType: string;
  referenceType: string;
  referenceId?: string;
  idempotencyKey: string;
  currencyCode: string;
  actorUserId?: string;
  reversalOfTransactionId?: string;
}

export function toMinor(value: MoneyInput): bigint {
  const raw = String(value).trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(raw)) {
    throw new BadRequestException({ code: 'INVALID_MONEY_AMOUNT' });
  }
  const [whole = '0', fraction = ''] = raw.split('.');
  return BigInt(whole) * 100n + BigInt((fraction + '00').slice(0, 2));
}

export function fromMinor(value: bigint): string {
  const whole = value / 100n;
  const fraction = (value % 100n).toString().padStart(2, '0');
  return `${whole}.${fraction}`;
}

function canonicalPayload(input: PostTransactionInput, normalizedLegs: Array<LedgerLegInput & { debit: string; credit: string }>) {
  return JSON.stringify({
    transactionType: input.transactionType,
    referenceType: input.referenceType,
    referenceId: input.referenceId ?? null,
    currencyCode: input.currencyCode,
    reversalOfTransactionId: input.reversalOfTransactionId ?? null,
    legs: normalizedLegs.map(leg => ({ accountId: leg.accountId, debit: leg.debit, credit: leg.credit })),
  });
}

@Injectable()
export class LedgerService {
  async postTransaction(client: PoolClient, input: PostTransactionInput): Promise<{
    transactionId: string;
    entriesCount: number;
    replayed: boolean;
  }> {
    if (input.legs.length < 2 || !input.idempotencyKey.trim()) {
      throw new BadRequestException({ code: 'INVALID_LEDGER_TRANSACTION' });
    }

    let debitTotal = 0n;
    let creditTotal = 0n;
    const normalized = input.legs.map(leg => {
      const debitMinor = toMinor(leg.debitAmount);
      const creditMinor = toMinor(leg.creditAmount);
      if ((debitMinor > 0n) === (creditMinor > 0n)) {
        throw new BadRequestException({ code: 'LEG_MUST_BE_EXCLUSIVELY_DEBIT_OR_CREDIT' });
      }
      if (leg.currency && leg.currency !== input.currencyCode) {
        throw new BadRequestException({ code: 'MIXED_CURRENCY_TRANSACTION' });
      }
      debitTotal += debitMinor;
      creditTotal += creditMinor;
      return { ...leg, debit: fromMinor(debitMinor), credit: fromMinor(creditMinor) };
    });
    if (debitTotal !== creditTotal) {
      throw new BadRequestException({
        code: 'LEDGER_TRANSACTION_UNBALANCED',
        totalDebit: fromMinor(debitTotal),
        totalCredit: fromMinor(creditTotal),
      });
    }

    const digest = createHash('sha256').update(canonicalPayload(input, normalized)).digest('hex');
    const transactionId = randomUUID();
    const inserted = await client.query<{ id: string }>(`
      INSERT INTO financial_transactions(
        id,transaction_type,reference_type,reference_id,currency_code,
        idempotency_key,payload_digest,reversal_of_transaction_id,created_by
      ) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)
      ON CONFLICT(idempotency_key) DO NOTHING RETURNING id
    `, [transactionId,input.transactionType,input.referenceType,input.referenceId ?? null,
      input.currencyCode,input.idempotencyKey,digest,input.reversalOfTransactionId ?? null,input.actorUserId ?? null]);

    if (!inserted.rowCount) {
      const existing = (await client.query<{ id: string; payload_digest: string }>(
        'SELECT id,payload_digest FROM financial_transactions WHERE idempotency_key=$1',
        [input.idempotencyKey],
      )).rows[0];
      if (!existing || existing.payload_digest !== digest) {
        throw new ConflictException({ code: 'FINANCIAL_IDEMPOTENCY_KEY_REUSED' });
      }
      return { transactionId: existing.id, entriesCount: 0, replayed: true };
    }

    for (const leg of normalized) {
      await client.query(`INSERT INTO financial_ledger_entries(
        transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency
      ) VALUES($1,$2,$3,$4,$5,$6,$7)`, [transactionId,input.referenceType,input.referenceId ?? null,
        leg.accountId,leg.debit,leg.credit,input.currencyCode]);
    }
    return { transactionId, entriesCount: normalized.length, replayed: false };
  }

  async createReservation(
    client: PoolClient,
    accountId: string,
    amount: MoneyInput,
    referenceId: string,
    currencyCode: string,
  ) {
    const normalized = fromMinor(toMinor(amount));
    if (toMinor(normalized) <= 0n) throw new BadRequestException({ code: 'INVALID_RESERVATION_AMOUNT' });
    const inserted = await client.query(`INSERT INTO financial_reservations(account_id,amount,reference_id,status,currency_code,credit_amount)
      VALUES($1,$2,$3,'HELD',$4,$2) ON CONFLICT(account_id,reference_id) DO NOTHING RETURNING *`,
    [accountId,normalized,referenceId,currencyCode]);
    if (inserted.rowCount) return inserted.rows[0];
    const existing = (await client.query(
      'SELECT * FROM financial_reservations WHERE account_id=$1 AND reference_id=$2',
      [accountId,referenceId],
    )).rows[0];
    if (!existing || existing.currency_code!==currencyCode || fromMinor(toMinor(existing.amount)) !== normalized) {
      throw new ConflictException({ code: 'RESERVATION_IDEMPOTENCY_CONFLICT' });
    }
    return existing;
  }

  async resolveReservation(client: PoolClient, reservationId: string, status: 'COMMITTED' | 'RELEASED') {
    const result = await client.query(`UPDATE financial_reservations
      SET status=$2,resolved_at=statement_timestamp() WHERE id=$1 AND status='HELD' RETURNING *`,
    [reservationId,status]);
    if (!result.rowCount) throw new NotFoundException({ code: 'RESERVATION_NOT_FOUND_OR_RESOLVED' });
    return result.rows[0];
  }

  recordCommission(
    client: PoolClient,
    requestId: string,
    nurseId: string,
    commission: MoneyInput,
    currencyCode: string,
  ) {
    return this.postTransaction(client, {
      transactionType: 'COMMISSION_RECOGNITION',
      referenceType: 'CARE_REQUEST',
      referenceId: requestId,
      idempotencyKey: `commission:${requestId}`,
      currencyCode,
      legs: [
        { accountId: `NURSE_RECEIVABLE:${nurseId}`, debitAmount: commission, creditAmount: 0 },
        { accountId: 'COMMISSION_REVENUE', debitAmount: 0, creditAmount: commission },
      ],
    });
  }

  async reverseTransaction(client: PoolClient, transactionId: string, idempotencyKey: string, actorUserId: string) {
    const original = await client.query(`SELECT t.*,e.account_id,e.debit_amount,e.credit_amount
      FROM financial_transactions t JOIN financial_ledger_entries e ON e.transaction_id=t.id
      WHERE t.id=$1 ORDER BY e.id`, [transactionId]);
    if (!original.rowCount) throw new NotFoundException({ code: 'FINANCIAL_TRANSACTION_NOT_FOUND' });
    const first = original.rows[0];
    return this.postTransaction(client, {
      transactionType: 'REVERSAL', referenceType: first.reference_type,
      referenceId: first.reference_id, idempotencyKey, currencyCode: first.currency_code,
      reversalOfTransactionId: transactionId, actorUserId,
      legs: original.rows.map(row => ({
        accountId: row.account_id,
        debitAmount: row.credit_amount,
        creditAmount: row.debit_amount,
      })),
    });
  }
}
