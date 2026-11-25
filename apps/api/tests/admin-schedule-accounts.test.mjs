import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { AdminScheduleService } from '../dist/admin/admin-schedule.service.js';
import { removeAccount } from '../dist/admin/account-removal.js';

test('admin schedules use actual arrivals and guard removal of live work', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  const migrations = new URL('../../../infra/db/migrations/', import.meta.url);
  for (const name of ['001_core','003_admin_reads_audit','004_auth_otp_refresh','005_password_accounts_push',
    '009_nurse_admin_documents_settings','019_device_sessions_and_persistent_auth','021_open_dispatch_and_cancellation_foundation','025_manual_password_recovery',
    '027_scheduled_visits','044_smart_scheduling_and_recurring','050_smart_booking_and_open_marketplace','052_admin_scheduled_visit_removal']) {
    const sql = await readFile(new URL(name + '.sql', migrations), 'utf8');
    await db.exec(sql.replace(/CREATE EXTENSION[^;]*;/g,'').replace(/geography\(Point,\s*4326\)/g,'text')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/g,''));
  }
  const user = async (phone,role,name) => (await db.query(
    'INSERT INTO users(phone_e164,role,display_name) VALUES($1,$2,$3) RETURNING id',[phone,role,name])).rows[0].id;
  const admin = await user('+963911111111','ADMIN','المشرف');
  const patient = await user('+963922222222','PATIENT','المريض');
  const nurse = await user('+963933333333','NURSE','الممرض الأول');
  const second = await user('+963944444444','NURSE','الممرض الثاني');
  const seed = (await db.query(`WITH b AS (
    INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'مستفيد','GRANTED') RETURNING id
  ), s AS (INSERT INTO services(code,title_ar,price_amount) VALUES('T','تبديل ضماد',100) RETURNING id)
  SELECT b.id AS beneficiary,s.id AS service FROM b,s`, [patient])).rows[0];
  const visit = async status => (await db.query(`WITH r AS (
    INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,
      price_amount,currency_code,commission_bps,status)
    VALUES($1,$2,$3,'33,36','MANUAL_PIN','دمشق',100,'SYP',100,$4) RETURNING id
  ) INSERT INTO scheduled_visits(request_id,appointment_at,release_at)
    SELECT id,now()+interval '1 day',now()+interval '23 hours' FROM r RETURNING request_id`,
  [patient,seed.beneficiary,seed.service,status])).rows[0].request_id;
  const completed = await visit('COMPLETED');
  const assigned = await visit('ASSIGNED');
  const booked = await visit('SCHEDULED');
  await db.query(`WITH n AS (INSERT INTO nurses(user_id) VALUES($1),($2) RETURNING id,user_id)
    INSERT INTO request_assignments(request_id,nurse_id,status)
    SELECT CASE WHEN user_id=$1 THEN $3::uuid ELSE $4::uuid END,id,
      CASE WHEN user_id=$1 THEN 'RELEASED' ELSE 'ACTIVE' END FROM n`, [nurse,second,completed,assigned]);
  await db.query('INSERT INTO visits(assignment_id,arrived_at,completed_at) SELECT id,now(),now() FROM request_assignments WHERE request_id=$1',[completed]);
  const schedule = new AdminScheduleService(db);
  const {items} = await schedule.list(false,1);
  assert.equal(items.find(v => v.id === completed).arrived_nurse,'الممرض الأول');
  assert.equal(items.find(v => v.id === assigned).assigned_nurse,'الممرض الثاني');
  assert.equal(items.find(v => v.id === assigned).arrived_at,null);
  assert.deepEqual(await schedule.plans(1),{items:[],hasMore:false});
  await assert.rejects(schedule.remove(admin,assigned), {response:{code:'SCHEDULE_VISIT_IN_PROGRESS'}});
  await assert.rejects(db.transaction(c => removeAccount(c,admin,patient)), {response:{code:'ACCOUNT_HAS_ACTIVE_REQUESTS'}});
  await schedule.remove(admin,booked);
  await schedule.remove(admin,completed);
  await schedule.remove(admin,completed);
  assert.deepEqual((await schedule.list(true,1)).items.map(v => v.status).sort(),['CANCELLED','COMPLETED']);
  assert.equal((await db.query('SELECT count(*)::int AS count FROM visits')).rows[0].count,1);
  assert.equal((await db.query("SELECT payload FROM outbox_events WHERE event_type='request.cancelled'")).rows[0].payload.recipientUserIds[0],patient);
  await db.query("INSERT INTO device_sessions(user_id,device_id) VALUES($1,'phone')",[nurse]);
  await db.query("INSERT INTO device_tokens(user_id,token,platform) VALUES($1,'test-token','android')",[nurse]);
  await db.transaction(c => removeAccount(c,admin,nurse));
  const deleted = (await db.query('SELECT status,phone_e164,auth_version FROM users WHERE id=$1',[nurse])).rows[0];
  assert.equal(deleted.status,'DELETED');
  assert.equal(deleted.phone_e164,'deleted-'+nurse);
  assert.ok(deleted.auth_version);
  assert.equal((await db.query('SELECT * FROM device_tokens WHERE user_id=$1',[nurse])).rows.length,0);
  assert.ok((await db.query('SELECT revoked_at FROM device_sessions WHERE user_id=$1',[nurse])).rows[0].revoked_at);
  assert.equal((await schedule.list(true,1)).items.find(v => v.id === completed).arrived_nurse,'الممرض الأول');
  assert.equal((await db.query("SELECT count(*)::int AS count FROM audit_log WHERE action='request.schedule_removed'")).rows[0].count,2);
  await assert.rejects(db.transaction(c => removeAccount(c,admin,admin)), {response:{code:'CANNOT_DELETE_SELF'}});
});
