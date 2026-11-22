import { BadRequestException, HttpException, Injectable } from '@nestjs/common';
import { randomInt } from 'node:crypto';
import { Q } from './fees.service.js';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const rnd = (n: number) => Array.from({ length: n }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
const fail = (code: string): never => { throw new BadRequestException({ code }); };

/** Personal referral codes: a new patient enters a friend's code before their first order and gets a welcome discount;
 *  when that first order is fully paid the referrer earns a discount too. Rewards are single-use promo codes owned by one user. */
@Injectable()
export class ReferralService {
  async myCode(q: Q, userId: string): Promise<string> {
    const cur = (await q.query('SELECT referral_code FROM users WHERE id=$1', [userId])).rows[0];
    if (cur?.referral_code) return cur.referral_code;
    for (let i = 0; i < 8; i++) {
      const code = `TM${rnd(6)}`;
      const r = await q.query('UPDATE users SET referral_code=$2 WHERE id=$1 AND referral_code IS NULL AND NOT EXISTS(SELECT 1 FROM users WHERE referral_code=$2) RETURNING referral_code', [userId, code]);
      if (r.rowCount) return code;
      const again = (await q.query('SELECT referral_code FROM users WHERE id=$1', [userId])).rows[0];
      if (again?.referral_code) return again.referral_code;
    }
    throw new HttpException({ code: 'REFERRAL_CODE_GENERATION_FAILED' }, 503);
  }

  async summary(q: Q, userId: string) {
    const s = (await q.query('SELECT referral_enabled,referral_referred_percent,referral_referrer_percent,referral_max_discount FROM pricing_settings WHERE id=1')).rows[0];
    const st = (await q.query(`SELECT count(*)::int AS invited,count(rewarded_at)::int AS rewarded FROM referrals WHERE referrer_id=$1`, [userId])).rows[0];
    const mine = (await q.query('SELECT 1 FROM referrals WHERE referred_id=$1', [userId])).rowCount;
    return {
      enabled: s.referral_enabled, code: s.referral_enabled ? await this.myCode(q, userId) : null, invited: st.invited, rewarded: st.rewarded,
      alreadyReferred: !!mine, friendGets: Number(s.referral_referred_percent), youGet: Number(s.referral_referrer_percent), maxDiscount: Number(s.referral_max_discount),
    };
  }

  /** A new patient enters a friend's code. Must be before their first order; one referrer per user; never your own code. */
  async claim(q: Q, userId: string, rawCode: string) {
    const s = (await q.query('SELECT * FROM pricing_settings WHERE id=1')).rows[0];
    if (!s.referral_enabled) return fail('REFERRAL_DISABLED');
    const referrer = (await q.query(`SELECT id FROM users WHERE referral_code=upper($1) AND role='PATIENT' AND status='ACTIVE'`, [rawCode.trim()])).rows[0];
    if (!referrer) return fail('REFERRAL_CODE_NOT_FOUND');
    if (referrer.id === userId) return fail('REFERRAL_OWN_CODE');
    if ((await q.query('SELECT 1 FROM referrals WHERE referred_id=$1', [userId])).rowCount) return fail('REFERRAL_ALREADY_USED');
    if ((await q.query(`SELECT 1 FROM care_requests WHERE requester_user_id=$1 AND status NOT IN ('CANCELLED','UNFULFILLED') LIMIT 1`, [userId])).rowCount) return fail('REFERRAL_ONLY_BEFORE_FIRST_ORDER');
    await q.query('INSERT INTO referrals(referrer_id,referred_id) VALUES($1,$2)', [referrer.id, userId]);
    const promo = await this.issue(q, userId, Number(s.referral_referred_percent), Number(s.referral_max_discount), 30, true, 'ترحيب بدعوة صديق');
    return { claimed: true, discountPercent: Number(s.referral_referred_percent), promoCode: promo };
  }

  /** Called when an order becomes fully PAID: if it is the referred user's first paid order, reward the referrer once. */
  async rewardIfFirstPaid(q: Q, userId: string): Promise<string | null> {
    const ref = (await q.query('SELECT id,referrer_id FROM referrals WHERE referred_id=$1 AND rewarded_at IS NULL FOR UPDATE', [userId])).rows[0];
    if (!ref) return null;
    const s = (await q.query('SELECT * FROM pricing_settings WHERE id=1')).rows[0];
    if (!s.referral_enabled) return null;
    const paid = (await q.query(`SELECT count(*)::int AS n FROM care_requests WHERE requester_user_id=$1 AND payment_status='PAID'`, [userId])).rows[0].n;
    if (paid !== 1) return null; // only the first paid order triggers the reward
    const month = (await q.query(`SELECT count(*)::int AS n FROM referrals WHERE referrer_id=$1 AND rewarded_at>=date_trunc('month',now())`, [ref.referrer_id])).rows[0].n;
    if (month >= Number(s.referral_max_rewards_per_month)) return null; // monthly cap against farming
    await q.query('UPDATE referrals SET rewarded_at=now() WHERE id=$1', [ref.id]);
    return this.issue(q, ref.referrer_id, Number(s.referral_referrer_percent), Number(s.referral_max_discount), 60, false, 'مكافأة دعوة صديق');
  }

  /** Single-use promo restricted to one user, claimed automatically so it applies to their next order. */
  private async issue(q: Q, userId: string, percent: number, maxDiscount: number, days: number, firstOrderOnly: boolean, description: string) {
    const code = `R-${rnd(8)}`;
    const p = (await q.query(`INSERT INTO promo_codes(code,description,type,value,max_discount,max_redemptions,per_user_limit,first_order_only,valid_to,source,only_user_id,active)
      VALUES($1,$2,'PERCENT',$3,$4,1,1,$5,now()+($6||' days')::interval,'REFERRAL',$7,true) RETURNING id`, [code, description, percent, maxDiscount, firstOrderOnly, String(days), userId])).rows[0];
    await q.query('INSERT INTO promo_claims(user_id,promo_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [userId, p.id]);
    return code;
  }
}
