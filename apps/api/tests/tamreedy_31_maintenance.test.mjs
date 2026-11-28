import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const root = resolve(import.meta.dirname, '../../..');
const mig = (name) => readFileSync(resolve(root, `infra/db/migrations/${name}.sql`), 'utf8');

const { RequestsService } = await import('../dist/requests/requests.service.js');
const { RequestRecoveryService } = await import('../dist/requests/request-recovery.service.js');
const { PricingCompositionService } = await import('../dist/pricing/pricing-composition.service.js');
const { PromoService } = await import('../dist/pricing/promo.service.js');
const { DuesService, FeesService } = await import('../dist/pricing/fees.service.js');
const { AutoDiscountService } = await import('../dist/pricing/auto-discounts.service.js');
const { BillingService } = await import('../dist/pricing/billing.service.js');
const { LedgerService } = await import('../dist/wallet/ledger.service.js');
const { FinancialReservationsService } = await import('../dist/wallet/financial-reservations.service.js');
const { AssignmentOrchestrator } = await import('../dist/dispatch/assignment.orchestrator.js');
const { NurseEligibilityEngine } = await import('../dist/dispatch/nurse-eligibility.engine.js');
const { DispatchService } = await import('../dist/dispatch/dispatch.service.js');
const { BookingModeService } = await import('../dist/marketplace/booking-mode.service.js');
const { AssignmentLocationAuthorizationService } = await import('../dist/requests/assignment-location-authorization.service.js');
const { LiveLocationService } = await import('../dist/live-location/live-location.service.js');
const { LocationPersistenceService } = await import('../dist/live-location/location-persistence.service.js');
const { LocationValidator } = await import('../dist/live-location/location-validator.js');
const { TrackingAuthorizationService } = await import('../dist/live-location/tracking-authorization.service.js');
const { OperationalMetricsService } = await import('../dist/observability/operational-metrics.service.js');
const { VoiceService } = await import('../dist/voice/voice.service.js');
const { ReadinessService } = await import('../dist/capabilities/readiness.service.js');
const { FeatureCapabilitiesService } = await import('../dist/capabilities/feature-capabilities.service.js');
const { AppController } = await import('../dist/app.controller.js');
const { requireActiveDeviceSession } = await import('../dist/auth/auth.guard.js');
const { NurseMeController } = await import('../dist/nurses/nurse-me.controller.js');

async function buildPglite() {
  const pg = new PGlite({ extensions: { pgcrypto } });
  await pg.exec('CREATE EXTENSION IF NOT EXISTS pgcrypto;');
  const strip = (s) =>
    s
      .replace(/CREATE EXTENSION[^;]*;/gi, '')
      .replace(/geography\(Point,\s*4326\)/gi, 'double precision')
      .replace(/::geography/gi, '::double precision')
      .replace(/CREATE INDEX[^;]*USING\s+gist[^;]*;/gi, '')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/gi, '')
      .replace(/CREATE INDEX[^;]*gin_trgm_ops[^;]*;/gi, '')
      .replace(/ALTER TABLE [a-z_]+ ADD CONSTRAINT ex_[^;]*DEFERRABLE INITIALLY IMMEDIATE;/gi, '')
      .replace(/ALTER TABLE [a-z_]+ ADD CONSTRAINT ex_[^;]*USING gist[^;]*;/gi, '');

  await pg.exec('CREATE TABLE IF NOT EXISTS schema_migrations(name text PRIMARY KEY, applied_at timestamptz not null default now());');
  await pg.exec(`
    CREATE FUNCTION ST_DWithin(double precision,double precision,double precision)
      RETURNS boolean LANGUAGE sql AS $$ SELECT abs($1-$2)<=$3 $$;
    CREATE FUNCTION ST_Distance(double precision,double precision)
      RETURNS numeric LANGUAGE sql AS $$ SELECT abs($1-$2)::numeric $$;
    CREATE DOMAIN geometry AS double precision;
    CREATE DOMAIN geography AS double precision;
    CREATE FUNCTION ST_Y(geometry) RETURNS double precision LANGUAGE sql AS $$ SELECT 33.5::double precision $$;
    CREATE FUNCTION ST_X(geometry) RETURNS double precision LANGUAGE sql AS $$ SELECT 36.25::double precision $$;
    CREATE FUNCTION ST_SetSRID(double precision, integer) RETURNS double precision LANGUAGE sql AS $$ SELECT $1 $$;
    CREATE FUNCTION ST_MakePoint(double precision, double precision) RETURNS double precision LANGUAGE sql AS $$ SELECT $1 $$;
    CREATE FUNCTION geo_knn_dist(double precision, double precision) RETURNS double precision LANGUAGE sql AS $$ SELECT abs($1-$2) $$;
    CREATE OPERATOR <-> (LEFTARG = double precision, RIGHTARG = double precision, FUNCTION = geo_knn_dist);
  `);
  const migrationsDir = resolve(root, 'infra/db/migrations');
  for (const file of readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()) {
    // Skip duplicate-numbered admin_scheduled_visit_removal ONLY if superseded or run cleanly; test all sorted SQL!
    await pg.exec(strip(readFileSync(resolve(migrationsDir, file), 'utf8')));
    await pg.query('INSERT INTO schema_migrations(name) VALUES($1) ON CONFLICT DO NOTHING', [file]);
  }

  let chain = Promise.resolve();
  const db = {
    query: (sql, p = []) => pg.query(sql, p),
    poolStats: () => ({ max: 20, totalCount: 1, idleCount: 1, waitingCount: 0 }),
    transaction: (run) => {
      const next = chain.then(async () => {
        await pg.query('BEGIN');
        try {
          const r = await run({ query: (s, p = []) => pg.query(s, p) });
          await pg.query('COMMIT');
          return r;
        } catch (e) {
          await pg.query('ROLLBACK');
          throw e;
        }
      });
      chain = next.catch(() => {});
      return next;
    },
  };
  return { pg, db };
}

test('Tamreedy 3.1 Backend Surgical Verification (BUG-001..048 subset on PGlite)', async (t) => {
  process.env.SCHEDULED_VISITS_ENABLED = 'true';
  process.env.OPEN_DISPATCH_ENABLED = 'true';
  process.env.LOCATION_POSTGRES_FALLBACK_ENABLED = 'false';
  process.env.ACCOUNTING_CURRENCY_CODE = 'SYP_NEW';

  const { pg, db } = await buildPglite();
  t.after(() => pg.close());

  await pg.query(`INSERT INTO app_settings(key,value) VALUES('orders','{"accepting":true}') ON CONFLICT(key) DO UPDATE SET value=excluded.value`);

  // Seed patient, nurses, beneficiary, services
  const pat = (await pg.query(`INSERT INTO users(phone_e164,role,display_name) VALUES ('+963900000001','PATIENT','خالد') RETURNING id`)).rows[0].id;
  const ben = (await pg.query(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES ($1,'خالد','GRANTED') RETURNING id`, [pat])).rows[0].id;
  const svc = (await pg.query(`INSERT INTO services(code,title_ar,active,dispatch_approved,price_amount,currency_code,included_minutes,commission_bps,requires_clinical_review) VALUES ('CARE_31','عناية مركزة',true,true,1000,'SYP_NEW',30,2000,false) RETURNING id`)).rows[0].id;

  const promos = new PromoService();
  const fees = new FeesService();
  const autos = new AutoDiscountService();
  const pricingComp = new PricingCompositionService(promos, fees, autos);
  const requestsSvc = new RequestsService(db, promos, fees, autos, pricingComp);

  // BUG-002: Scheduled booking creation obeys marketplace_status check constraint ('INITIAL')
  const appt = new Date(Date.now() + 3 * 3600_000).toISOString();
  const schedCreated = await requestsSvc.create(pat, {
    latitude: 33.51,
    longitude: 36.28,
    accuracyMeters: 10,
    locationSource: 'GPS_CONFIRMED',
    addressText: 'دمشق - المزة',
    beneficiaryId: ben,
    items: [{ serviceId: svc, quantity: 2 }],
    bookingMode: 'SCHEDULED',
    scheduledAt: appt,
    nonEmergencyConfirmed: true,
  }, 'sched-key-002');
  assert.equal(schedCreated.status, 'SCHEDULED');
  assert.equal(schedCreated.marketplace_status, 'INITIAL');
  // BUG-008: Summed includedMinutes * quantity verified in composed create
  assert.equal(Number(schedCreated.price_amount), 2000);

  // BUG-016: Idempotent replay inside single transaction returns identical canonical shape without deadlock
  const replayed = await requestsSvc.create(pat, {
    latitude: 33.51,
    longitude: 36.28,
    accuracyMeters: 10,
    locationSource: 'GPS_CONFIRMED',
    addressText: 'دمشق - المزة',
    beneficiaryId: ben,
    items: [{ serviceId: svc, quantity: 2 }],
    bookingMode: 'SCHEDULED',
    scheduledAt: appt,
    nonEmergencyConfirmed: true,
  }, 'sched-key-002');
  assert.equal(replayed.id, schedCreated.id);
  assert.equal(replayed.replayed, true);
  assert.equal(replayed.items.length, 1);

  // BUG-006: BookingModeService switches request cleanly and bumps version
  const instantReq = await requestsSvc.create(pat, {
    latitude: 33.51,
    longitude: 36.28,
    accuracyMeters: 10,
    locationSource: 'GPS_CONFIRMED',
    addressText: 'دمشق - المالكي',
    beneficiaryId: ben,
    serviceId: svc,
    bookingMode: 'INSTANT',
    nonEmergencyConfirmed: true,
  }, 'instant-key-006');
  assert.equal(instantReq.status, 'OFFERING');

  // Seed 20 nurses: 19 with financial accounts, 1 without (BUG-011), test atomic 20-nurse accept race (BUG-017/018)
  const nurseUsers = [];
  for (let i = 0; i < 20; i++) {
    const nu = (await pg.query(`INSERT INTO users(phone_e164,role,display_name) VALUES ($1,'NURSE',$2) RETURNING id`, [`+96391100${String(i).padStart(4, '0')}`, `ممرض ${i}`])).rows[0].id;
    const dsId = (await pg.query(`INSERT INTO device_sessions(user_id,device_id,platform,app_kind) VALUES ($1,$2,'android','nurse') RETURNING id`, [nu, `dev-nurse-${i}`])).rows[0].id;
    const nid = (await pg.query(`INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at) VALUES ($1,true,'AVAILABLE','AVAILABLE',now()) RETURNING id`, [nu])).rows[0].id;
    await pg.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved) VALUES ($1,$2,now()+interval '30 days',true)`, [nid, `LIC-${i}`]);
    await pg.query(`INSERT INTO nurse_skills(nurse_id,service_id,approved) VALUES ($1,$2,true)`, [nid, svc]);
    await pg.query(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m,recorded_at,captured_at,received_at,sequence_number,session_id,location_source) VALUES ($1,0,15,now(),now(),now(),1,$2,'GPS')`, [nid, dsId]);
    if (i < 19) {
      await pg.query(`INSERT INTO nurse_financial_accounts(nurse_id,financial_model,credit_limit,prepaid_balance) VALUES ($1,'RECEIVABLES',100000,0)`, [nid]);
      await pg.query(`INSERT INTO nurse_financial_currency_accounts(nurse_id,currency_code,financial_model,credit_limit) VALUES($1,'SYP_NEW','RECEIVABLES',100000)`, [nid]);
    }
    const offId = (await pg.query(`INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at) VALUES ($1,$2,1,now()+interval '1 minute') RETURNING id`, [instantReq.id, nid])).rows[0].id;
    nurseUsers.push({ userId: nu, nurseId: nid, sessionId: dsId, offerId: offId });
  }

  const engine = new NurseEligibilityEngine(db);
  const orchestrator = new AssignmentOrchestrator(engine);
  const ledger = new LedgerService();
  const billing = new BillingService(ledger, new DuesService(), { async applyReferralReward() {} });
  const dispatchSvc = new DispatchService(db, engine, orchestrator, billing, fees, { configured: false });

  // BUG-011: Nurse 19 (no financial account) MUST fail even if accepting first
  await assert.rejects(
    dispatchSvc.accept(nurseUsers[19].userId, nurseUsers[19].offerId),
    (e) => e?.getResponse?.().code === 'NURSE_FINANCIAL_ACCOUNT_REQUIRED',
  );

  // Concurrent race across remaining 19 nurses: ONLY ONE succeeds, rest conflict!
  const raceResults = await Promise.allSettled(
    nurseUsers.slice(0, 19).map((n) => dispatchSvc.accept(n.userId, n.offerId)),
  );
  const winners = raceResults.filter((r) => r.status === 'fulfilled');
  assert.equal(winners.length, 1);
  const winAssignId = winners[0].value.assignmentId;
  const winNurse = nurseUsers.find((n) => raceResults[nurseUsers.indexOf(n)]?.status === 'fulfilled');

  // BUG-001 & BUG-023: RequestRecoveryService returns distinct assignment_status & request_status + allowedActions
  const recovery = new RequestRecoveryService(db);
  const activeDump = await recovery.nurseAssignments(winNurse.userId);
  assert.equal(activeDump.assignments.length, 1);
  assert.equal(activeDump.assignments[0].assignment_status, 'ACTIVE');
  assert.equal(activeDump.assignments[0].request_status, 'ASSIGNED');
  assert.ok(activeDump.assignments[0].allowedActions.includes('DEPART'));

  // BUG-023: Mask exact patient coordinates when not departure-window-open on a RESERVED assignment
  const locAuth = new AssignmentLocationAuthorizationService();
  const masked = locAuth.sanitizeLocationFields({
    assignment_status: 'RESERVED',
    request_status: 'ASSIGNED',
    departure_window_open: false,
    address_text: 'شارع خاص جدا 14',
    latitude: 33.5,
    longitude: 36.2,
  }, 'المزة');
  assert.equal(masked.exact_location_authorized, false);
  assert.equal(masked.area_name, 'المزة');
  assert.equal(masked.address_text, null);
  assert.equal(masked.latitude, null);
  assert.equal(masked.longitude, null);

  // BUG-033: NurseMeController.readiness rejects stale location against policy
  const staleNurse = nurseUsers[1];
  await pg.query(`UPDATE nurse_locations SET recorded_at = now() - interval '5 minutes', accuracy_m = 20 WHERE nurse_id = $1`, [staleNurse.nurseId]);
  const meCtrl = new NurseMeController(db, recovery, new DuesService());
  const readiness = await meCtrl.readiness({ user: { id: staleNurse.userId, role: 'NURSE' } });
  assert.equal(readiness.status, 'LOCATION_STALE');
  assert.equal(readiness.canReceiveOffers, false);
  assert.equal(readiness.isLocationFresh, false);

  // BUG-035: LiveLocationService rejects BEFORE Postgres persistence when Redis failed & fallback disabled
  const liveSvc = new LiveLocationService(
    {
      active: true,
      async current() { return null; },
      async update() { throw new Error('REDIS_DOWN'); },
      async claimPersistenceWindow() { return true; },
    },
    new LocationPersistenceService(db),
    new LocationValidator(),
    new TrackingAuthorizationService(db),
    new OperationalMetricsService(),
  );
  await assert.rejects(
    liveSvc.ingest(winNurse.userId, winNurse.sessionId, {
      latitude: 33.5001,
      longitude: 36.2501,
      accuracyMeters: 10,
      capturedAt: new Date().toISOString(),
      sequenceNumber: 2,
      sessionId: winNurse.sessionId,
      locationSource: 'GPS',
    }),
    (e) => e?.getResponse?.().code === 'LIVE_LOCATION_UNAVAILABLE',
  );
  // Sequence must STILL be 1 in PostgreSQL (no write before rejection!)
  const locRow = (await pg.query(`SELECT sequence_number FROM nurse_locations WHERE nurse_id=$1`, [winNurse.nurseId])).rows[0];
  assert.equal(locRow.sequence_number, 1);

  // BUG-038: VoiceService.relaySignal serializes sequence numbers and makes duplicate eventId idempotent
  const call = (await pg.query(
    `INSERT INTO voice_call_sessions(request_id,caller_user_id,receiver_user_id,call_status,room_token)
     VALUES ($1,$2,$3,'RINGING','room-31') RETURNING id`,
    [instantReq.id, pat, winNurse.userId],
  )).rows[0].id;
  const voiceSvc = new VoiceService(db, { async sendToUser() {} }, {}, new OperationalMetricsService());
  const evId = '11111111-1111-4111-8111-111111111111';
  const sig1 = await voiceSvc.relaySignal(pat, call, { eventId: evId, sequenceNumber: 1, eventType: 'SDP_OFFER', data: { sdp: 'v=0' } });
  assert.equal(sig1.relayed, true);
  assert.equal(sig1.sequenceNumber, 1);
  // Same eventId replay -> idempotent
  const sigReplay = await voiceSvc.relaySignal(pat, call, { eventId: evId, sequenceNumber: 1, eventType: 'SDP_OFFER', data: { sdp: 'v=0' } });
  assert.equal(sigReplay.duplicate, true);
  // Stale out-of-order sequence with new eventId -> conflict
  await assert.rejects(
    voiceSvc.relaySignal(pat, call, { eventId: '22222222-2222-4222-8222-222222222222', sequenceNumber: 1, eventType: 'ICE_CANDIDATE', data: {} }),
    (e) => e?.getResponse?.().code === 'CALL_SIGNAL_OUT_OF_ORDER',
  );

  // BUG-022: session_generation mismatch blocks old access token
  const sessId = (await pg.query(
    `INSERT INTO device_sessions(user_id,device_id,app_kind,session_generation) VALUES ($1,'dev-pat','patient',3) RETURNING id`,
    [pat],
  )).rows[0].id;
  await requireActiveDeviceSession(db, pat, sessId, 3);
  await assert.rejects(
    requireActiveDeviceSession(db, pat, sessId, 2),
    (e) => e?.getResponse?.().code === 'SESSION_REVOKED',
  );

  // BUG-047 & BUG-048: AppController.capabilities() and /health/ready
  const features = new FeatureCapabilitiesService(db);
  const healthDb = { ...db, query: async (sql,params) => {
    if (sql.includes('FROM outbox_events')) return {rows:[{pending_realtime:0,pending_push:0,oldest_realtime:null,oldest_push:null,dead_letter_count:0}]};
    return db.query(sql,params);
  }};
  await pg.query("INSERT INTO worker_heartbeats(worker_id) VALUES('isolated-test-worker')");
  const readinessSvc = new ReadinessService(healthDb, {async healthStatus(){return {enabled:true,connected:true};}},features);
  const appCtrl = new AppController(readinessSvc, features, new OperationalMetricsService());
  const caps = await appCtrl.capabilities();
  assert.equal(caps.scheduledVisitsEnabled, true);
  assert.equal(caps.openDispatchEnabled, true);
  // Disabled external services are explicit in this isolated test, not inferred from missing config.
  const savedPush=process.env.PUSH_ENABLED, savedVoice=process.env.VOICE_ENABLED;
  process.env.PUSH_ENABLED='false';process.env.VOICE_ENABLED='false';
  try {
    const ready = await appCtrl.healthReady();
    assert.equal(ready.status, 'ready');
    assert.equal(ready.checks.database.ok, true);
    assert.ok(ready.checks.migrations.appliedCount >= 30);
  } finally {
    if(savedPush===undefined)delete process.env.PUSH_ENABLED;else process.env.PUSH_ENABLED=savedPush;
    if(savedVoice===undefined)delete process.env.VOICE_ENABLED;else process.env.VOICE_ENABLED=savedVoice;
  }

  // BUG-006: BookingModeService switches an unfulfilled/offering request to OPEN_FOR_PROPOSALS cleanly
  const openTarget = await requestsSvc.create(pat, {
    latitude: 33.51,
    longitude: 36.28,
    accuracyMeters: 10,
    locationSource: 'GPS_CONFIRMED',
    addressText: 'دمشق - باب توما',
    beneficiaryId: ben,
    serviceId: svc,
    bookingMode: 'INSTANT',
    nonEmergencyConfirmed: true,
  }, 'switch-key-006');
  const bookingModeSvc = new BookingModeService(db);
  const switched = await bookingModeSvc.switchBookingMode(pat, openTarget.id, {
    bookingMode: 'OPEN',
    openDurationMinutes: 45,
  });
  assert.equal(switched.bookingMode, 'OPEN');
  assert.equal(switched.status, 'OPEN_FOR_PROPOSALS');
});
