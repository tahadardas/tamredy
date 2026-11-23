import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { DispatchService } from '../dist/dispatch/dispatch.service.js';
import { AppealsService } from '../dist/requests/appeals.service.js';
import { CommitmentService } from '../dist/requests/commitment.service.js';
import { cancelRequest } from '../dist/requests/cancellation.service.js';

const migrations = new URL('../../../infra/db/migrations/', import.meta.url);
const read = (name) => readFileSync(new URL(`${name}.sql`, migrations), 'utf8');

test('acceptance, fixed ETA and cancellation maintain a single replayable result', async (t) => {
  const pg = new PGlite();
  t.after(() => pg.close());
  await pg.exec(read('001_core').replace(/CREATE EXTENSION[^;]*;/g, '')
    .replaceAll('geography(Point,4326)', 'double precision')
    .replace(/CREATE INDEX[^;]*GIST[^;]*;/g, ''));
  for (const name of ['003_admin_reads_audit', '006_pricing_promos_rewards', '007_fees_tiers_dues_referrals', '021_open_dispatch_and_cancellation_foundation']) {
    await pg.exec(read(name));
  }
  await pg.exec(`
    CREATE FUNCTION ST_DWithin(double precision,double precision,double precision)
      RETURNS boolean LANGUAGE sql AS $$ SELECT abs($1-$2)<=$3 $$;
    CREATE FUNCTION ST_Distance(double precision,double precision)
      RETURNS numeric LANGUAGE sql AS $$ SELECT abs($1-$2)::numeric $$;
    CREATE DOMAIN geometry AS double precision;
    CREATE FUNCTION ST_Y(geometry) RETURNS double precision LANGUAGE sql AS $$ SELECT 33.5::double precision $$;
    CREATE FUNCTION ST_X(geometry) RETURNS double precision LANGUAGE sql AS $$ SELECT 36.25::double precision $$;
  `);
  await pg.exec(read('022_open_dispatch_eligibility'));
  await pg.exec(`
    CREATE TABLE app_settings(key text PRIMARY KEY, value jsonb);
    INSERT INTO users(phone_e164,role) VALUES ('patient-1','PATIENT'),('nurse-1','NURSE');
    INSERT INTO beneficiaries(owner_user_id,display_name,consent_status)
      SELECT id,'زيارة اختبارية','GRANTED' FROM users WHERE role='PATIENT';
    INSERT INTO services(code,title_ar,price_amount) VALUES ('TEST','خدمة اختبارية',100);
    INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,
      price_amount,currency_code,commission_bps,search_started_at,search_expires_at,search_radius_meters,
      search_max_heartbeat_seconds,search_max_location_seconds,search_max_accuracy_meters)
    SELECT b.owner_user_id,b.id,s.id,0,'MANUAL_PIN','دمشق',100,'SYP',2000,now()-interval '1 minute',
      now()+interval '1 minute',3000,60,120,100 FROM beneficiaries b CROSS JOIN services s;
    INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at)
      SELECT id,true,'AVAILABLE','AVAILABLE',now() FROM users WHERE role='NURSE';
    INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved)
      SELECT id,'test',now()+interval '1 day',true FROM nurses;
    INSERT INTO nurse_skills(nurse_id,service_id,approved) SELECT n.id,s.id,true FROM nurses n CROSS JOIN services s;
    INSERT INTO nurse_locations(nurse_id,location,accuracy_m) SELECT id,100,50 FROM nurses;
    INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
      SELECT r.id,n.id,1,now()-interval '1 second' FROM care_requests r CROSS JOIN nurses n;
  `);
  const query = pg.query.bind(pg);
  let inTransaction = false;
  const db = {
    query,
    async transaction(run) {
      await query('BEGIN');
      inTransaction = true;
      try {
        const result = await run({query});
        await query('COMMIT');
        return result;
      } catch (error) {
        await query('ROLLBACK');
        throw error;
      } finally {
        inTransaction = false;
      }
    },
  };
  let routeCalls = 0;
  const routes = { configured: true, provider: 'google', async compute() {
    assert.equal(inTransaction, false);
    routeCalls++;
    return {durationSeconds: 600, distanceMeters: 1000, polyline: 'test'};
  }};
  const dispatch = new DispatchService(db, undefined, undefined, routes);
  const {offer, user_id: nurse} = (await query('SELECT o.id AS offer,n.user_id FROM request_offers o JOIN nurses n ON n.id=o.nurse_id')).rows[0];
  await assert.rejects(dispatch.accept(nurse, offer), error => error.getStatus() === 410);
  await query(`UPDATE request_offers SET expires_at=(SELECT search_expires_at FROM care_requests)`);
  const first = await dispatch.accept(nurse, offer);
  assert.equal(first.status, 'ASSIGNED');
  assert.equal(first.replayed, false);
  assert.equal(routeCalls, 0);
  assert.equal((await query('SELECT departed_at FROM request_assignments')).rows[0].departed_at, null);
  const departed = await dispatch.transition(nurse, first.assignmentId, 'depart');
  assert.equal(departed.status, 'EN_ROUTE');
  const replay = await dispatch.accept(nurse, offer);
  assert.equal(replay.assignmentId, first.assignmentId);
  assert.equal(replay.status, 'EN_ROUTE');
  assert.equal(replay.replayed, true);
  await dispatch.transition(nurse, first.assignmentId, 'depart');
  assert.equal(routeCalls, 1);
  const snapshot = (await query(`SELECT eta_status,eta_provider,
    EXTRACT(EPOCH FROM expected_arrival_at-departed_at)::int AS duration FROM request_assignments`)).rows[0];
  assert.deepEqual(snapshot, { eta_status: 'AVAILABLE', eta_provider: 'google', duration: 600 });
  const patient = (await query("SELECT id FROM users WHERE role='PATIENT'")).rows[0].id;
  const cancel = (dto) => db.transaction(client => cancelRequest(client,patient,first.requestId,dto));
  const payload = {reasonCode:'HEALTH_CIRCUMSTANCE_CHANGED',reasonNote:'تفاصيل اختبار خاصة',idempotencyKey:'cancel-1'};
  await assert.rejects(cancel(payload), error => error.getResponse().code === 'CANCELLATION_POLICY_ACK_REQUIRED');
  const accepted = await cancel({...payload,policyAcknowledged:true});
  assert.equal(accepted.commitmentImpact,true);
  assert.equal(accepted.policyClassification,'EN_ROUTE_COUNTED');
  assert.equal((await cancel({...payload,policyAcknowledged:true})).replayed,true);
  await assert.rejects(cancel({...payload,reasonCode:'OTHER',policyAcknowledged:true}),
    error => error.getResponse().code === 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD');
  const events = (await query("SELECT payload FROM outbox_events WHERE event_type='request.cancelled'")).rows;
  assert.equal(events.length, 1);
  assert.doesNotMatch(JSON.stringify(events),/HEALTH_CIRCUMSTANCE_CHANGED|تفاصيل اختبار خاصة/);
  assert.equal((await query("SELECT status FROM request_assignments")).rows[0].status,'RELEASED');
  const commitment = new CommitmentService(db);
  assert.equal((await commitment.ownHistory(patient)).countedCancellations,1);
  await assert.rejects(commitment.forActiveOffer(nurse,offer),error => error.getStatus() === 404);
  const newOffer = (await query(`
    WITH next_request AS (
      INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,
        price_amount,currency_code,commission_bps)
      SELECT requester_user_id,beneficiary_id,service_id,location,location_source,address_text,
        price_amount,currency_code,commission_bps FROM care_requests WHERE id=$1 RETURNING id
    )
    INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
    SELECT r.id,n.id,1,now()+interval '1 minute' FROM next_request r CROSS JOIN nurses n RETURNING id
  `,[first.requestId])).rows[0].id;
  assert.deepEqual(await commitment.forActiveOffer(nurse,newOffer), {sufficient:false,lookbackDays:90});
  await query(`INSERT INTO app_settings VALUES('commitment','{"lookbackDays":90,"minAssignedVisits":1}')`);
  assert.deepEqual(await commitment.forActiveOffer(nurse,newOffer),
    {sufficient:true,lookbackDays:90,assignedVisits:1,countedCancellations:1});
  const appeals = new AppealsService(db);
  const admin = (await query("INSERT INTO users(phone_e164,role) VALUES('admin','ADMIN') RETURNING id")).rows[0].id;
  await assert.rejects(appeals.submit(nurse,'PATIENT',accepted.cancellationId,'غير مخول'),error => error.getStatus()===404);
  const appeal = await appeals.submit(patient,'PATIENT',accepted.cancellationId,'أطلب مراجعة التصنيف');
  assert.equal(appeal.status,'SUBMITTED');
  await assert.rejects(appeals.submit(patient,'PATIENT',accepted.cancellationId,'اعتراض مكرر'),error => error.getStatus()===409);
  await assert.rejects(appeals.review(admin,appeal.id,{status:'APPROVED',reason:'مراجعة'}),error => error.getStatus()===409);
  assert.equal((await commitment.forActiveOffer(nurse,newOffer)).countedCancellations,0);
  assert.equal((await commitment.ownHistory(patient)).items[0].commitmentImpact,false);
  await appeals.review(admin,appeal.id,{status:'UNDER_REVIEW',reason:'بدء المراجعة'});
  await appeals.review(admin,appeal.id,{status:'APPROVED',reason:'قُبل العذر'});
  assert.equal((await commitment.ownHistory(patient)).items[0].classification,'EXCUSED');
  assert.equal((await cancel({...payload,policyAcknowledged:true})).commitmentImpact,true);
  assert.equal((await query('SELECT previous_classification FROM cancellation_classification_events')).rows[0].previous_classification,
    'EN_ROUTE_COUNTED');
});
