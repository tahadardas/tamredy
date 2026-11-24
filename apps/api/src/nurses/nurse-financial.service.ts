import { Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

@Injectable()
export class NurseFinancialService {
  constructor(private readonly db: DbService) {}

  private async getNurseId(userId: string): Promise<string> {
    const res = await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [userId]);
    if (!res.rowCount) throw new NotFoundException({ code: 'NURSE_RECORD_NOT_FOUND' });
    return res.rows[0].id;
  }

  /** Detailed financial summary for nurse dashboard */
  async getFinancialSummary(nurseUserId: string) {
    const nurseId = await this.getNurseId(nurseUserId);

    // 1. Earnings aggregations across time horizons
    const statsRes = await this.db.query(`
      SELECT
        coalesce(sum(cr.price_amount - coalesce(cr.owed_to_company, 0)), 0)::numeric(18,2) AS lifetime_net_earnings,
        coalesce(sum(cr.price_amount), 0)::numeric(18,2) AS lifetime_gross,
        coalesce(sum(coalesce(cr.owed_to_company, 0)), 0)::numeric(18,2) AS lifetime_commission,
        count(*)::int AS completed_visits_count,
        coalesce(sum(CASE WHEN v.completed_at >= current_date THEN (cr.price_amount - coalesce(cr.owed_to_company, 0)) ELSE 0 END), 0)::numeric(18,2) AS today_net_earnings,
        coalesce(sum(CASE WHEN v.completed_at >= date_trunc('week', now()) THEN (cr.price_amount - coalesce(cr.owed_to_company, 0)) ELSE 0 END), 0)::numeric(18,2) AS this_week_net_earnings,
        coalesce(sum(CASE WHEN v.completed_at >= date_trunc('month', now()) THEN (cr.price_amount - coalesce(cr.owed_to_company, 0)) ELSE 0 END), 0)::numeric(18,2) AS this_month_net_earnings
      FROM request_assignments ra
      JOIN visits v ON v.assignment_id = ra.id AND v.completed_at IS NOT NULL
      JOIN care_requests cr ON cr.id = ra.request_id AND cr.payment_status = 'PAID'
      WHERE ra.nurse_id = $1
    `, [nurseId]);

    const stats = statsRes.rows[0];

    // 2. Receivables and settlements calculation
    const duesRes = await this.db.query(`
      SELECT
        coalesce((
          SELECT sum(cr.owed_to_company)
          FROM request_assignments a
          JOIN visits v ON v.assignment_id = a.id AND v.completed_at IS NOT NULL
          JOIN care_requests cr ON cr.id = a.request_id AND cr.payment_status = 'PAID'
          WHERE a.nurse_id = $1
        ), 0)::numeric(18,2) AS total_commission_accrued,
        coalesce((
          SELECT sum(amount)
          FROM nurse_settlements
          WHERE nurse_id = $1 AND direction = 'FROM_NURSE'
        ), 0)::numeric(18,2) AS total_settled_amount
    `, [nurseId]);

    const totalAccrued = Number(duesRes.rows[0].total_commission_accrued);
    const totalSettled = Number(duesRes.rows[0].total_settled_amount);
    const outstandingDues = Math.max(0, totalAccrued - totalSettled);

    // 3. Nurse financial account & credit limit
    const accRes = await this.db.query(`
      SELECT financial_model, credit_limit, prepaid_balance, reserved_balance
      FROM nurse_financial_accounts
      WHERE nurse_id = $1
    `, [nurseId]);

    const account = accRes.rows[0] ?? {
      financial_model: 'RECEIVABLES',
      credit_limit: 100000,
      prepaid_balance: 0,
      reserved_balance: 0,
    };

    const creditLimit = Number(account.credit_limit);
    const isLimitExceeded = outstandingDues >= creditLimit;

    // 4. Recent visits breakdown
    const recentVisits = await this.db.query(`
      SELECT cr.id AS request_id, v.completed_at, cr.address_text, s.title_ar AS service_title,
             cr.price_amount AS gross_amount, cr.owed_to_company AS commission_amount,
             (cr.price_amount - coalesce(cr.owed_to_company, 0)) AS net_amount,
             cr.currency_code
      FROM request_assignments ra
      JOIN visits v ON v.assignment_id = ra.id AND v.completed_at IS NOT NULL
      JOIN care_requests cr ON cr.id = ra.request_id
      JOIN services s ON s.id = cr.service_id
      WHERE ra.nurse_id = $1
      ORDER BY v.completed_at DESC
      LIMIT 10
    `, [nurseId]);

    return {
      currencyCode: 'SYP_NEW',
      financialModel: account.financial_model,
      earnings: {
        today: Number(stats.today_net_earnings),
        thisWeek: Number(stats.this_week_net_earnings),
        thisMonth: Number(stats.this_month_net_earnings),
        lifetimeNet: Number(stats.lifetime_net_earnings),
        lifetimeGross: Number(stats.lifetime_gross),
        completedVisitsCount: stats.completed_visits_count,
      },
      receivables: {
        totalAccrued,
        totalSettled,
        outstandingDues,
        creditLimit,
        isLimitExceeded,
        limitUtilizationPercent: creditLimit > 0 ? Math.min(100, Math.round((outstandingDues / creditLimit) * 100)) : 0,
      },
      prepaid: {
        availableBalance: Number(account.prepaid_balance) - Number(account.reserved_balance),
        totalBalance: Number(account.prepaid_balance),
        reservedBalance: Number(account.reserved_balance),
      },
      recentVisits: recentVisits.rows,
    };
  }

  /** Nurse ledger entries history */
  async getLedgerHistory(nurseUserId: string, limit = 50) {
    const nurseId = await this.getNurseId(nurseUserId);
    const clampedLimit = Math.min(Math.max(1, limit), 100);

    const res = await this.db.query(`
      SELECT le.id, le.transaction_id, le.reference_type, le.reference_id,
             le.debit_amount, le.credit_amount, le.currency, le.created_at
      FROM financial_ledger_entries le
      WHERE le.account_id = $1
      ORDER BY le.created_at DESC
      LIMIT $2
    `, [`NURSE_RECEIVABLE:${nurseId}`, clampedLimit]);

    return res.rows;
  }
}
