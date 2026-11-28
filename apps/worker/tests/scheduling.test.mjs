import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { releaseScheduledVisit } from '../src/scheduling.ts';
import { saveSchedule, validateAppointment } from '../../api/dist/scheduling/scheduling.js';

const migrations = new URL('../../../infra/db/migrations/', import.meta.url);
const sql = (name) => readFileSync(new URL(name + '.sql', migrations), 'utf8');

test('scheduled visits wait, then release once; late and cancelled visits do not dispatch', async (t) => {
  const previous = process.env.SCHEDULED_VISITS_ENABLED;
  const previousOpen = process.env.OPEN_DISPATCH_ENABLED;
  process.env.SCHEDULED_VISITS_ENABLED = 'true';
  process.env.OPEN_DISPATCH_ENABLED = 'true';
  t.after(() => {
    if (previous === undefined) delete process.env.SCHEDULED_VISITS_ENABLED;
    else process.env.SCHEDULED_VISITS_ENABLED = previous;
    if (previousOpen === undefined) delete process.env.OPEN_DISPATCH_ENABLED;
    else process.env.OPEN_DISPATCH_ENABLED = previousOpen;
  });
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(sql('001_core').replace(/CREATE EXTENSION[^;]*;/g, '')
    .replaceAll('geography(Point,4326)', 'double precision').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, ''));
  await db.exec('CREATE FUNCTION ST_DWithin(double precision,double precision,double precision) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT abs($1-$2)<=$3 $$');
  for (const name of ['003_admin_reads_audit', '006_pricing_promos_rewards', '007_fees_tiers_dues_referrals',
    '009_nurse_admin_documents_settings', '021_open_dispatch_and_cancellation_foundation', '022_open_dispatch_eligibility',
    '027_scheduled_visits','056_clinical_approval_gate']) {
    await db.exec(sql(name));
  }
  await db.exec(`
    INSERT INTO users(phone_e164,role) VALUES ('test-patient','PATIENT');
    INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) SELECT id,'موعد','GRANTED' FROM users;
    INSERT INTO services(code,title_ar,price_amount) VALUES ('TEST','خدمة اختبارية',100);
    INSERT INTO app_settings(key,value) VALUES ('dispatch','{"openEnabled":true}') ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value;
    INSERT INTO app_settings(key,value) VALUES ('orders','{"accepting":true}') ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value;
  `);
  const makeVisit = async (status) => (await db.query(`
    INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,
      price_amount,currency_code,commission_bps,status)
    SELECT b.owner_user_id,b.id,s.id,0,'MANUAL_PIN','دمشق',100,'SYP',2000,$1
    FROM beneficiaries b CROSS JOIN services s RETURNING id
  `, [status])).rows[0].id;
  const pool = { connect: async () => ({ query: db.query.bind(db), release() {} }) };
  const due = await makeVisit('SCHEDULED');
  await saveSchedule(db, due, validateAppointment(new Date(Date.now() + 3600000).toISOString()));
  assert.equal(await releaseScheduledVisit(pool), false);
  await db.query("UPDATE scheduled_visits SET appointment_at=now()+interval '10 minutes',release_at=now()-interval '5 minutes' WHERE request_id=$1", [due]);
  process.env.SCHEDULED_VISITS_ENABLED='false';
  assert.equal(await releaseScheduledVisit(pool), false);
  assert.equal((await db.query('SELECT status FROM care_requests WHERE id=$1',[due])).rows[0].status,'SCHEDULED');
  process.env.SCHEDULED_VISITS_ENABLED='true';
  await db.query("DELETE FROM app_settings WHERE key='orders'");
  assert.equal(await releaseScheduledVisit(pool), false);
  await db.query(`INSERT INTO app_settings(key,value) VALUES('orders','{"accepting":true}')`);
  assert.equal(await releaseScheduledVisit(pool), true);
  assert.equal(await releaseScheduledVisit(pool), false);
  const started = (await db.query('SELECT status, search_expires_at FROM care_requests WHERE id=$1', [due])).rows[0];
  assert.equal(started.status, 'OFFERING');
  assert.ok(started.search_expires_at);
  const late = await makeVisit('SCHEDULED');
  const cancelled = await makeVisit('CANCELLED');
  for (const id of [late, cancelled]) await saveSchedule(db, id, new Date(Date.now() - 3600000));
  assert.equal(await releaseScheduledVisit(pool), true);
  assert.equal(await releaseScheduledVisit(pool), false);
  assert.deepEqual((await db.query('SELECT request_id FROM dispatch_jobs')).rows, [{ request_id: due }]);
  assert.equal((await db.query('SELECT status FROM care_requests WHERE id=$1', [late])).rows[0].status, 'UNFULFILLED');
});
