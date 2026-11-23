import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { alarmMessage, pushCopy } from '../src/push.ts';
import { processBroadcast, runWinback } from '../src/marketing.ts';

const root = resolve(import.meta.dirname, '../../..');
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
async function freshDb() {
  const pg = new PGlite();
  for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '007_fees_tiers_dues_referrals', '008_marketing', '009_nurse_admin_documents_settings', '010_self_registration', '011_regions', '012_area_coordinates', '013_default_password', '014_applications_doc_kinds'])
    await pg.exec(strip(readFileSync(resolve(root, `infra/db/migrations/${f}.sql`), 'utf8')));
  return pg;
}
const id = async (pg, sql, p) => (await pg.query(sql, p)).rows[0].id;

test('new-request alarm: data-only on Android, long loud tone on iOS, TTL = offer lifetime', () => {
  const m = alarmMessage('tok', { type: 'offer.created', offerId: 'o1' }, 18, { title: 'طلب جديد', body: 'افتح' }).message;
  assert.match(pushCopy('winback.offer', { percent: 15 }).body, /15%/);
  assert.equal(m.notification, undefined);                 // data-only so the app raises the insistent alarm itself
  assert.equal(m.data.alarm, '1'); assert.equal(m.data.ttl, '18');
  assert.equal(m.android.priority, 'HIGH'); assert.equal(m.android.ttl, '18s');
  assert.equal(m.apns.payload.aps.sound, 'tamreedy_alert.caf');
  assert.equal(m.apns.payload.aps['interruption-level'], 'time-sensitive');
  assert.equal(alarmMessage('t', {}, 1000, { title: 'a', body: 'b' }).message.android.ttl, '300s'); // capped
  assert.equal(alarmMessage('t', {}, 0, { title: 'a', body: 'b' }).message.android.ttl, '0s');
});

test('broadcast: sent once to the right audience (opt-in patients only), counts recorded, dead tokens pruned', async () => {
  const pg = await freshDb();
  const admin = await id(pg, `INSERT INTO users(phone_e164,role) VALUES('+1','ADMIN') RETURNING id`);
  const yes = await id(pg, `INSERT INTO users(phone_e164,role,marketing_opt_in) VALUES('+2','PATIENT',true) RETURNING id`);
  const no = await id(pg, `INSERT INTO users(phone_e164,role) VALUES('+3','PATIENT') RETURNING id`);
  for (const [u, t] of [[yes, 'tok-yes-' + 'a'.repeat(20)], [yes, 'tok-dead-' + 'b'.repeat(20)], [no, 'tok-no-' + 'c'.repeat(20)]])
    await pg.query(`INSERT INTO device_tokens(user_id,token,platform) VALUES($1,$2,'android')`, [u, t]);
  const b = await id(pg, `INSERT INTO broadcasts(audience,title,body,promo_code,total,created_by) VALUES('ALL_PATIENTS','عرض','خصم اليوم','HELLO',2,$1) RETURNING id`, [admin]);
  const sentTo = [];
  const fcm = { send: async (t, msg) => { sentTo.push([t, msg.body]); return t.includes('dead') ? 'unregistered' : 'ok'; } };
  assert.equal(await processBroadcast(pg, fcm), true);
  assert.equal(await processBroadcast(pg, fcm), false);   // nothing left: never sent twice
  assert.equal(sentTo.length, 2); assert.ok(sentTo.every(([t]) => !t.includes('tok-no-')));
  assert.match(sentTo[0][1], /الكود: HELLO/);
  const row = (await pg.query('SELECT status,sent,failed,total FROM broadcasts WHERE id=$1', [b])).rows[0];
  assert.deepEqual([row.status, row.sent, row.failed, row.total], ['DONE', 1, 1, 2]);
  assert.equal((await pg.query(`SELECT count(*)::int n FROM device_tokens WHERE token LIKE 'tok-dead-%'`)).rows[0].n, 0);
});

test('broadcast without FCM configured is marked FAILED, never faked as sent', async () => {
  const pg = await freshDb();
  const admin = await id(pg, `INSERT INTO users(phone_e164,role) VALUES('+1','ADMIN') RETURNING id`);
  const b = await id(pg, `INSERT INTO broadcasts(audience,title,body,total,created_by) VALUES('ALL_NURSES','تنبيه','نص',3,$1) RETURNING id`, [admin]);
  await processBroadcast(pg, undefined);
  assert.equal((await pg.query('SELECT status FROM broadcasts WHERE id=$1', [b])).rows[0].status, 'FAILED');
});

test('win-back: only while switched on, only opted-in lapsed customers, one personal single-use code each, once per period', async () => {
  const pg = await freshDb();
  const mk = async (phone, optIn) => id(pg, `INSERT INTO users(phone_e164,role,marketing_opt_in) VALUES($1,'PATIENT',$2) RETURNING id`, [phone, optIn]);
  const lapsed = await mk('+10', true), recent = await mk('+11', true), noConsent = await mk('+12', false), neverOrdered = await mk('+13', true);
  const svc = await id(pg, `INSERT INTO services(code,title_ar,price_amount) VALUES('S','x',100) RETURNING id`);
  const order = async (u, daysAgo) => {
    const b = await id(pg, `INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'م','GRANTED') RETURNING id`, [u]);
    await pg.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,payment_status,created_at)
      VALUES($1,$2,$3,'x','MANUAL_PIN','a','COMPLETED',100,'SYP_NEW',2000,'PAID',now()-($4||' days')::interval)`, [u, b, svc, String(daysAgo)]);
  };
  await order(lapsed, 45); await order(recent, 3); await order(noConsent, 45);
  for (const u of [lapsed, recent, noConsent, neverOrdered]) await pg.query(`INSERT INTO device_tokens(user_id,token,platform) VALUES($1,$2,'android')`, [u, 'tok-' + u + 'z'.repeat(10)]);
  assert.equal(await runWinback(pg), 0);                                  // feature is OFF by default
  await pg.query(`UPDATE marketing_features SET enabled=true WHERE key='winback'`);
  assert.equal(await runWinback(pg), 1);                                  // only the lapsed, consenting customer
  const promo = (await pg.query(`SELECT code,only_user_id,max_redemptions,source,value FROM promo_codes WHERE source='WINBACK'`)).rows;
  assert.equal(promo.length, 1); assert.equal(promo[0].only_user_id, lapsed); assert.equal(promo[0].max_redemptions, 1);
  assert.equal((await pg.query(`SELECT count(*)::int n FROM promo_claims WHERE user_id=$1`, [lapsed])).rows[0].n, 1);
  assert.equal((await pg.query(`SELECT count(*)::int n FROM outbox_events WHERE event_type='winback.offer'`)).rows[0].n, 1);
  assert.equal(await runWinback(pg), 0);                                  // not again within the same period
});
