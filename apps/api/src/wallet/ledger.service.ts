import { createHash, randomUUID } from 'node:crypto';
import { Injectable, BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

export interface LedgerLegInput {
  accountId: string;
  debitAmount: number;
  creditAmount: number;
  currency?: string;
}

@Injectable()
export class LedgerService {
  constructor(private readonly db: DbService) {}

  /**
   * Posts a strictly balanced double-entry transaction.
   * Invariant: SUM(debits) === SUM(credits)
   */
  async postTransaction(
    client: { query: (s: string, p?: unknown[]) => Promise<any> },
    legs: LedgerLegInput[],
    referenceType: string,
    referenceId?: string,
    idempotencyKey?: string,
  ): Promise<{ transactionId: string; entriesCount: number }> {
    if (!Array.isArray(legs) || legs.length < 2) {
      throw new BadRequestException({ code: 'LEDGER_REQUIRES_AT_LEAST_TWO_LEGS' });
    }

    // Check idempotency
    if (idempotencyKey) {
      const existing = await client.query(
        `SELECT transaction_id FROM financial_ledger_entries WHERE idempotency_key = $1 LIMIT 1`,
        [idempotencyKey],
      );
      if (existing.rowCount) {
        return { transactionId: existing.rows[0].transaction_id, entriesCount: 0 };
      }
    }

    // Validate debit and credit balance
    let totalDebit = 0;
    let totalCredit = 0;

    for (const leg of legs) {
      const debit = Math.round((leg.debitAmount || 0) * 100) / 100;
      const credit = Math.round((leg.creditAmount || 0) * 100) / 100;

      if (debit < 0 || credit < 0) {
        throw new BadRequestException({ code: 'NEGATIVE_AMOUNTS_PROHIBITED' });
      }
      if ((debit > 0 && credit > 0) || (debit === 0 && credit === 0)) {
        throw new BadRequestException({ code: 'LEG_MUST_BE_EXCLUSIVELY_DEBIT_OR_CREDIT' });
      }

      totalDebit += debit;
      totalCredit += credit;
    }

    // Exact balance check in integer cents
    const diff = Math.abs(Math.round(totalDebit * 100) - Math.round(totalCredit * 100));
    if (diff !== 0) {
      throw new BadRequestException({
        code: 'LEDGER_TRANSACTION_UNBALANCED',
        totalDebit,
        totalCredit,
        difference: diff / 100,
      });
    }

    const transactionId = randomUUID();

    for (const leg of legs) {
      await client.query(`
        INSERT INTO financial_ledger_entries(
          transaction_id, reference_type, reference_id, account_id,
          debit_amount, credit_amount, currency, idempotency_key
        )
        VALUES($1, $2, $3, $4, $5, $6, coalesce($7, 'SYP_NEW'), $8)
      `, [
        transactionId,
        referenceType,
        referenceId ?? null,
        leg.accountId,
        leg.debitAmount || 0,
        leg.creditAmount || 0,
        leg.currency ?? 'SYP_NEW',
        idempotencyKey ?? null,
      ]);
    }

    return { transactionId, entriesCount: legs.length };
  }

  /** Holds an amount in reservation (e.g. pre-paid commission model) */
  async createReservation(
    client: { query: (s: string, p?: unknown[]) => Promise<any> },
    accountId: string,
    amount: number,
    referenceId: string,
  ) {
    if (amount <= 0) throw new BadRequestException({ code: 'INVALID_RESERVATION_AMOUNT' });

    const res = await client.query(`
      INSERT INTO financial_reservations(account_id, amount, reference_id, status)
      VALUES($1, $2, $3, 'HELD')
      RETURNING *
    `, [accountId, amount, referenceId]);

    return res.rows[0];
  }

  /** Commits a held reservation upon successful visit completion */
  async commitReservation(
    client: { query: (s: string, p?: unknown[]) => Promise<any> },
    reservationId: string,
  ) {
    const res = await client.query(`
      UPDATE financial_reservations
      SET status = 'COMMITTED', resolved_at = now()
      WHERE id = $1 AND status = 'HELD'
      RETURNING *
    `, [reservationId]);

    if (!res.rowCount) throw new NotFoundException({ code: 'RESERVATION_NOT_FOUND_OR_RESOLVED' });
    return res.rows[0];
  }

  /** Releases a held reservation upon cancellation */
  async releaseReservation(
    client: { query: (s: string, p?: unknown[]) => Promise<any> },
    reservationId: string,
  ) {
    const res = await client.query(`
      UPDATE financial_reservations
      SET status = 'RELEASED', resolved_at = now()
      WHERE id = $1 AND status = 'HELD'
      RETURNING *
    `, [reservationId]);

    if (!res.rowCount) throw new NotFoundException({ code: 'RESERVATION_NOT_FOUND_OR_RESOLVED' });
    return res.rows[0];
  }

  /** Records completion of a visit in the double-entry ledger */
  async recordVisitCompletion(
    client: { query: (s: string, p?: unknown[]) => Promise<any> },
    requestId: string,
    nurseId: string,
    totalGross: number,
    platformCommission: number,
  ) {
    const nurseShare = totalGross - platformCommission;
    const idempotencyKey = `visit_completion_${requestId}`;

    // Legs:
    // 1. Debit NURSE_RECEIVABLE for the commission collected in cash
    // 2. Credit COMPANY_COMMISSIONS revenue for the commission earned
    const legs: LedgerLegInput[] = [
      {
        accountId: `NURSE_RECEIVABLE:${nurseId}`,
        debitAmount: platformCommission,
        creditAmount: 0,
      },
      {
        accountId: 'COMPANY_COMMISSIONS',
        debitAmount: 0,
        creditAmount: platformCommission,
      },
    ];

    return this.postTransaction(
      client,
      legs,
      'PLATFORM_COMMISSION',
      requestId,
      idempotencyKey,
    );
  }
}
