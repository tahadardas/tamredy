import { closeNightIneligibleOffers, nightPolicyEnabled } from './night-safety.js';
import pg from 'pg';
import { readFileSync } from 'node:fs';
import Redis from 'ioredis';
import 'dotenv/config';
import { FcmClient, loadServiceAccount, pushDeliverBatch, retryPendingPushes } from './push.js';
import { notifyDelayedDepartures } from './departure-reminders.js';
import { deliverOutbox } from './outbox.js';
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
const redis = process.env.REDIS_URL ? new Redis(process.env.REDIS_URL, { enableOfflineQueue: false, maxRetriesPerRequest: 1, commandTimeout: 2000, retryStrategy: (times) => Math.min(times * 500, 5000) }) : undefined;

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
  const raw = process.env.FCM_SERVICE_ACCOUNT_FILE
    ? readFileSync(process.env.FCM_SERVICE_ACCOUNT_FILE, 'utf8')
    : process.env.FCM_SERVICE_ACCOUNT_JSON;
  sa = loadServiceAccount(raw);
} catch (e) {
  logFailure('push.configuration',e);
}

const fcm = sa ? new FcmClient(sa) : undefined;

async function flushRealtimeOutbox(): Promise<boolean> {
  if (!redis) return false;
  return deliverOutbox(pool, 'realtime', async events => {
    for (const event of events) {
      await redis.publish('tamreedy:events', JSON.stringify({
        eventId: String(event.id), type: event.event_type, payload: event.payload,
      }));
    }
  });
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

  async function poll(name: string, run: () => Promise<boolean>): Promise<void> {
    while (!stopping) {
      let delay = 500;
      try {
        if (await run()) continue;
      } catch (error) {
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
      await retryPendingPushes(pool,fcm).catch(error=>logFailure('retryPush',error));
    }
    if (Date.now() - lastWinback > 6 * 3600_000) {
      lastWinback = Date.now();
      await runWinback(pool).catch(error=>logFailure('winback',error));
    }
    return processBroadcast(pool, fcm);
  }

  await Promise.all([
    ...(process.env.SCHEDULED_VISITS_ENABLED === 'true' ? [poll('Scheduled Visits', () => releaseScheduledVisit(pool))] : []),
    ...(process.env.GUARDIAN_CHECKINS_ENABLED === 'true' ? [poll('Safety Check-ins', () => runSafetyCheckin(pool))] : []),
    ...(process.env.GUARDIAN_ROUTING_ENABLED === 'true' ? [poll('Safety Case Routing', () => routeSafetyCase(pool))] : []),
    ...(nightPolicyEnabled() ? [poll('Night Safety Offers', () => closeNightIneligibleOffers(pool))] : []),
    poll('Dispatch', () => doDispatch(pool)),
    poll('Realtime', flushRealtimeOutbox),
    poll('Push', flushPushOutbox),
    poll('Background Jobs', runBackgroundJobs),
  ]);
  await redis?.quit();
  await pool.end();
  console.log('[Worker Stopped] Graceful shutdown complete.');
}

void runWorker().catch(async error=>{
  logFailure('worker',error);
  redis?.disconnect();
  await pool.end();
  process.exitCode=1;
});
