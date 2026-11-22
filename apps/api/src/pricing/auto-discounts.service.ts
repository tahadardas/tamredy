import { Injectable } from '@nestjs/common';
import { localParts, PromoRule } from './pricing.js';
import { Q } from './fees.service.js';

export type AutoKind = 'OFFPEAK' | 'LOYALTY' | 'PACK';
export interface AutoDiscount extends PromoRule { auto: true; kind: AutoKind; label: string; packGrantId?: string; }

/** Discounts applied automatically at order time when no code is used. Only ONE applies: the largest percentage
 *  (tie order: pack > loyalty > off-peak). Every feature is a switch in the marketing page and is OFF by default. */
@Injectable()
export class AutoDiscountService {
  async features(q: Q): Promise<Record<string, { enabled: boolean; config: any }>> {
    const rows = (await q.query('SELECT key,enabled,config FROM marketing_features')).rows;
    return Object.fromEntries(rows.map(r => [r.key, { enabled: r.enabled, config: r.config }]));
  }

  async pick(q: Q, userId: string, now = new Date(), tz = 'Asia/Damascus'): Promise<AutoDiscount | null> {
    const f = await this.features(q);
    const found: (AutoDiscount & { percent: number; rank: number })[] = [];

    if (f.offpeak?.enabled) {
      const c = f.offpeak.config, p = localParts(now, tz);
      const hm = (s: string) => { const [h, m] = String(s).split(':').map(Number); return (h ?? 0) * 60 + (m ?? 0); };
      const inDay = (c.days ?? []).map(Number).includes(p.dow), a = hm(c.start), b = hm(c.end);
      const inTime = a <= b ? p.minutes >= a && p.minutes < b : p.minutes >= a || p.minutes < b;
      if (inDay && inTime && Number(c.percent) > 0)
        found.push({ auto: true, kind: 'OFFPEAK', label: 'خصم الأوقات الهادئة', type: 'PERCENT', value: Number(c.percent), maxDiscount: c.maxDiscount ?? null, percent: Number(c.percent), rank: 1 });
    }

    if (f.loyalty?.enabled) {
      const c = f.loyalty.config, every = Math.max(2, Number(c.everyN));
      const paid = (await q.query(`SELECT count(*)::int AS n FROM care_requests WHERE requester_user_id=$1 AND payment_status='PAID'`, [userId])).rows[0].n;
      if ((paid + 1) % every === 0 && Number(c.percent) > 0)
        found.push({ auto: true, kind: 'LOYALTY', label: `مكافأة الولاء (الطلب ${paid + 1})`, type: 'PERCENT', value: Number(c.percent), maxDiscount: c.maxDiscount ?? null, percent: Number(c.percent), rank: 2 });
    }

    if (f.packs?.enabled) {
      const g = (await q.query(`SELECT g.id,g.name,g.percent,g.visits,
          (SELECT count(*)::int FROM care_requests cr WHERE cr.promo_snapshot->>'packGrantId'=g.id::text AND cr.status NOT IN ('CANCELLED','UNFULFILLED')) AS used
        FROM pack_grants g WHERE g.user_id=$1 AND g.expires_at>now() ORDER BY g.percent DESC,g.expires_at`, [userId])).rows.find(x => x.used < x.visits);
      if (g) found.push({ auto: true, kind: 'PACK', label: `باقة: ${g.name}`, type: 'PERCENT', value: Number(g.percent), maxDiscount: null, percent: Number(g.percent), rank: 3, packGrantId: g.id });
    }

    if (!found.length) return null;
    found.sort((a, b) => b.percent - a.percent || b.rank - a.rank);
    const { percent: _p, rank: _r, ...best } = found[0]!;
    return { ...best, code: best.label };
  }
}
