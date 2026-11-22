import { randomInt } from 'node:crypto';
import type { Db } from './push.js';

type Sender = { send: (token: string, msg: { title: string; body: string }, data: Record<string, string>) => Promise<'ok' | 'unregistered' | 'error'> };

/** Same audiences as the API (patients only if they opted in to marketing). */
export const AUDIENCE_SQL: Record<string, string> = {
  ALL_PATIENTS: `u.role='PATIENT' AND u.status='ACTIVE' AND u.marketing_opt_in`,
  ALL_NURSES: `u.role='NURSE' AND u.status='ACTIVE'`,
  AVAILABLE_NURSES: `u.role='NURSE' AND u.status='ACTIVE' AND EXISTS(SELECT 1 FROM nurses n WHERE n.user_id=u.id AND n.work_status='AVAILABLE')`,
};

/** Delivers ONE queued broadcast (claimed atomically so several workers never send it twice). Returns true if it did work. */
export async function processBroadcast(db: Db, fcm: Sender | undefined, concurrency = 20): Promise<boolean> {
  const claimed = (await db.query(`UPDATE broadcasts SET status='SENDING' WHERE id=(
      SELECT id FROM broadcasts WHERE status='QUEUED' ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *`)).rows[0];
  if (!claimed) return false;
  if (!fcm) { // push not configured: do not pretend it was sent
    await db.query(`UPDATE broadcasts SET status='FAILED',failed=total,finished_at=now() WHERE id=$1`, [claimed.id]);
    return true;
  }
  const where = AUDIENCE_SQL[claimed.audience];
  const tokens: string[] = where ? (await db.query(`SELECT t.token FROM users u JOIN device_tokens t ON t.user_id=u.id WHERE ${where}`)).rows.map(r => r.token) : [];
  let sent = 0, failed = 0;
  const dead: string[] = [];
  const data = { type: 'broadcast', broadcastId: claimed.id, promoCode: claimed.promo_code ?? '' };
  for (let i = 0; i < tokens.length; i += concurrency) {
    await Promise.all(tokens.slice(i, i + concurrency).map(async t => {
      const r = await fcm.send(t, { title: claimed.title, body: claimed.promo_code ? `${claimed.body}\nالكود: ${claimed.promo_code}` : claimed.body }, data);
      if (r === 'ok') sent++; else { failed++; if (r === 'unregistered') dead.push(t); }
    }));
  }
  if (dead.length) await db.query('DELETE FROM device_tokens WHERE token=ANY($1::text[])', [dead]);
  await db.query(`UPDATE broadcasts SET status='DONE',sent=$2,failed=$3,total=$4,finished_at=now() WHERE id=$1`, [claimed.id, sent, failed, tokens.length]);
  return true;
}

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const rnd = (n: number) => Array.from({ length: n }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');

/** Win-back: patients who ordered before, opted in, and have been inactive for N days get a personal single-use code + a push.
 *  Switched on/off from the marketing page; each patient gets at most one per inactivity period. */
export async function runWinback(db: Db): Promise<number> {
  const f = (await db.query(`SELECT enabled,config FROM marketing_features WHERE key='winback'`)).rows[0];
  if (!f?.enabled) return 0;
  const c = f.config;
  const users = (await db.query(`SELECT u.id FROM users u
    WHERE u.role='PATIENT' AND u.status='ACTIVE' AND u.marketing_opt_in
      AND (u.last_winback_at IS NULL OR u.last_winback_at < now() - ($1||' days')::interval)
      AND EXISTS (SELECT 1 FROM care_requests cr WHERE cr.requester_user_id=u.id AND cr.payment_status='PAID')
      AND NOT EXISTS (SELECT 1 FROM care_requests cr WHERE cr.requester_user_id=u.id AND cr.created_at > now() - ($1||' days')::interval)
      AND EXISTS (SELECT 1 FROM device_tokens t WHERE t.user_id=u.id)
    LIMIT $2`, [String(c.inactiveDays), Number(c.maxPerRun)])).rows;
  for (const u of users) {
    const code = `W-${rnd(8)}`;
    const p = (await db.query(`INSERT INTO promo_codes(code,description,type,value,max_discount,max_redemptions,per_user_limit,valid_to,source,only_user_id,active)
      VALUES($1,'استرجاع عميل','PERCENT',$2,$3,1,1,now()+($4||' days')::interval,'WINBACK',$5,true) RETURNING id`,
      [code, c.percent, c.maxDiscount ?? null, String(c.validDays), u.id])).rows[0];
    await db.query('INSERT INTO promo_claims(user_id,promo_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [u.id, p.id]);
    await db.query('UPDATE users SET last_winback_at=now() WHERE id=$1', [u.id]);
    await db.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('winback.offer',$1,$2::jsonb)`, [p.id, JSON.stringify({ recipientUserId: u.id, percent: Number(c.percent) })]);
  }
  return users.length;
}
