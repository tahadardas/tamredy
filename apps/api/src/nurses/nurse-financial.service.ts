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

  /** Detailed financial summary for nurse dashboard with strict currency isolation (BUG-010) */
  async getFinancialSummary(nurseUserId: string) {
    const nurseId = await this.getNurseId(nurseUserId);

    // 1. Earnings aggregations grouped strictly by currency
    const statsRes = await this.db.query(`
      SELECT
        cr.currency_code,
        coalesce(sum(cr.nurse_earning), 0)::numeric(18,2) AS lifetime_net_earnings,
        coalesce(sum(cr.gross_amount), 0)::numeric(18,2) AS lifetime_gross,
        coalesce(sum(cr.commission_amount), 0)::numeric(18,2) AS lifetime_commission,
        count(*)::int AS completed_visits_count,
        coalesce(sum(CASE WHEN v.completed_at >= current_date THEN cr.nurse_earning ELSE 0 END), 0)::numeric(18,2) AS today_net_earnings,
        coalesce(sum(CASE WHEN v.completed_at >= date_trunc('week', now()) THEN cr.nurse_earning ELSE 0 END), 0)::numeric(18,2) AS this_week_net_earnings,
        coalesce(sum(CASE WHEN v.completed_at >= date_trunc('month', now()) THEN cr.nurse_earning ELSE 0 END), 0)::numeric(18,2) AS this_month_net_earnings
      FROM request_assignments ra
      JOIN visits v ON v.assignment_id = ra.id AND v.completed_at IS NOT NULL
      JOIN care_requests cr ON cr.id = ra.request_id AND cr.payment_status = 'PAID'
      WHERE ra.nurse_id = $1
      GROUP BY cr.currency_code
    `, [nurseId]);

    const primaryCurrency = process.env.ACCOUNTING_CURRENCY_CODE ?? null;
    const stats = statsRes.rows.find(r => r.currency_code === primaryCurrency) ?? {
      currency_code: primaryCurrency,
      today_net_earnings: 0,
      this_week_net_earnings: 0,
      this_month_net_earnings: 0,
      lifetime_net_earnings: 0,
      lifetime_gross: 0,
      completed_visits_count: 0,
    };

    // 2. Authoritative settlement position grouped strictly by currency from immutable double-entry accounts.
    const duesRes = await this.db.query(`
      SELECT
        e.currency AS currency_code,
        coalesce(sum(CASE WHEN e.account_id='CASH_HELD_BY_NURSE:'||$1::text
          THEN e.debit_amount-e.credit_amount ELSE 0 END),0)::numeric(18,2) AS cash_held,
        coalesce(sum(CASE WHEN e.account_id='NURSE_PAYABLE:'||$1::text
          THEN e.credit_amount-e.debit_amount ELSE 0 END),0)::numeric(18,2) AS nurse_payable,
        coalesce(sum(CASE WHEN t.transaction_type='NURSE_SETTLEMENT_FROM_NURSE'
          AND e.account_id='CASH_HELD_BY_NURSE:'||$1::text THEN e.credit_amount ELSE 0 END),0)::numeric(18,2) AS total_settled_amount
      FROM financial_ledger_entries e JOIN financial_transactions t ON t.id=e.transaction_id
      WHERE e.account_id IN ('CASH_HELD_BY_NURSE:'||$1::text, 'NURSE_PAYABLE:'||$1::text)
      GROUP BY e.currency
    `, [nurseId]);

    // 3. Nurse financial account & credit limit
    const accRes = await this.db.query(`
      SELECT currency_code, financial_model, credit_limit, prepaid_balance, reserved_balance, settlement_required,
        greatest(0,prepaid_balance-reserved_balance)::text AS available_balance
      FROM nurse_financial_currency_accounts
      WHERE nurse_id = $1 ORDER BY currency_code
    `, [nurseId]);
    const legacy = await this.db.query(
      'SELECT reconciliation_required FROM nurse_financial_accounts WHERE nurse_id=$1', [nurseId],
    );

    const hasFinancialAccount = (accRes.rowCount ?? 0) > 0;
    const account = accRes.rows.find(row => row.currency_code===primaryCurrency) ?? {
      financial_model: 'RECEIVABLES',
      credit_limit: 0,
      prepaid_balance: 0,
      reserved_balance: 0,
    };
    const creditLimit = Number(account.credit_limit);

    const balancesByCurrency = duesRes.rows.map(r => {
      const currencyAccount = accRes.rows.find(account => account.currency_code===r.currency_code);
      const creditLimit = Number(currencyAccount?.credit_limit ?? 0);
      const cashHeld = Number(r.cash_held);
      const nursePayable = Number(r.nurse_payable);
      const settled = Number(r.total_settled_amount);
      const outstandingDues = Math.max(0, cashHeld - nursePayable);
      const accrued = Math.max(0, cashHeld - nursePayable + settled);
      return {
        currencyCode: String(r.currency_code),
        cashHeld,
        nursePayable,
        totalAccrued: accrued,
        totalSettled: settled,
        outstandingDues,
        creditLimit,
        isLimitExceeded: creditLimit > 0 && outstandingDues >= creditLimit,
      };
    });

    const primaryDues = balancesByCurrency.find(b => b.currencyCode === primaryCurrency) ?? {
      currencyCode: primaryCurrency,
      cashHeld: 0,
      nursePayable: 0,
      totalAccrued: 0,
      totalSettled: 0,
      outstandingDues: 0,
      creditLimit,
      isLimitExceeded: false,
    };

    // 4. Recent visits breakdown
    const recentVisits = await this.db.query(`
      SELECT cr.id AS request_id, v.completed_at, cr.address_text, s.title_ar AS service_title,
             cr.gross_amount, cr.commission_amount,
             cr.nurse_earning AS net_amount,
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
      hasFinancialAccount,
      financialStatus:hasFinancialAccount?'FINANCIAL_CONFIGURED':'FINANCIAL_SETUP_REQUIRED',
      isFinanciallyBlocked:accRes.rows.length>0 && accRes.rows.every(row=>row.settlement_required===true),
      legacyReconciliationRequired: legacy.rows.some(row => row.reconciliation_required),
      financialAccountsByCurrency: accRes.rows.map(row => ({
        currencyCode:row.currency_code, financialModel:row.financial_model,
        creditLimit:row.credit_limit,prepaidBalance:row.prepaid_balance,
        reservedBalance:row.reserved_balance,
        availableBalance:row.available_balance,
        settlementRequired:row.settlement_required,
      })),
      currencyCode: primaryCurrency,
      financialModel: account.financial_model,
      balancesByCurrency,
      earningsByCurrency: statsRes.rows.map(r => ({
        currencyCode: String(r.currency_code),
        today: Number(r.today_net_earnings),
        thisWeek: Number(r.this_week_net_earnings),
        thisMonth: Number(r.this_month_net_earnings),
        lifetimeNet: Number(r.lifetime_net_earnings),
        lifetimeGross: Number(r.lifetime_gross),
        completedVisitsCount: Number(r.completed_visits_count),
      })),
      earnings: {
        today: Number(stats.today_net_earnings),
        thisWeek: Number(stats.this_week_net_earnings),
        thisMonth: Number(stats.this_month_net_earnings),
        lifetimeNet: Number(stats.lifetime_net_earnings),
        lifetimeGross: Number(stats.lifetime_gross),
        completedVisitsCount: stats.completed_visits_count,
      },
      receivables: {
        totalAccrued: primaryDues.totalAccrued,
        totalSettled: primaryDues.totalSettled,
        outstandingDues: primaryDues.outstandingDues,
        creditLimit,
        isLimitExceeded: primaryDues.isLimitExceeded,
        limitUtilizationPercent: creditLimit > 0 ? Math.min(100, Math.round((primaryDues.outstandingDues / creditLimit) * 100)) : 0,
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
      WHERE le.account_id IN ($1,$2)
      ORDER BY le.created_at DESC
      LIMIT $3
    `, [`NURSE_PAYABLE:${nurseId}`,`CASH_HELD_BY_NURSE:${nurseId}`,clampedLimit]);

    return res.rows;
  }
}
