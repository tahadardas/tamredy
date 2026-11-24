import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { closeNightIneligibleOffers } from '../../worker/src/night-safety.ts';
import { VisitRiskService } from '../dist/safety/visit-risk.js';
import { NightPolicyService } from '../dist/safety/night-policy.js';
import { routeSafetyCase } from '../../worker/src/safety-routing.ts';
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
import { ShiftsRepository } from '../dist/safety/shifts.repository.js';
import { ShiftsService } from '../dist/safety/shifts.service.js';
import { HandoversService } from '../dist/safety/handovers.js';
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
  await db.exec(await read('011_regions'));
  await db.exec(await read('035_safety_shifts'));
  await db.exec(await read('036_guardian_case_routing'));
  await db.exec(await read('037_guardian_handovers'));
  await db.exec(await read('038_guardian_night_policy'));
  await db.exec(await read('039_guardian_visit_risk'));
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
  const grants = new StaffCasesRepository(adapter);
  const shiftRepository = new ShiftsRepository(adapter);
  const shiftService = new ShiftsService(shiftRepository, grants);
  const ops = new StaffCasesService(grants, shiftRepository);
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
  assert.equal(summary.coverage, 'UNCOVERED');
  assert.equal(summary.counts.open_sos, 1);
  assert.equal(summary.counts.missed_checkins, 1);
  const now = Date.now();
  const shiftSpec = {
    shiftKind: 'NIGHT', primaryUserId: operator, backupUserId: supervisor,
    startsAt: new Date(now-3600000).toISOString(), endsAt: new Date(now+3600000).toISOString(),
  };
  await assert.rejects(shiftService.save(operator, shiftSpec), { status: 403 });
  const shift = await shiftService.save(supervisor, shiftSpec);
  assert.equal((await ops.dashboard(operator)).coverage, 'UNCOVERED');
  await assert.rejects(shiftService.save(supervisor, shiftSpec), { status: 409 });
  await assert.rejects(shiftService.presence(otherOperator, shift.id, 'checkin'), { status: 404 });
  await assert.rejects(shiftService.presence(operator, shift.id, 'heartbeat'), { status: 409 });
  await shiftService.presence(operator, shift.id, 'checkin');
  assert.equal((await ops.dashboard(supervisor)).shifts[0].primary_present, true);
  await db.query("UPDATE safety_staff_shift_presence SET checked_in_at=now()-interval '5 minutes',heartbeat_at=now()-interval '2 minutes' WHERE shift_id=$1", [shift.id]);
  assert.equal((await ops.dashboard(supervisor)).coverage, 'UNCOVERED');
  await shiftService.presence(supervisor, shift.id, 'checkin');
  assert.equal((await ops.dashboard(operator)).shifts[0].backup_present, true);
  await shiftService.presence(supervisor, shift.id, 'checkout');
  assert.equal((await ops.dashboard(supervisor)).coverage, 'UNCOVERED');
  const tomorrow = new Date(now+172800000).toISOString().slice(0,10);
  const following = new Date(now+259200000).toISOString().slice(0,10);
  const acrossMidnight = await shiftService.save(supervisor, {
    ...shiftSpec, startsAt: tomorrow+'T22:00:00+03:00', endsAt: following+'T06:00:00+03:00',
  });
  assert.equal(new Date(acrossMidnight.ends_at)-new Date(acrossMidnight.starts_at), 8*3600000);
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
  // Verify time-based routing separately from human acknowledgement.
  await db.query("UPDATE safety_cases SET next_route_at=now()+interval '1 hour'");
  const another = await svc.sos(nurse, { clientEventId: randomUUID(), silent: true });
  const routed = (await db.query('SELECT id FROM safety_cases WHERE emergency_event_id=$1', [another.id])).rows[0];
  await shiftService.presence(operator, shift.id, 'checkin');
  await shiftService.presence(supervisor, shift.id, 'checkin');
  assert.equal(await routeSafetyCase(pool), true);
  const routeStatus = async () => (await db.query(
    'SELECT assigned_user_id,routing_stage,state FROM safety_cases WHERE id=$1', [routed.id])).rows[0];
  assert.deepEqual(await routeStatus(), {assigned_user_id: operator, routing_stage: 'PRIMARY', state: 'RECEIVED'});
  assert.equal(await routeSafetyCase(pool), false);
  const expire = () => db.query("UPDATE safety_cases SET next_route_at=now()-interval '1 second' WHERE id=$1", [routed.id]);
  await expire();
  assert.equal(await routeSafetyCase(pool), true);
  assert.deepEqual(await routeStatus(), {assigned_user_id: supervisor, routing_stage: 'BACKUP', state: 'RECEIVED'});
  await expire();
  assert.equal(await routeSafetyCase(pool), true);
  assert.deepEqual(await routeStatus(), {assigned_user_id: null, routing_stage: 'UNCOVERED', state: 'RECEIVED'});
  assert.equal((await svc.event(nurse, another.id)).state, 'RECEIVED');
  assert.equal((await db.query('SELECT id FROM safety_case_routes WHERE case_id=$1', [routed.id])).rows.length, 3);

  const handovers = new HandoversService(adapter, grants);
  const pendingVersion = (await db.query('SELECT version FROM safety_cases WHERE id=$1', [routed.id])).rows[0].version;
  const claimed = await ops.act(operator, routed.id, 'ACKNOWLEDGED', {
    clientActionId: randomUUID(), expectedVersion: pendingVersion,
  });
  const options = await handovers.candidates(operator, routed.id);
  assert.deepEqual(options.map(slot => slot.user_id), [supervisor]);
  const transfer = {toUserId: supervisor, toShiftId: shift.id, expectedVersion: claimed.version};
  const offer = await handovers.request(operator, routed.id, transfer);
  assert.deepEqual(await handovers.request(operator, routed.id, transfer), offer);
  assert.equal((await routeStatus()).assigned_user_id, operator);
  assert.equal((await handovers.inbox(supervisor))[0].id, offer.id);
  assert.deepEqual(await handovers.inbox(otherOperator), []);
  await assert.rejects(handovers.accept(otherOperator, offer.id), {status: 404});
  await shiftService.presence(supervisor, shift.id, 'checkout');
  await assert.rejects(handovers.accept(supervisor, offer.id), {status: 409});
  await shiftService.presence(supervisor, shift.id, 'checkin');
  assert.deepEqual(await handovers.accept(supervisor, offer.id), {caseId: routed.id});
  assert.deepEqual(await handovers.accept(supervisor, offer.id), {caseId: routed.id});
  assert.equal((await routeStatus()).assigned_user_id, supervisor);
  assert.equal((await svc.event(nurse, another.id)).state, 'ACKNOWLEDGED');
  await assert.rejects(ops.detail(operator, routed.id), {status: 404});

  const policy = new NightPolicyService(adapter, grants);
  const nurseId = (await db.query('SELECT id FROM nurses WHERE user_id=$1', [nurse])).rows[0].id;
  const visitInfo = (await db.query(`SELECT r.id,r.service_id,r.beneficiary_id
    FROM care_requests r JOIN request_assignments a ON a.request_id=r.id WHERE a.id=$1`, [assignment])).rows[0];
  const reason = async (when) => (await db.query('SELECT guardian_night_denial($1,$2,$3) AS reason',
    [nurseId,visitInfo.service_id,when])).rows[0].reason;
  const policyWindow = {startsAt: '22:00', endsAt: '06:00', mode: 'REQUIRE_OPT_IN_AND_COVERAGE'};
  await assert.rejects(policy.publish(operator,policyWindow), {status: 403});
  await policy.publish(supervisor,policyWindow);
  assert.equal(await reason('2024-11-25T00:01:00+03:00'), 'NIGHT_POLICY_OPT_IN_REQUIRED');
  assert.equal(await reason('2024-11-25T06:00:00+03:00'), null);
  await policy.preferenceUpdate(nurse,{optedIn: true});
  assert.equal(await reason('2024-11-25T00:01:00+03:00'), 'NIGHT_POLICY_COVERAGE_REQUIRED');
  const current = (await db.query("SELECT (now() AT TIME ZONE 'Asia/Damascus')::time::text AS time")).rows[0].time;
  const hour = Number(current.slice(0,2));
  const endsAt = String((hour + 1) % 24).padStart(2, '0')+':00';
  const startsAt = String((hour + 23) % 24).padStart(2, '0')+':00';
  await policy.publish(supervisor, {mode: 'REQUIRE_COVERAGE', startsAt, endsAt});
  assert.equal(await reason(new Date().toISOString()), null);
  await policy.publish(supervisor, {mode: 'RESTRICT', startsAt, endsAt});
  const offering = (await db.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,
    location_source,address_text,price_amount,currency_code,commission_bps)
    VALUES($1,$2,$3,'','MANUAL_PIN','دمشق',100,'SYP',100) RETURNING id`,
  [requester,visitInfo.beneficiary_id,visitInfo.service_id])).rows[0];
  await db.query("INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at) VALUES($1,$2,1,now()+interval '1 minute')",
    [offering.id,nurseId]);
  assert.equal(await closeNightIneligibleOffers({query: adapter.query}), true);
  assert.equal((await db.query('SELECT status FROM request_offers WHERE request_id=$1', [offering.id])).rows[0].status, 'CLOSED');
  assert.equal((await db.query('SELECT status FROM care_requests WHERE id=$1', [visitInfo.id])).rows[0].status, 'ESCALATED');

  const risks = new VisitRiskService(adapter, grants);
  const effectiveUntil = new Date(Date.now()+3600000).toISOString();
  const assessment = {decision: 'HOLD', basis: 'DOCUMENTED_THREAT', reference: 'case-reference', effectiveUntil};
  await assert.rejects(risks.assess(operator,offering.id,assessment), {status: 403});
  await risks.assess(supervisor,offering.id,assessment);
  const eligibility = async (nurse, request) => (await db.query(
    'SELECT guardian_dispatch_denial($1,$2,statement_timestamp()) AS reason',[nurse,request])).rows[0].reason;
  assert.equal(await eligibility(nurseId,offering.id), 'VISIT_SAFETY_REVIEW_REQUIRED');
  await risks.assess(supervisor,offering.id,{...assessment, decision: 'REQUIRE_COMPANION', basis: 'SOLO_WORK'});
  assert.equal(await eligibility(nurseId,offering.id), 'VISIT_COMPANION_REQUIRED');
  const companion = (await db.query(`INSERT INTO nurses(user_id,verified,work_status,availability_intent,last_heartbeat_at)
    VALUES($1,true,'AVAILABLE','AVAILABLE',now()) RETURNING id`,[outsider])).rows[0].id;
  await db.query("UPDATE nurses SET verified=true WHERE id=$1", [nurseId]);
  for (const provider of [nurseId,companion]) {
    await db.query("INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved) VALUES($1,'test',now()+interval '1 day',true)",[provider]);
  }
  await risks.nominate(supervisor,offering.id,{nurseId,companionId: companion});
  await assert.rejects(risks.confirm(nurse,offering.id,nurseId), {status: 404});
  assert.equal((await risks.pending(outsider))[0].request_id,offering.id);
  await risks.confirm(outsider,offering.id,nurseId);
  await policy.publish(supervisor,{mode: 'ALLOW',startsAt,endsAt});
  assert.equal(await eligibility(nurseId,offering.id), null);
  const newAssignment = (await db.query(
    'INSERT INTO request_assignments(request_id,nurse_id) VALUES($1,$2) RETURNING id',[offering.id,nurseId])).rows[0].id;
  await db.query('INSERT INTO safety_companion_reservations(assignment_id,companion_id) VALUES($1,$2)',[newAssignment,companion]);
  assert.equal(await eligibility(companion,offering.id), 'VISIT_COMPANION_BUSY');
  await db.query("UPDATE request_assignments SET status='RELEASED' WHERE id=$1",[newAssignment]);
  assert.notEqual(await eligibility(companion,offering.id), 'VISIT_COMPANION_BUSY');

});
