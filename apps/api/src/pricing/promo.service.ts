import { BadRequestException, HttpException, Injectable, Optional } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import type { PromoRule } from './pricing.js';

type Q = { query: (sql: string, p?: unknown[]) => Promise<{ rows: any[]; rowCount: number | null }> };
export interface PromoRow { id: string; code: string; type: 'PERCENT' | 'FIXED'; value: string; max_discount: string | null; [k: string]: any; }
const fail = (code: string): never => { throw new BadRequestException({ code }); };

export const toRule = (p: PromoRow): PromoRule => ({ code: p.code, type: p.type, value: Number(p.value), maxDiscount: p.max_discount == null ? null : Number(p.max_discount) });

@Injectable()
export class PromoService {
  /** `db` (a separate pool connection) logs attempts even when the surrounding transaction rolls back. */
  constructor(@Optional() private readonly db?: DbService) {}

  private async limits(q: Q) { return (await q.query('SELECT promo_attempts_per_hour,promo_max_orders_30d FROM pricing_settings WHERE id=1')).rows[0]; }

  /** Throws a PROMO_* error when the code cannot be used by this user for this service. */
  async check(q: Q, p: PromoRow, userId: string, serviceId: string, basePrice: number, opts: { ignoreUsage?: boolean } = {}): Promise<void> {
    const now = Date.now();
    if (p.only_user_id && p.only_user_id !== userId) fail('PROMO_NOT_FOUND'); // personal (referral) codes belong to one user
    if (!p.active) fail('PROMO_INACTIVE');
    if (p.valid_from && new Date(p.valid_from).getTime() > now) fail('PROMO_NOT_STARTED');
    if (p.valid_to && new Date(p.valid_to).getTime() < now) fail('PROMO_EXPIRED');
    if (p.service_ids && !p.service_ids.includes(serviceId)) fail('PROMO_NOT_FOR_SERVICE');
    if (Number(p.min_amount) > basePrice) fail('PROMO_MIN_AMOUNT');
    if (opts.ignoreUsage) return;
    const cap = Number((await this.limits(q)).promo_max_orders_30d);
    if (cap > 0) {
      const used = (await q.query(`SELECT count(*)::int AS n FROM care_requests WHERE requester_user_id=$1 AND promo_id IS NOT NULL AND status NOT IN ('CANCELLED','UNFULFILLED') AND created_at>now()-interval '30 days'`, [userId])).rows[0].n;
      if (used >= cap) fail('PROMO_LIMIT_REACHED');
    }
    const u = (await q.query(`SELECT count(*)::int AS total, count(*) FILTER (WHERE requester_user_id=$2)::int AS mine
      FROM care_requests WHERE promo_id=$1 AND status NOT IN ('CANCELLED','UNFULFILLED')`, [p.id, userId])).rows[0];
    if (p.max_redemptions != null && u.total >= p.max_redemptions) fail('PROMO_EXHAUSTED');
    if (u.mine >= p.per_user_limit) fail('PROMO_ALREADY_USED');
    if (p.first_order_only) {
      const any = await q.query(`SELECT 1 FROM care_requests WHERE requester_user_id=$1 AND status NOT IN ('CANCELLED','UNFULFILLED') LIMIT 1`, [userId]);
      if (any.rowCount) fail('PROMO_FIRST_ORDER_ONLY');
    }
  }

  /** Explicit code -> must be valid (error otherwise). No code -> best claimed code, silently skipped if unusable. */
  async resolve(q: Q, userId: string, serviceId: string, basePrice: number, code?: string | null, lock = false): Promise<PromoRow | null> {
    if (code?.trim()) {
      await this.guard(userId);
      try {
        const p = (await q.query(`SELECT * FROM promo_codes WHERE upper(code)=upper($1)${lock ? ' FOR UPDATE' : ''}`, [code.trim()])).rows[0];
        if (!p) return fail('PROMO_NOT_FOUND');
        await this.check(q, p, userId, serviceId, basePrice);
        return p;
      } catch (e) {
        await this.log(userId, false);
        throw e;
      }
    }
    const claimed = (await q.query(`SELECT p.* FROM promo_claims k JOIN promo_codes p ON p.id=k.promo_id WHERE k.user_id=$1 AND p.active ORDER BY k.claimed_at LIMIT 5`, [userId])).rows;
    for (const p of claimed) {
      try { await this.check(q, p, userId, serviceId, basePrice); return p; } catch { /* try the next claimed code */ }
    }
    return null;
  }

  /** Too many wrong codes in an hour (guessing) -> temporarily blocked. */
  async guard(userId: string): Promise<void> {
    if (!this.db) return;
    const limit = Number((await this.limits(this.db)).promo_attempts_per_hour);
    const n = (await this.db.query(`SELECT count(*)::int AS n FROM promo_attempts WHERE user_id=$1 AND NOT ok AND created_at>now()-interval '1 hour'`, [userId])).rows[0].n;
    if (n >= limit) throw new HttpException({ code: 'PROMO_RATE_LIMITED' }, 429);
  }

  async log(userId: string, ok: boolean): Promise<void> {
    try { await this.db?.query('INSERT INTO promo_attempts(user_id,ok) VALUES($1,$2)', [userId, ok]); } catch { /* never block ordering because of logging */ }
  }

  async claim(q: Q, userId: string, code: string): Promise<PromoRow> {
    await this.guard(userId);
    const p = (await q.query('SELECT * FROM promo_codes WHERE upper(code)=upper($1)', [code.trim()])).rows[0];
    if (!p || (p.only_user_id && p.only_user_id !== userId)) { await this.log(userId, false); return fail('PROMO_NOT_FOUND'); }
    await this.check(q, p, userId, p.service_ids?.[0] ?? '', 0, { ignoreUsage: true }).catch(e => {
      if (e.getResponse?.().code !== 'PROMO_NOT_FOR_SERVICE') throw e; // scope is checked when ordering
    });
    await q.query('INSERT INTO promo_claims(user_id,promo_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [userId, p.id]);
    return p;
  }
}
