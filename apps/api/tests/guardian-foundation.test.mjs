import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { runSafetyCheckin } from '../../worker/src/safety-checkins.ts';
import { CheckinsRepository } from '../dist/safety/checkins.repository.js';
import { CheckinsService } from '../dist/safety/checkins.service.js';
import { StaffCasesRepository } from '../dist/safety/staff-cases.repository.js';
import { StaffCasesService } from '../dist/safety/staff-cases.service.js';
import { SafetyRepository } from '../dist/safety/safety.repository.js';
import { SafetyService } from '../dist/safety/safety.service.js';

const migrations = new URL('../../../infra/db/migrations/', import.meta.url);
const read = (name) => readFile(new URL(name + '.sql', migrations), 'utf8');

test('Guardian binds sessions to the assigned nurse and stores immutable points and one SOS', async (t) => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec((await read('001_core')).replace(/CREATE EXTENSION[^;]*;/g, '')
    .replaceAll('geography(Point,4326)', 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, ''));
  await db.exec(`
    CREATE DOMAIN geography AS text;
    CREATE FUNCTION ST_MakePoint(float8,float8) RETURNS text LANGUAGE sql AS $$ SELECT $1::text || ',' || $2::text $$;
    CREATE FUNCTION ST_SetSRID(text, integer) RETURNS text LANGUAGE sql AS $$ SELECT $1 $$;
  `);
  await db.exec((await read('028_guardian_foundation')).replaceAll('geography(Point,4326)', 'geography'));
  await db.exec(await read('003_admin_reads_audit'));
  await db.exec(await read('004_auth_otp_refresh'));
  await db.exec(await read('005_password_accounts_push'));
  await db.exec(await read('029_guardian_checkins'));
  await db.exec(await read('030_guardian_staff_cases'));
  const makeUser = async (phone, role) => (await db.query(
    'INSERT INTO users(phone_e164,role) VALUES($1,$2) RETURNING id', [phone, role])).rows[0].id;
  const requester = await makeUser('patient', 'PATIENT');
  const nurse = await makeUser('nurse-a', 'NURSE');
  const outsider = await makeUser('nurse-b', 'NURSE');
  const assignment = (await db.query(`
    WITH n AS (INSERT INTO nurses(user_id) VALUES($2) RETURNING id),
      b AS (INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'مستفيد','GRANTED') RETURNING id),
      s AS (INSERT INTO services(code,title_ar,price_amount) VALUES('T','زيارة',100) RETURNING id),
      r AS (INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,price_amount,currency_code,commission_bps,status)
        SELECT $1,b.id,s.id,'','MANUAL_PIN','دمشق',100,'SYP',100,'EN_ROUTE' FROM b CROSS JOIN s RETURNING id)
    INSERT INTO request_assignments(request_id,nurse_id) SELECT r.id,n.id FROM r CROSS JOIN n RETURNING id
  `, [requester, nurse])).rows[0].id;

  const adapter = { query: db.query.bind(db), transaction: db.transaction.bind(db) };
  const repo = new SafetyRepository(adapter);
  const svc = new SafetyService(repo);
  const checkins = new CheckinsService(repo, new CheckinsRepository(adapter));
  const pool = { connect: async () => ({ query: adapter.query, release() {} }) };
  await assert.rejects(svc.start(outsider, assignment), { status: 404 });
  const session = await svc.start(nurse, assignment);
  assert.equal((await svc.start(nurse, assignment)).id, session.id);
  const point = { sequence: 1, latitude: 33.5, longitude: 36.3, accuracy: 12, capturedAt: new Date().toISOString() };
  assert.deepEqual(await svc.upload(nurse, session.id, { points: [point] }), { acceptedSequences: [1] });
  await svc.upload(nurse, session.id, { points: [point] });
  await assert.rejects(svc.upload(nurse, session.id, { points: [{ ...point, latitude: 33 }] }), { status: 409 });
  await assert.rejects(svc.upload(outsider, session.id, { points: [point] }), { status: 404 });

  const dto = { sessionId: session.id, clientEventId: randomUUID(), silent: true };
  const sos = await svc.sos(nurse, dto);
  assert.equal(sos.state, 'RECEIVED');
  assert.equal((await svc.sos(nurse, dto)).id, sos.id);
  await assert.rejects(svc.sos(nurse, { ...dto, silent: false }), { status: 409 });
  await assert.rejects(svc.event(outsider, sos.id), { status: 404 });
  assert.ok(session.policy_version_id);
  assert.equal(await runSafetyCheckin(pool), false);
  const forceDue = () => db.query("UPDATE safety_sessions SET next_checkin_at=now()-interval '1 second' WHERE id=$1", [session.id]);
  await forceDue();
  assert.equal(await runSafetyCheckin(pool), true);
  const first = (await checkins.pending(nurse, session.id)).checkin;
  assert.ok(first);
  assert.equal((await checkins.pending(outsider, session.id)).checkin, null);
  await assert.rejects(checkins.respond(outsider, session.id, {
    checkinId: first.id, clientResponseId: randomUUID(), response: 'OK',
  }), { status: 404 });
  const moreTime = { checkinId: first.id, clientResponseId: randomUUID(), response: 'MORE_TIME' };
  assert.equal((await checkins.respond(nurse, session.id, moreTime)).response, 'MORE_TIME');
  assert.equal((await checkins.respond(nurse, session.id, moreTime)).response, 'MORE_TIME');
  await assert.rejects(checkins.respond(nurse, session.id, { ...moreTime, clientResponseId: randomUUID() }), { status: 409 });
  await db.query("UPDATE safety_checkins SET remind_at=now()-interval '1 minute',deadline_at=now()+interval '1 minute' WHERE id=$1", [first.id]);
  assert.equal(await runSafetyCheckin(pool), true);
  assert.equal(await runSafetyCheckin(pool), false);
  await db.query("UPDATE safety_checkins SET remind_at=now()-interval '2 minutes',deadline_at=now()-interval '1 minute' WHERE id=$1", [first.id]);
  assert.equal(await runSafetyCheckin(pool), true);
  await forceDue();
  assert.equal(await runSafetyCheckin(pool), true);
  const second = (await checkins.pending(nurse, session.id)).checkin;
  await checkins.respond(nurse, session.id, { checkinId: second.id, clientResponseId: randomUUID(), response: 'SAFE_EXIT' });
  assert.deepEqual((await db.query('SELECT kind FROM safety_alerts ORDER BY kind')).rows,
    [{ kind: 'CHECKIN_MISSED' }, { kind: 'SAFE_EXIT_REQUESTED' }]);
  await forceDue();
  assert.equal(await runSafetyCheckin(pool), true);
  const third = (await checkins.pending(nurse, session.id)).checkin;
  await svc.checkout(nurse, session.id);
  assert.equal(await svc.status(nurse), null);
  assert.equal((await db.query('SELECT state FROM safety_checkins WHERE id=$1', [third.id])).rows[0].state, 'CANCELLED');
  assert.equal(await runSafetyCheckin(pool), false);
  await assert.rejects(svc.upload(nurse, session.id, {
    points: [{ ...point, sequence: 2, capturedAt: new Date(Date.now() + 10_000).toISOString() }],
  }), { status: 400 });
  assert.equal((await svc.event(nurse, sos.id)).state, 'RECEIVED');
  const ops = new StaffCasesService(new StaffCasesRepository(adapter));
  const plainAdmin = await makeUser('admin', 'ADMIN');
  const operator = await makeUser('operator', 'ADMIN');
  const otherOperator = await makeUser('operator-b', 'ADMIN');
  const supervisor = await makeUser('supervisor', 'ADMIN');
  await db.query(`INSERT INTO safety_staff_grants(user_id,permission,granted_by)
    VALUES($1,'SAFETY_OPERATOR',$4),($2,'SAFETY_OPERATOR',$4),($3,'SAFETY_SUPERVISOR',$4)`,
  [operator, otherOperator, supervisor, plainAdmin]);
  await assert.rejects(ops.list(plainAdmin), { status: 403 });
  const queue = await ops.list(operator);
  assert.deepEqual(queue.map(entry => entry.kind).sort(), ['CHECKIN_MISSED','SAFE_EXIT_REQUESTED','SOS']);
  const entry = queue.find(row => row.kind === 'SOS');
  await assert.rejects(ops.detail(operator, entry.id), { status: 404 });
  const acknowledgement = { clientActionId: randomUUID(), expectedVersion: 1 };
  const ack = await ops.act(operator, entry.id, 'ACKNOWLEDGED', acknowledgement);
  assert.equal(ack.state, 'ACKNOWLEDGED');
  assert.deepEqual(await ops.act(operator, entry.id, 'ACKNOWLEDGED', acknowledgement), ack);
  await assert.rejects(ops.act(otherOperator, entry.id, 'ACKNOWLEDGED', {
    clientActionId: randomUUID(), expectedVersion: 1,
  }), { status: 404 });
  assert.equal((await ops.detail(operator, entry.id)).silent, true);
  assert.equal((await svc.event(nurse, sos.id)).state, 'ACKNOWLEDGED');
  await assert.rejects(ops.act(operator, entry.id, 'RESOLVED', {
    clientActionId: randomUUID(), expectedVersion: 2, note: 'تم التحقق',
  }), { status: 403 });
  await ops.act(operator, entry.id, 'ESCALATED', {
    clientActionId: randomUUID(), expectedVersion: 2, note: 'تم رفع البلاغ للمشرف',
  });
  await assert.rejects(ops.act(supervisor, entry.id, 'RESOLVED', {
    clientActionId: randomUUID(), expectedVersion: 2, note: 'تم التحقق',
  }), { status: 409 });
  await ops.act(supervisor, entry.id, 'RESOLVED', {
    clientActionId: randomUUID(), expectedVersion: 3, note: 'تم التحقق من السلامة',
  });
  assert.equal((await svc.event(nurse, sos.id)).state, 'RESOLVED');
  assert.equal((await ops.detail(supervisor, entry.id)).actions.length, 3);
  assert.equal((await db.query("SELECT id FROM audit_log WHERE action='safety.case_resolved'")).rows.length, 1);
  assert.equal((await db.query("SELECT id FROM outbox_events WHERE event_type='safety.sos_received'")).rows.length, 1);
});
