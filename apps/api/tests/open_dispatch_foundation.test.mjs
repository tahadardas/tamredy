import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const migration = (name) => readFileSync(
  new URL(`../../../infra/db/migrations/${name}.sql`, import.meta.url),
  'utf8',
);
const id = (last) => `00000000-0000-4000-8000-${String(last).padStart(12, '0')}`;

test('migration 021 preserves legacy requests and constrains dispatch and cancellation evidence', async (t) => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(migration('001_core')
    .replace(/^CREATE EXTENSION.*;$/gm, '')
    .replaceAll('geography(Point,4326)', 'text')
    .replace(/^CREATE INDEX.*USING GIST.*;$/gm, ''));
  const [patient, nurseUser, nurse, beneficiary, service, assigned, historic, wrong, assignment] =
    Array.from({ length: 9 }, (_, index) => id(index + 1));
  await db.exec(`
    INSERT INTO users(id,phone_e164,role) VALUES ('${patient}','+963900000001','PATIENT'),
      ('${nurseUser}','+963900000002','NURSE');
    INSERT INTO nurses(id,user_id) VALUES ('${nurse}','${nurseUser}');
    INSERT INTO beneficiaries(id,owner_user_id,display_name,consent_status)
      VALUES ('${beneficiary}','${patient}','مريض تجريبي','GRANTED');
    INSERT INTO services(id,code,title_ar,price_amount) VALUES ('${service}','TEST','تمريض منزلي',5000);
    INSERT INTO care_requests(id,requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps)
    SELECT request_id,'${patient}','${beneficiary}','${service}','test','MANUAL_PIN','دمشق',status,5000,'SYP',2000
    FROM (VALUES ('${assigned}'::uuid,'EN_ROUTE'),('${historic}'::uuid,'CANCELLED'),('${wrong}'::uuid,'OFFERING')) r(request_id,status);
    INSERT INTO request_assignments(id,request_id,nurse_id,accepted_at)
      VALUES ('${assignment}','${assigned}','${nurse}','2026-01-01T12:00:00Z');
  `);
  await db.exec(migration('021_open_dispatch_and_cancellation_foundation'));
  assert.deepEqual((await db.query(
    'SELECT status,search_started_at,search_expires_at,closed_at FROM care_requests WHERE id=$1', [historic],
  )).rows, [{ status: 'CANCELLED', search_started_at: null, search_expires_at: null, closed_at: null }]);
  assert.equal((await db.query('SELECT 1 FROM request_cancellations')).rows.length, 0);

  await assert.rejects(
    db.query('UPDATE care_requests SET search_started_at=now(),search_radius_meters=3000 WHERE id=$1', [wrong]),
    { constraint: 'chk_care_request_search_window' },
  );
  await db.query(`UPDATE care_requests SET search_started_at=now(),
    search_expires_at=now()+interval '60 seconds',search_radius_meters=10000 WHERE id=$1`, [wrong]);
  await assert.rejects(db.query(`UPDATE request_assignments SET departed_at='2026-01-01T12:01:00Z',
    eta_reference_at='2026-01-01T12:01:00Z',eta_duration_seconds=600,eta_provider='test',eta_status='AVAILABLE',
    eta_version=1,expected_arrival_at='2026-01-01T12:10:00Z' WHERE id=$1`, [assignment]),
  { constraint: 'chk_assignment_departure_eta' });
  await db.query(`UPDATE request_assignments SET departed_at='2026-01-01T12:01:00Z',
    eta_reference_at='2026-01-01T12:01:00Z',eta_duration_seconds=600,eta_provider='test',eta_status='AVAILABLE',
    eta_version=1,expected_arrival_at='2026-01-01T12:11:00Z' WHERE id=$1`, [assignment]);

  const insert = (request, cancelledAt) => db.query(`INSERT INTO request_cancellations
    (request_id,cancelled_by_user_id,assignment_id,reason_code,status_at_cancellation,cancelled_at,
     nurse_departed_at,eta_reference_at,expected_arrival_at,classification,commitment_impact,policy_version,idempotency_key,payload_digest)
    VALUES ($1,$2,$3,'OTHER','EN_ROUTE',$4,'2026-01-01T12:01:00Z','2026-01-01T12:01:00Z',
      '2026-01-01T12:11:00Z','EN_ROUTE_COUNTED',true,1,'test',repeat('a',64)) RETURNING id`,
  [request, patient, assignment, cancelledAt]);
  await assert.rejects(insert(wrong, '2026-01-01T12:40:59Z'), { constraint: 'fk_cancellation_request_assignment' });
  for (const time of ['12:41:00', '12:41:01']) {
    await assert.rejects(insert(assigned, `2026-01-01T${time}Z`),
      { constraint: 'chk_cancellation_counted_evidence' });
  }
  const cancellation = (await insert(assigned, '2026-01-01T12:40:59Z')).rows[0].id;
  await assert.rejects(insert(assigned, '2026-01-01T12:40:59Z'), { code: '23505' });
  const appeal = await db.query(`INSERT INTO cancellation_appeals(cancellation_id,submitted_by_user_id,submitter_role,description)
    VALUES ($1,$2,'PATIENT','أطلب مراجعة التصنيف') RETURNING status`, [cancellation, patient]);
  assert.equal(appeal.rows[0].status, 'SUBMITTED');
});
