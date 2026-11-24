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
import { TrustedContactsRepository } from '../dist/trusted-contacts/trusted-contacts.repository.js';
import { TrustedContactsService } from '../dist/trusted-contacts/trusted-contacts.service.js';
import { SafeAbortRepository } from '../dist/safety/safe-abort.repository.js';
import { SafeAbortService } from '../dist/safety/safe-abort.service.js';
import { DirectoryRepository } from '../dist/safety/directory.repository.js';
import { DirectoryService } from '../dist/safety/directory.service.js';
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
  await db.exec(await read('031_guardian_sos_trigger_time'));
  await db.exec(await read('032_trusted_contacts'));
  await db.exec(await read('033_safety_abort'));
  await db.exec(await read('034_emergency_directory'));
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

  const triggeredAt = new Date(Date.now() - 90000).toISOString();
  const dto = { sessionId: session.id, clientEventId: randomUUID(), silent: true, triggeredAt, expectedReporterId: nurse };
  assert.throws(() => svc.sos(outsider, dto), { status: 403 });
  const sos = await svc.sos(nurse, dto);
  assert.equal(sos.state, 'RECEIVED');
  assert.equal(new Date(sos.triggered_at).toISOString(), triggeredAt);
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
  const aborts = new SafeAbortService(new SafeAbortRepository(adapter), repo);
  await assert.rejects(aborts.abort(outsider, assignment, {}), { status: 404 });
  await db.query('INSERT INTO visits(assignment_id,arrived_at) VALUES($1,now())', [assignment]);
  const result = await aborts.abort(nurse, assignment, {});
  assert.deepEqual(result, { status: 'ESCALATED', eventId: sos.id });
  assert.deepEqual(await aborts.abort(nurse, assignment, {}), result);
  const terminated = (await db.query(`SELECT r.status,a.reason,n.work_status,v.outcome
    FROM request_assignments a JOIN care_requests r ON r.id=a.request_id
    JOIN nurses n ON n.id=a.nurse_id JOIN visits v ON v.assignment_id=a.id WHERE a.id=$1`, [assignment])).rows[0];
  assert.deepEqual(terminated, { status: 'ESCALATED', reason: 'SAFETY_ABORT', work_status: 'PAUSED', outcome: 'ESCALATED' });
  assert.equal((await svc.event(nurse, sos.id)).state, 'RECEIVED');
  const patientNotice = (await db.query(`SELECT payload FROM outbox_events WHERE event_type='visit.interrupted'`)).rows[0].payload;
  assert.equal(patientNotice.recipientUserId, requester);
  assert.deepEqual(Object.keys(patientNotice).sort(), ['recipientUserId', 'requestId']);
  const ops = new StaffCasesService(new StaffCasesRepository(adapter));
  const plainAdmin = await makeUser('admin', 'ADMIN');
  const operator = await makeUser('operator', 'ADMIN');
  const otherOperator = await makeUser('operator-b', 'ADMIN');
  const supervisor = await makeUser('supervisor', 'ADMIN');
  await db.query(`INSERT INTO safety_staff_grants(user_id,permission,granted_by)
    VALUES($1,'SAFETY_OPERATOR',$4),($2,'SAFETY_OPERATOR',$4),($3,'SAFETY_SUPERVISOR',$4)`,
  [operator, otherOperator, supervisor, plainAdmin]);
  const directory = new DirectoryService(new DirectoryRepository(adapter), new StaffCasesRepository(adapter));
  const draft = {
    name: 'جهة اختبارية', category: 'APPROVED_SUPPORT', governorate: 'دمشق',
    dialNumber: '000000', officialSource: 'مرجع اختباري', publishVerified: false,
  };
  await assert.rejects(directory.save(plainAdmin, draft), { status: 403 });
  const directoryEntry = await directory.save(supervisor, draft);
  assert.deepEqual(await directory.visible(), []);
  await directory.save(supervisor, { ...draft, publishVerified: true }, directoryEntry.id);
  assert.equal((await directory.visible())[0].id, directoryEntry.id);
  await db.query("UPDATE emergency_directory SET verified_at=now()-interval '91 days',valid_until=now()-interval '1 day' WHERE id=$1", [directoryEntry.id]);
  assert.deepEqual(await directory.visible(), []);
  await directory.save(supervisor, { ...draft, publishVerified: true }, directoryEntry.id);
  await directory.deactivate(supervisor, directoryEntry.id);
  assert.deepEqual(await directory.visible(), []);
  const contacts = new TrustedContactsService(new TrustedContactsRepository(adapter));
  const nominated = {
    name: 'أحمد', phone: '+963987654321', relationship: 'أخ',
    priority: 1, communication: 'CALL', requestLocation: true,
  };
  const contact = await contacts.save(nurse, nominated);
  assert.equal(contact.consent_state, 'PENDING');
  assert.equal(contact.location_allowed, false);
  assert.deepEqual(await contacts.list(outsider), []);
  await assert.rejects(contacts.save(outsider, nominated, contact.id), { status: 404 });
  await assert.rejects(contacts.save(nurse, { ...nominated, priority: 2 }), { status: 409 });
  const confirmation = {
    decision: 'ACCEPTED', allowsLocation: true,
    verificationReference: 'verification-1', verifiedPhone: nominated.phone,
  };
  await assert.rejects(contacts.consent(plainAdmin, contact.id, confirmation), { status: 403 });
  await assert.rejects(contacts.consent(supervisor, contact.id, {
    ...confirmation, verifiedPhone: '+963987654322',
  }), { status: 409 });
  assert.equal((await contacts.consent(supervisor, contact.id, confirmation)).location_allowed, true);
  const changed = await contacts.save(nurse, { ...nominated, phone: '+963987654322' }, contact.id);
  assert.equal(changed.consent_state, 'PENDING');
  assert.equal(changed.location_allowed, false);
  await contacts.remove(nurse, contact.id);
  assert.deepEqual(await contacts.list(nurse), []);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM trusted_contact_consents WHERE contact_id=$1', [contact.id])).rows[0].n, 3);
  await assert.rejects(ops.list(plainAdmin), { status: 403 });
  await assert.rejects(ops.dashboard(plainAdmin), { status: 403 });
  const summary = await ops.dashboard(operator);
  assert.equal(summary.canResolve, false);
  assert.equal(summary.coverage, 'NOT_CONFIGURED');
  assert.equal(summary.counts.open_sos, 1);
  assert.equal(summary.counts.missed_checkins, 1);
  const queue = await ops.list(operator);
  assert.deepEqual(queue.map(entry => entry.kind).sort(), ['CHECKIN_MISSED','SAFE_EXIT_REQUESTED','SOS']);
  const entry = queue.find(row => row.kind === 'SOS');
  await assert.rejects(ops.detail(operator, entry.id), { status: 404 });
  const acknowledgement = { clientActionId: randomUUID(), expectedVersion: 1 };
  const ack = await ops.act(operator, entry.id, 'ACKNOWLEDGED', acknowledgement);
  assert.equal(ack.state, 'ACKNOWLEDGED');
  assert.equal((await ops.dashboard(otherOperator)).counts.open_sos, 0);
  assert.equal((await ops.dashboard(supervisor)).counts.open_sos, 1);
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
