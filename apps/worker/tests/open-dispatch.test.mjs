import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { doDispatch } from '../src/dispatch.ts';

const scripts = new URL('../../../infra/db/migrations/', import.meta.url);
const migration = (name) => readFileSync(new URL(`${name}.sql`, scripts), 'utf8');

test('open dispatch wakes for new eligible nurses, deduplicates, and enforces the fixed deadline', async (t) => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(migration('001_core').replace(/CREATE EXTENSION[^;]*;/g, '')
    .replaceAll('geography(Point,4326)', 'double precision')
    .replace(/CREATE INDEX[^;]*GIST[^;]*;/g, ''));
  for (const name of ['006_pricing_promos_rewards', '007_fees_tiers_dues_referrals', '021_open_dispatch_and_cancellation_foundation']) {
    await db.exec(migration(name));
  }
  await db.exec(`
    CREATE TABLE IF NOT EXISTS care_request_items (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      request_id uuid NOT NULL,
      service_id uuid NOT NULL
    );
    CREATE TABLE IF NOT EXISTS user_blocks (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      blocker_user_id uuid NOT NULL,
      blocked_user_id uuid NOT NULL,
      revoked_at timestamptz
    );
    CREATE FUNCTION ST_DWithin(double precision,double precision,double precision)
    RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT abs($1-$2)<=$3 $$;
  `);
  await db.exec(migration('022_open_dispatch_eligibility'));
  await db.exec(`
    INSERT INTO users(phone_e164,role) VALUES ('test-patient','PATIENT');
    INSERT INTO beneficiaries(owner_user_id,display_name,consent_status)
      SELECT id,'زيارة اختبارية','GRANTED' FROM users WHERE role='PATIENT';
    INSERT INTO services(code,title_ar,price_amount) VALUES ('TEST','خدمة اختبارية',100);
    INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,
      price_amount,currency_code,commission_bps,search_started_at,search_expires_at,search_radius_meters,
      search_max_heartbeat_seconds,search_max_location_seconds,search_max_accuracy_meters)
    SELECT b.owner_user_id,b.id,s.id,0,'MANUAL_PIN','دمشق',100,'SYP',2000,now()-interval '1 minute',
      now()+interval '1 minute',3000,60,120,100 FROM beneficiaries b CROSS JOIN services s;
    INSERT INTO dispatch_jobs(request_id) SELECT id FROM care_requests;
    INSERT INTO users(phone_e164,role)
      SELECT 'test-nurse-'||i,'NURSE' FROM generate_series(1,102) i;
    INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at)
      SELECT id,true,'OFFLINE','OFFLINE',now() FROM users WHERE role='NURSE';
    INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved)
      SELECT id,'test',now()+interval '1 day',true FROM nurses;
    INSERT INTO nurse_skills(nurse_id,service_id,approved)
      SELECT n.id,s.id,true FROM nurses n CROSS JOIN services s;
    INSERT INTO nurse_locations(nurse_id,location,accuracy_m)
      SELECT n.id,100,CASE WHEN u.phone_e164='test-nurse-102' THEN 101 ELSE 100 END
      FROM nurses n JOIN users u ON u.id=n.user_id;
  `);
  const pool = { connect: async () => ({ query: db.query.bind(db), release() {} }) };
  const count = async (table) => (await db.query(`SELECT count(*)::int AS total FROM ${table}`)).rows[0].total;
  const makeAvailable = async (where) => db.exec(`
    UPDATE nurses n SET work_status='AVAILABLE',availability_intent='AVAILABLE'
    FROM users u WHERE u.id=n.user_id AND ${where};
  `);
  assert.equal(await doDispatch(pool), true);
  assert.equal(await count('request_offers'), 0);

  // Availability change advances the next run even without waiting for reconciliation.
  await makeAvailable("u.phone_e164 <> 'test-nurse-101'");
  assert.equal(await doDispatch(pool), true);
  assert.equal(await count('request_offers'), 100);
  assert.equal(await count('outbox_events'), 100);

  // The last eligible nurse joins via periodic reconciliation if a wake-up was missed.
  await makeAvailable("u.phone_e164='test-nurse-101'");
  await db.exec('UPDATE dispatch_jobs SET next_run_at=now()');
  assert.equal(await doDispatch(pool), true);
  assert.equal(await count('request_offers'), 101);
  assert.equal(await count('outbox_events'), 101);
  assert.equal((await db.query(`
    SELECT bool_and(o.expires_at=r.search_expires_at) AS same
    FROM request_offers o JOIN care_requests r ON r.id=o.request_id
  `)).rows[0].same, true);

  await db.exec(`
    UPDATE care_requests SET search_expires_at=now()-interval '1 second';
    UPDATE dispatch_jobs SET next_run_at=now();
    UPDATE nurse_locations SET accuracy_m=100 WHERE accuracy_m=101;
  `);
  assert.equal(await doDispatch(pool), true);
  assert.equal(await count('request_offers'), 101);
  assert.equal(await count('dispatch_jobs'), 0);
  assert.deepEqual((await db.query('SELECT status,close_reason FROM care_requests')).rows,
    [{ status: 'UNFULFILLED', close_reason: 'EXPIRED' }]);
});
