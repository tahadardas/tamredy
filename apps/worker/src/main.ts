import pg from 'pg';
import { readFileSync } from 'node:fs';
import Redis from 'ioredis';
import 'dotenv/config';
import { FcmClient, loadServiceAccount, pushDeliverBatch, retryPendingPushes } from './push.js';
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
console.log(`[Worker Boot] Redis: ${redis ? 'Configured (' + process.env.REDIS_URL + ')' : 'Not configured'}`);
console.log(`[Worker Boot] Push (FCM): ${fcm ? 'CONFIGURED & READY (Project: ' + sa?.project_id + ')' : 'NOT_CONFIGURED (Push disabled, fallback REST polling & Socket.IO active)'}`);

/** Flushes realtime events to Redis / Socket.IO (independent from push). */
async function flushRealtimeOutbox(): Promise<boolean> {
  if (!redis) return false;
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const rows = await c.query(`
      SELECT id, event_type, aggregate_id, payload
      FROM outbox_events
      WHERE realtime_published_at IS NULL
      ORDER BY id ASC
      LIMIT 20
      FOR UPDATE SKIP LOCKED
    `);

    if (!rows.rowCount) {
      await c.query('COMMIT');
      return false;
    }

    const publishedIds: string[] = [];
    for (const event of rows.rows) {
      await redis.publish(
        'tamreedy:events',
        JSON.stringify({ eventId: event.id, type: event.event_type, payload: event.payload })
      );
      publishedIds.push(String(event.id));
    }

    await c.query(`UPDATE outbox_events SET realtime_published_at = now() WHERE id = ANY($1::bigint[])`, [publishedIds]);
    await c.query('COMMIT');
    return true;
  } catch (e) {
    await c.query('ROLLBACK');
    console.error('[Realtime Outbox Error]', e);
    return false;
  } finally {
    c.release();
  }
}

/** Flushes pushes to Firebase FCM and maintains delivery ledger in notification_deliveries. */
async function flushPushOutbox(): Promise<boolean> {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const rows = await c.query(`
      SELECT id, event_type, aggregate_id, payload
      FROM outbox_events
      WHERE push_published_at IS NULL
      ORDER BY id ASC
      LIMIT 20
      FOR UPDATE SKIP LOCKED
    `);

    if (!rows.rowCount) {
      await c.query('COMMIT');
      return false;
    }

    if (fcm) {
      const stats = await pushDeliverBatch(c, fcm, rows.rows);
      if (stats.sent > 0 || stats.failed > 0) {
        console.log(`[Push Batch] Processed: ${stats.sent} sent, ${stats.failed} failed/missing token, ${stats.pruned} pruned.`);
      }
    }

    const ids = rows.rows.map(r => String(r.id));
    await c.query(`UPDATE outbox_events SET push_published_at = now() WHERE id = ANY($1::bigint[])`, [ids]);
    await c.query('COMMIT');
    return true;
  } catch (e) {
    await c.query('ROLLBACK');
    console.error('[Push Outbox Error]', e);
    return false;
  } finally {
    c.release();
  }
}

async function runWorker(): Promise<void> {
  let stopping = false;
  let lastWinback = 0;
  let lastPushRetry = 0;

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
