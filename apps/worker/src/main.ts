import pg from 'pg';
import { readFileSync } from 'node:fs';
import Redis from 'ioredis';
import 'dotenv/config';
import { FcmClient, loadServiceAccount, pushDeliverBatch, retryPendingPushes } from './push.js';
import { notifyDelayedDepartures } from './departure-reminders.js';
import { deliverOutbox } from './outbox.js';
import { routeSafetyCase } from './safety-routing.js';
import { runSafetyCheckin } from './safety-checkins.js';
import { releaseScheduledVisit } from './scheduling.js';
import { doDispatch } from './dispatch.js';
import { processBroadcast, runWinback } from './marketing.js';

const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) throw new Error('DATABASE_URL required');

const pool = new pg.Pool({ connectionString: dbUrl, max: 10, statement_timeout: 10000 });
const redis = process.env.REDIS_URL ? new Redis(process.env.REDIS_URL, { enableOfflineQueue: false, maxRetriesPerRequest: 1, commandTimeout: 2000, retryStrategy: (times) => Math.min(times * 500, 5000) }) : undefined;

let sa;
try {
  const raw = process.env.FCM_SERVICE_ACCOUNT_FILE
    ? readFileSync(process.env.FCM_SERVICE_ACCOUNT_FILE, 'utf8')
    : process.env.FCM_SERVICE_ACCOUNT_JSON;
  sa = loadServiceAccount(raw);
} catch (e) {
  console.warn('[FCM] Notice: Service account file could not be read or parsed:', e);
}

const fcm = sa ? new FcmClient(sa) : undefined;
console.log(`[Worker Boot] Starting Tamreedy Dispatch & Notification Engine...`);
console.log(`[Worker Boot] Database: Connected`);
console.log(`[Worker Boot] Redis: ${redis ? 'Configured' : 'Not configured'}`);
console.log(`[Worker Boot] Push (FCM): ${fcm ? 'CONFIGURED & READY (Project: ' + sa?.project_id + ')' : 'NOT_CONFIGURED (Push disabled, fallback REST polling & Socket.IO active)'}`);

async function flushRealtimeOutbox(): Promise<boolean> {
  if (!redis) return false;
  return deliverOutbox(pool, 'realtime', async events => {
    for (const event of events) {
      await redis.publish('tamreedy:events', JSON.stringify({
        eventId: event.id, type: event.event_type, payload: event.payload,
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
  let stopping = false;
  let lastWinback = 0;
  let lastPushRetry = 0;
  let lastDepartureCheck = 0;

  process.on('SIGINT', () => { stopping = true; });
  process.on('SIGTERM', () => { stopping = true; });

  async function poll(name: string, run: () => Promise<boolean>): Promise<void> {
    while (!stopping) {
      let delay = 500;
      try {
        if (await run()) continue;
      } catch (error) {
        console.error(`[${name} Error]`, error);
        delay = 1500;
      }
      if (!stopping) await new Promise(resolve => setTimeout(resolve, delay));
    }
  }

  async function runBackgroundJobs(): Promise<boolean> {
    if (Date.now() - lastDepartureCheck > 5000) {
      lastDepartureCheck = Date.now();
      await notifyDelayedDepartures(pool);
    }
    if (fcm && Date.now() - lastPushRetry > 5000) {
      lastPushRetry = Date.now();
      await retryPendingPushes(pool, fcm).catch(error => console.error('[Retry Push Error]', error));
    }
    if (Date.now() - lastWinback > 6 * 3600_000) {
      lastWinback = Date.now();
      await runWinback(pool).catch(error => console.error('[Winback Error]', error));
    }
    return processBroadcast(pool, fcm);
  }

  await Promise.all([
    ...(process.env.SCHEDULED_VISITS_ENABLED === 'true' ? [poll('Scheduled Visits', () => releaseScheduledVisit(pool))] : []),
    ...(process.env.GUARDIAN_CHECKINS_ENABLED === 'true' ? [poll('Safety Check-ins', () => runSafetyCheckin(pool))] : []),
    ...(process.env.GUARDIAN_ROUTING_ENABLED === 'true' ? [poll('Safety Case Routing', () => routeSafetyCase(pool))] : []),
    poll('Dispatch', () => doDispatch(pool)),
    poll('Realtime', flushRealtimeOutbox),
    poll('Push', flushPushOutbox),
    poll('Background Jobs', runBackgroundJobs),
  ]);
  await redis?.quit();
  await pool.end();
  console.log('[Worker Stopped] Graceful shutdown complete.');
}

void runWorker();
