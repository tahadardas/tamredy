import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { doDispatch } from '../src/dispatch.ts';
import { pushDeliverBatch } from '../src/push.ts';

test('alerts all eligible nurses in each wave and stops widening after assignment', async t => {
  const db = new PGlite({ extensions: { pgcrypto } });
  t.after(() => db.close());
  await db.exec('CREATE EXTENSION IF NOT EXISTS pgcrypto;');
  // Exercise the production SQL with distances represented as meters on one axis.
  for (const migration of ['001_core', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '007_fees_tiers_dues_referrals', '016_expand_dispatch_waves_limit', '018_dispatch_diagnostics_and_deliveries', '019_device_sessions_and_persistent_auth', '021_open_dispatch_and_cancellation_foundation', '042_competitive_expansion_catalog_and_items', '045_health_records_and_clinical_observations', '047_financial_ledger_and_multi_model', '055_financial_source_of_truth', '056_clinical_approval_gate', '063_notifications_routing_and_device_tokens', '067_device_session_generation']) {
    const sql = readFileSync(new URL(`../../../infra/db/migrations/${migration}.sql`, import.meta.url), 'utf8')
      .replace(/CREATE EXTENSION[^;]*;/g, '')
      .replace(/geography\(Point,4326\)/g, 'double precision')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
    await db.exec(sql);
  }
  await db.exec(`
    ALTER TABLE care_requests ADD COLUMN IF NOT EXISTS marketplace_status text;
    CREATE TABLE IF NOT EXISTS care_request_items (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      request_id uuid NOT NULL,
      service_id uuid NOT NULL,
      expected_minutes integer NOT NULL DEFAULT 30
    );
    CREATE TABLE IF NOT EXISTS user_blocks (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      blocker_user_id uuid NOT NULL,
      blocked_user_id uuid NOT NULL,
      revoked_at timestamptz
    );
    CREATE TABLE IF NOT EXISTS nurse_calendar_blocks (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      nurse_id uuid NOT NULL,
      start_time timestamptz NOT NULL,
      end_time timestamptz NOT NULL
    );
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS planned_start_at timestamptz;
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS planned_end_at timestamptz;
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS travel_buffer_before_minutes integer NOT NULL DEFAULT 30;
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS travel_buffer_after_minutes integer NOT NULL DEFAULT 15;
    CREATE FUNCTION nurse_has_schedule_conflict(uuid, timestamptz, timestamptz, uuid)
      RETURNS boolean LANGUAGE sql STABLE AS $$
        SELECT EXISTS (
          SELECT 1 FROM nurse_calendar_blocks b
          WHERE b.nurse_id=$1 AND b.start_time < $3 AND b.end_time > $2
        ) OR EXISTS (
          SELECT 1 FROM request_assignments a
          WHERE a.nurse_id=$1 AND a.status IN ('RESERVED','ACTIVE')
            AND a.planned_start_at IS NOT NULL
            AND ($4 IS NULL OR a.request_id <> $4)
            AND a.planned_start_at - a.travel_buffer_before_minutes * interval '1 minute' < $3
            AND a.planned_end_at + a.travel_buffer_after_minutes * interval '1 minute' > $2
        );
      $$;
    CREATE FUNCTION ST_DWithin(double precision, double precision, double precision)
      RETURNS boolean LANGUAGE sql AS $$ SELECT abs($1 - $2) <= $3 $$;
    ${readFileSync(new URL('../../../infra/db/migrations/022_open_dispatch_eligibility.sql', import.meta.url), 'utf8')}
    CREATE TABLE app_settings (key text PRIMARY KEY, value jsonb);
    INSERT INTO app_settings VALUES ('dispatch', '{"waves":[{"radiusM":3000,"seconds":15,"limit":1},{"radiusM":6000,"seconds":15,"limit":1},{"radiusM":10000,"seconds":20,"limit":1}]}');
    CREATE TABLE marketing_features (key text PRIMARY KEY, enabled boolean);
    INSERT INTO marketing_features VALUES ('alarm',true);
    INSERT INTO users(phone_e164,role) VALUES ('patient','PATIENT');
    INSERT INTO beneficiaries(owner_user_id,display_name,consent_status)
      SELECT id,'أحمد','GRANTED' FROM users;
    INSERT INTO services(code,title_ar,price_amount) VALUES ('visit','زيارة تمريضية',100);
    INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,price_amount,currency_code,commission_bps)
      SELECT b.owner_user_id,b.id,s.id,0,'MANUAL_PIN','دمشق',100,'SYP_NEW',2000 FROM beneficiaries b CROSS JOIN services s WHERE s.code='visit';
    INSERT INTO dispatch_jobs(request_id) SELECT id FROM care_requests;
    INSERT INTO users(phone_e164,role) VALUES
      ('near-a','NURSE'), ('near-b','NURSE'), ('middle','NURSE'), ('far','NURSE'), ('stale','NURSE'), ('outside','NURSE');
    INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at)
      SELECT id,true,'AVAILABLE','AVAILABLE',now() FROM users WHERE role='NURSE';
    INSERT INTO nurse_locations(nurse_id,location,accuracy_m,recorded_at)
      SELECT n.id,d.distance,10,now()-d.age FROM nurses n JOIN users u ON u.id=n.user_id
      JOIN (VALUES ('near-a',500,interval '0'), ('near-b',2500,interval '0'), ('middle',4500,interval '0'),
        ('far',8500,interval '0'), ('stale',800,interval '3 minutes'), ('outside',12000,interval '0')) d(phone,distance,age)
        ON d.phone=u.phone_e164;
    INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved)
      SELECT id,'license',now()+interval '1 day',true FROM nurses;
    INSERT INTO nurse_financial_accounts(nurse_id,financial_model,credit_limit,prepaid_balance)
      SELECT id,'RECEIVABLES',100000,0 FROM nurses;
    INSERT INTO nurse_skills(nurse_id,service_id,approved) SELECT n.id,s.id,true FROM nurses n CROSS JOIN services s;
    INSERT INTO device_sessions(id,user_id,device_id,app_kind)
      SELECT gen_random_uuid(),id,'dev-'||phone_e164,'nurse' FROM users WHERE role='NURSE';
    INSERT INTO device_tokens(user_id,token,platform,session_id,role,app_type)
      SELECT u.id,u.phone_e164 || repeat('x',30),'android',ds.id,'NURSE','NURSE_APP'
      FROM users u JOIN device_sessions ds ON ds.user_id=u.id WHERE u.role='NURSE';
  `);
  const pool = { connect: async () => ({ query: db.query.bind(db), release() {} }) };
  const offers = async () => (await db.query(`
    SELECT u.phone_e164 AS nurse,o.wave_no AS wave FROM request_offers o
      JOIN nurses n ON n.id=o.nurse_id JOIN users u ON u.id=n.user_id ORDER BY wave,nurse
  `)).rows;
  const nextWave = async () => db.exec(`
    UPDATE request_offers SET expires_at=now()-interval '1 second' WHERE status='OPEN';
    UPDATE dispatch_jobs SET next_run_at=now()-interval '1 second';
  `);

  assert.equal(await doDispatch(pool), true);
  assert.deepEqual(await offers(), [{ nurse: 'near-a', wave: 1 }, { nurse: 'near-b', wave: 1 }]);
  assert.equal(await doDispatch(pool), false);
  const events = (await db.query("SELECT * FROM outbox_events WHERE event_type='offer.created' ORDER BY id")).rows;
  const alarms = [];
  const delivery = await pushDeliverBatch(db, {
    async sendAlarmDetailed(token, data, ttl) {
      alarms.push({ token: token.replace(/x+$/, ''), offerId: data.offerId });
      assert.ok(ttl > 0 && ttl <= 15);
      return { result: 'ok' };
    },
  }, events);
  assert.deepEqual(delivery, { sent: 2, failed: 0, pruned: 0 });
  assert.deepEqual(alarms.map(a => a.token).sort(), ['near-a', 'near-b']);
  assert.equal(new Set(alarms.map(a => a.offerId)).size, 2);

  await nextWave();
  assert.equal(await doDispatch(pool), true);
  assert.deepEqual(await offers(), [{ nurse: 'near-a', wave: 1 }, { nurse: 'near-b', wave: 1 }, { nurse: 'middle', wave: 2 }]);
  assert.deepEqual(await pushDeliverBatch(db, {}, events), { sent: 0, failed: 0, pruned: 0 });
  await nextWave();
  assert.equal(await doDispatch(pool), true);
  assert.deepEqual(await offers(), [{ nurse: 'near-a', wave: 1 }, { nurse: 'near-b', wave: 1 }, { nurse: 'middle', wave: 2 }, { nurse: 'far', wave: 3 }]);

  await db.exec("UPDATE care_requests SET status='ASSIGNED'; UPDATE dispatch_jobs SET next_run_at=now()-interval '1 second';");
  assert.equal(await doDispatch(pool), true);
  assert.equal((await db.query('SELECT status FROM care_requests')).rows[0].status, 'ASSIGNED');
  assert.equal((await db.query('SELECT * FROM dispatch_jobs')).rowCount, 0);
  assert.equal((await offers()).length, 4);
  const finalEvents = (await db.query("SELECT * FROM outbox_events WHERE event_type='offer.created' ORDER BY id")).rows;
  assert.deepEqual(await pushDeliverBatch(db, {}, finalEvents), { sent: 0, failed: 0, pruned: 0 });

  await db.exec(`
    UPDATE nurses SET availability_intent='OFFLINE';
    WITH created AS (
      INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,price_amount,currency_code,commission_bps)
      SELECT requester_user_id,beneficiary_id,service_id,location,location_source,address_text,price_amount,currency_code,commission_bps
      FROM care_requests WHERE status='ASSIGNED' RETURNING id
    )
    INSERT INTO dispatch_jobs(request_id) SELECT id FROM created;
  `);
  for (let step = 0; step < 4; step++) assert.equal(await doDispatch(pool), true);
  assert.equal(await doDispatch(pool), false);
  assert.equal((await db.query("SELECT id FROM care_requests WHERE status='UNFULFILLED'")).rowCount, 1);
  assert.equal((await db.query("SELECT id FROM outbox_events WHERE event_type='request.unfulfilled'")).rowCount, 1);
});
