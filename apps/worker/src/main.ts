import { closeLocationReader } from './live-location.js';
import { randomUUID } from 'node:crypto';
import { missingMigrations } from '../../../packages/backend-policy/schema.mjs';
import { featureCapabilities, runtimeConfigFingerprint } from '../../../packages/backend-policy/capabilities.mjs';
import { closeNightIneligibleOffers, nightPolicyEnabled } from './night-safety.js';
import pg from 'pg';
import { readFileSync } from 'node:fs';
import Redis from 'ioredis';
import 'dotenv/config';
import { FcmClient, loadServiceAccount, pushDeliverBatch, retryPendingPushes } from './push.js';
import { notifyDelayedDepartures } from './departure-reminders.js';
import { deliverOutbox, publishRealtimeEvents } from './outbox.js';
import { runSafetyRetention } from './safety-retention.js';
import { routeSafetyCase } from './safety-routing.js';
import { runSafetyCheckin } from './safety-checkins.js';
import { releaseScheduledVisit } from './scheduling.js';
import { doDispatch } from './dispatch.js';
import { processBroadcast, runWinback } from './marketing.js';
import { runSmartRecoveryJob } from './smart-recovery.js';
import { expireVoiceCalls } from './voice-lifecycle.js';

const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) throw new Error('DATABASE_URL required');

const pool = new pg.Pool({
  connectionString: dbUrl,
  max: Number(process.env.DATABASE_POOL_MAX ?? 10),
  statement_timeout: Number(process.env.DATABASE_STATEMENT_TIMEOUT_MS ?? 10_000),
  connectionTimeoutMillis: Number(process.env.DATABASE_CONNECTION_TIMEOUT_MS ?? 3_000),
  idleTimeoutMillis: Number(process.env.DATABASE_IDLE_TIMEOUT_MS ?? 30_000),
});
const features = featureCapabilities();
const redis = features.realtimeEnabled && process.env.REDIS_URL ? new Redis(process.env.REDIS_URL, { enableOfflineQueue: false, maxRetriesPerRequest: 1, commandTimeout: 2000, retryStrategy: (times) => Math.min(times * 500, 5000) }) : undefined;

function logFailure(job: string,error: unknown) {
  const candidate = typeof error==='object' && error!==null && 'code' in error ? error.code : null;
  const code = typeof candidate==='string' && /^[A-Z0-9_]{1,40}$/.test(candidate)
    ? candidate : 'WORKER_OPERATION_FAILED';
  console.error(JSON.stringify({service:'tamreedy-worker',event:'job.failed',job,code}));
}
pool.on('error',error=>logFailure('database',error));
redis?.on('error',error=>logFailure('redis',error));

let sa;
try {
  const raw = features.pushEnabled && process.env.FCM_SERVICE_ACCOUNT_FILE
    ? readFileSync(process.env.FCM_SERVICE_ACCOUNT_FILE, 'utf8')
    : features.pushEnabled ? process.env.FCM_SERVICE_ACCOUNT_JSON : undefined;
  sa = features.pushEnabled ? loadServiceAccount(raw) : undefined;
} catch (e) {
  logFailure('push.configuration',e);
}

type LoopName = 'push' | 'realtime' | 'dispatch';
const loopState: Record<LoopName, { success: Date | null; error: Date | null }> = {
  push: { success: null, error: null }, realtime: { success: null, error: null },
  dispatch: { success: null, error: null },
};
function observeLoop(name: LoopName, ok: boolean) {
  loopState[name][ok ? 'success' : 'error'] = new Date();
}
function operational(name: LoopName): boolean | null {
  const { success, error } = loopState[name];
  if (!success && !error) return null;
  return !!success && (!error || success.getTime() >= error.getTime());
}
const fcm = sa ? new FcmClient(sa, undefined, ok => observeLoop('push', ok)) : undefined;

let lastRealtimeProbe = 0;
async function flushRealtimeOutbox(): Promise<boolean> {
  if (!redis) throw Object.assign(new Error('Redis not configured'), {code:'REDIS_CONFIGURATION_REQUIRED'});
  const worked = await deliverOutbox(pool, 'realtime', events => publishRealtimeEvents(pool, redis, events));
  if (worked || Date.now() - lastRealtimeProbe >= 5000) {
    // Pub/Sub can acknowledge a publish while no API replica is listening.
    const subscriberCounts = await redis.pubsub('NUMSUB', 'tamreedy:events');
    if (!Array.isArray(subscriberCounts) || Number(subscriberCounts[1]) < 1) {
      throw Object.assign(new Error('No realtime subscriber'), {code:'REALTIME_SUBSCRIBER_UNAVAILABLE'});
    }
    lastRealtimeProbe = Date.now();
    observeLoop('realtime', true);
  }
  return worked;
}

async function flushPushOutbox(): Promise<boolean> {
  if (!fcm) return false;
  return deliverOutbox(pool, 'push', async events => {
    const stats = await pushDeliverBatch(pool, fcm, events);
    if (stats.sent || stats.failed) {
      console.info(`[Push Batch] FCM accepted: ${stats.sent}; failed or missing token: ${stats.failed}; pruned: ${stats.pruned}.`);
    }
  });
}

async function runWorker(): Promise<void> {
  await pool.query('SELECT 1');
  let applied: string[];
  try {
    applied = (await pool.query('SELECT name FROM schema_migrations')).rows.map(row => String(row.name));
  } catch {
    throw Object.assign(new Error('Migration manifest unavailable'), {code:'MIGRATION_COMPATIBILITY_ERROR'});
  }
  const missing = missingMigrations(applied);
  if (missing.length) throw Object.assign(new Error('Required release migrations missing'), {code:'MIGRATION_COMPATIBILITY_ERROR'});
  if (features.openDispatchEnabled && !features.openMarketplaceEnabled) throw new Error('FEATURE_FLAGS_CONFLICT');
  if (features.liveLocationRedisEnabled && !process.env.REDIS_URL) throw new Error('REDIS_CONFIGURATION_REQUIRED');
  const workerId = randomUUID();
  async function heartbeat(): Promise<void> {
    await pool.query(`INSERT INTO worker_heartbeats(worker_id,worker_version,runtime_config_fingerprint,
      push_configured,push_operational,push_last_success_at,push_last_error_at,
      realtime_operational,realtime_last_success_at,realtime_last_error_at,
      dispatch_last_success_at,dispatch_last_error_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
      ON CONFLICT(worker_id) DO UPDATE SET received_at=statement_timestamp(),
        push_operational=excluded.push_operational,push_last_success_at=excluded.push_last_success_at,
        push_last_error_at=excluded.push_last_error_at,realtime_operational=excluded.realtime_operational,
        realtime_last_success_at=excluded.realtime_last_success_at,realtime_last_error_at=excluded.realtime_last_error_at,
        dispatch_last_success_at=excluded.dispatch_last_success_at,dispatch_last_error_at=excluded.dispatch_last_error_at`,
      [workerId, process.env.TAMREEDY_RELEASE ?? '3.1.0-rc.3', runtimeConfigFingerprint(features), !!fcm,
       operational('push'), loopState.push.success, loopState.push.error,
       operational('realtime'), loopState.realtime.success, loopState.realtime.error,
       loopState.dispatch.success, loopState.dispatch.error]);
  }
  await heartbeat();
  console.info(JSON.stringify({
    service:'tamreedy-worker',event:'worker.started',realtimeConfigured:!!redis,pushConfigured:!!fcm,
  }));
  let stopping = false;
  let lastWinback = 0;
  let lastPushRetry = 0;
  let lastDepartureCheck = 0;
  let lastVoiceCleanup = 0;

  process.on('SIGINT', () => { stopping = true; });
  process.on('SIGTERM', () => { stopping = true; });

  async function poll(name: string, run: () => Promise<boolean>, channel?: LoopName, idleMs = 500): Promise<void> {
    while (!stopping) {
      let delay = idleMs;
      try {
        const worked = await run();
        if (channel === 'dispatch') observeLoop(channel, true);
        if (worked) continue;
      } catch (error) {
        if (channel) observeLoop(channel, false);
        logFailure(name,error);
        delay = 1500;
      }
      if (!stopping) await new Promise(resolve => setTimeout(resolve, delay));
    }
  }

  let lastSafetyRetention = 0;
  let lastSmartRecovery = 0;
  async function runBackgroundJobs(): Promise<boolean> {
    if (Date.now() - lastVoiceCleanup > 5000) {
      lastVoiceCleanup = Date.now();
      await expireVoiceCalls(pool).catch(error=>logFailure('voiceLifecycle',error));
    }
    if (Date.now() - lastSmartRecovery > 10000) {
      lastSmartRecovery = Date.now();
      await runSmartRecoveryJob(pool).catch(error=>logFailure('smartRecovery',error));
    }
    if (Date.now() - lastDepartureCheck > 5000) {
      lastDepartureCheck = Date.now();
      await notifyDelayedDepartures(pool);
    }
    if (process.env.GUARDIAN_RETENTION_ENABLED === 'true' && Date.now() - lastSafetyRetention > 3600_000) {
      lastSafetyRetention = Date.now();
      if (await runSafetyRetention(pool)) lastSafetyRetention = 0;
    }
    if (fcm && Date.now() - lastPushRetry > 5000) {
      lastPushRetry = Date.now();
      await retryPendingPushes(pool,fcm).catch(error=>{observeLoop('push', false);logFailure('retryPush',error);});
    }
    if (Date.now() - lastWinback > 6 * 3600_000) {
      lastWinback = Date.now();
      await runWinback(pool).catch(error=>logFailure('winback',error));
    }
    return processBroadcast(pool, fcm);
  }

  await Promise.all([
    ...(features.scheduledVisitsEnabled ? [poll('Scheduled Visits', () => releaseScheduledVisit(pool))] : []),
    ...(process.env.GUARDIAN_CHECKINS_ENABLED === 'true' ? [poll('Safety Check-ins', () => runSafetyCheckin(pool))] : []),
    ...(features.guardianRoutingEnabled ? [poll('Safety Case Routing', () => routeSafetyCase(pool))] : []),
    ...(nightPolicyEnabled() ? [poll('Night Safety Offers', () => closeNightIneligibleOffers(pool))] : []),
    poll('Dispatch', () => doDispatch(pool), 'dispatch'),
    ...(features.realtimeEnabled ? [poll('Realtime', flushRealtimeOutbox, 'realtime')] : []),
    ...(fcm ? [poll('Push', flushPushOutbox, 'push')] : []),
    poll('Heartbeat', async () => { await heartbeat(); return false; }, undefined, 2500),
    poll('Background Jobs', runBackgroundJobs),
  ]);
  await pool.query('DELETE FROM worker_heartbeats WHERE worker_id=$1', [workerId]);
  await redis?.quit();
  await closeLocationReader();
  await pool.end();
  console.log('[Worker Stopped] Graceful shutdown complete.');
}

void runWorker().catch(async error=>{
  logFailure('worker',error);
  redis?.disconnect();
  await closeLocationReader();
  await pool.end();
  process.exitCode=1;
});
