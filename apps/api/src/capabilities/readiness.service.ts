import { OUTBOX_HEALTH_SQL } from './readiness-queries.js';
import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { GeoIndexService } from '../live-location/geo-index.service.js';
import { missingMigrations, requiredMigrations } from '../../../../packages/backend-policy/schema.mjs';
import { FeatureCapabilitiesService } from './feature-capabilities.service.js';

@Injectable()
export class ReadinessService {
  constructor(private readonly db: DbService, private readonly geo: GeoIndexService,
    private readonly capabilities: FeatureCapabilitiesService) {}

  async report() {
    const checks: Record<string, unknown> = {};
    const failures: string[] = [];
    try {
      await this.db.query('SELECT 1');
      checks.database = {ok:true, pool:this.db.poolStats()};
    } catch {
      throw new ServiceUnavailableException({status:'unavailable', code:'DATABASE_UNAVAILABLE'});
    }
    try {
      const applied = (await this.db.query<{name:string}>('SELECT name FROM schema_migrations')).rows.map(row => row.name);
      const missing = missingMigrations(applied);
      checks.migrations = {ok:missing.length === 0, missing, appliedCount:applied.length, requiredCount:requiredMigrations.length};
      if (missing.length) failures.push('MIGRATION_COMPATIBILITY_ERROR');
    } catch {
      checks.migrations = {ok:false, status:'unknown'};
      failures.push('MIGRATION_COMPATIBILITY_ERROR');
    }
    try {
      const result = (await this.db.query(OUTBOX_HEALTH_SQL)).rows[0];
      const age = (value: unknown) => value ? (Date.now()-new Date(String(value)).getTime())/1000 : 0;
      const limit = Number(process.env.READINESS_OUTBOX_MAX_AGE_SECONDS ?? 120);
      const healthy = age(result?.oldest_realtime) <= limit && age(result?.oldest_push) <= limit && Number(result?.dead_letter_count) === 0;
      checks.outbox = {ok:healthy, pendingRealtime:result?.pending_realtime, pendingPush:result?.pending_push,
        oldestPendingRealtime:result?.oldest_realtime, oldestPendingPush:result?.oldest_push, deadLetterCount:result?.dead_letter_count};
      if (!healthy) failures.push('OUTBOX_UNHEALTHY');
    } catch {
      checks.outbox = {ok:false, status:'unknown'};
      failures.push('OUTBOX_MONITOR_UNAVAILABLE');
    }
    try {
      const heartbeat = (await this.db.query('SELECT max(received_at) AS last_seen FROM worker_heartbeats')).rows[0]?.last_seen;
      const age = heartbeat ? (Date.now()-new Date(heartbeat).getTime())/1000 : null;
      const ok = age !== null && age <= Number(process.env.READINESS_WORKER_MAX_AGE_SECONDS ?? 30);
      checks.worker = {ok, workerHeartbeatAge:age};
      if (!ok) failures.push('WORKER_UNAVAILABLE');
    } catch {
      checks.worker = {ok:false, status:'unknown'};
      failures.push('WORKER_MONITOR_UNAVAILABLE');
    }
    const redis = await this.geo.healthStatus();
    const redisRequired = redis.enabled || process.env.REALTIME_ENABLED !== 'false';
    // Geo client only exists when live GEO is enabled; test the realtime Redis separately otherwise.
    let connected = redis.connected;
    if (redisRequired && !redis.enabled) {
      const {Redis} = await import('ioredis');
      const client = process.env.REDIS_URL ? new Redis(process.env.REDIS_URL, {lazyConnect:true, enableOfflineQueue:false, maxRetriesPerRequest:0, connectTimeout:1500, commandTimeout:1500}) : null;
      if (client) {
        client.on('error', () => undefined);
        try { await client.connect(); connected = await client.ping() === 'PONG'; }
        catch { connected = false; }
        finally { client.disconnect(); }
      }
    }
    checks.redis = {...redis, required:redisRequired, connected};
    if (redisRequired && !connected) failures.push('REDIS_UNAVAILABLE');
    const pushConfigured = Boolean(process.env.FCM_SERVICE_ACCOUNT_FILE || process.env.FCM_SERVICE_ACCOUNT_JSON);
    const pushRequired = process.env.PUSH_ENABLED !== 'false';
    checks.push = {configured:pushConfigured, required:pushRequired};
    if (pushRequired && !pushConfigured) failures.push('FCM_NOT_CONFIGURED');
    const voiceRequired = process.env.VOICE_ENABLED !== 'false';
    const voiceConfigured = Boolean(process.env.TURN_URLS && process.env.TURN_SHARED_SECRET);
    checks.voice = {configured:voiceConfigured, required:voiceRequired};
    if (voiceRequired && !voiceConfigured) failures.push('VOICE_NOT_CONFIGURED');
    const capabilities = await this.capabilities.snapshot();
    checks.capabilities = {ok:capabilities.ordersStatus === 'available'};
    if (capabilities.ordersStatus !== 'available') failures.push('ORDERS_SETTINGS_UNAVAILABLE');
    if (capabilities.openDispatchEnabled && !capabilities.openMarketplaceEnabled) failures.push('FEATURE_FLAGS_CONFLICT');
    if (failures.length) {
      console.error(JSON.stringify({event:'readiness.unavailable', codes:failures}));
      throw new ServiceUnavailableException({service:'tamreedy-api', status:'unavailable', failures, checks});
    }
    return {service:'tamreedy-api', status:'ready', checks};
  }
}
