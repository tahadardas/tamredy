import { OUTBOX_HEALTH_SQL } from './readiness-queries.js';
import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { GeoIndexService } from '../live-location/geo-index.service.js';
import { missingMigrations, requiredMigrations } from '../../../../packages/backend-policy/schema.mjs';
import { FeatureCapabilitiesService } from './feature-capabilities.service.js';
import { featureCapabilities, runtimeConfigFingerprint } from '../../../../packages/backend-policy/capabilities.mjs';

@Injectable()
export class ReadinessService {
  constructor(private readonly db: DbService, private readonly geo: GeoIndexService,
    private readonly capabilities: FeatureCapabilitiesService) {}

  async report() {
    const checks: Record<string, unknown> = {};
    const failures: string[] = [];
    const features = featureCapabilities();
    const expectedFingerprint = runtimeConfigFingerprint(features);
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
      const result = (await this.db.query(OUTBOX_HEALTH_SQL, [features.realtimeEnabled, features.pushEnabled])).rows[0];
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
      const limit = Number(process.env.READINESS_WORKER_MAX_AGE_SECONDS ?? 30);
      const worker = (await this.db.query(`SELECT *, extract(epoch FROM statement_timestamp()-received_at) AS age_seconds
        FROM worker_heartbeats WHERE received_at >= statement_timestamp() - $1::double precision * interval '1 second'
        ORDER BY (runtime_config_fingerprint IS NOT DISTINCT FROM $2) DESC, received_at DESC LIMIT 1`,
      [limit, expectedFingerprint])).rows[0];
      const fresh = !!worker && Number(worker.age_seconds) <= limit;
      const configMatches = fresh && worker.runtime_config_fingerprint === expectedFingerprint;
      const versionMatches = fresh && worker.worker_version === (process.env.TAMREEDY_RELEASE ?? '3.1.0-rc.3');
      const lastDispatchSuccess = worker?.dispatch_last_success_at;
      const dispatchOperational = fresh && !!lastDispatchSuccess &&
        Date.now() - new Date(lastDispatchSuccess).getTime() <= limit * 1000 &&
        (!worker.dispatch_last_error_at || worker.dispatch_last_success_at >= worker.dispatch_last_error_at);
      checks.worker = {ok:fresh && configMatches && versionMatches && dispatchOperational,
        workerHeartbeatAge:fresh ? Number(worker.age_seconds) : null, version:worker?.worker_version ?? null,
        configFingerprint:worker?.runtime_config_fingerprint ?? null, configMatches, versionMatches,
        dispatchOperational, dispatchLastSuccessAt:worker?.dispatch_last_success_at ?? null,
        dispatchLastErrorAt:worker?.dispatch_last_error_at ?? null};
      if (!fresh) failures.push('WORKER_UNAVAILABLE');
      else if (!configMatches || !versionMatches) failures.push('WORKER_CONFIGURATION_MISMATCH');
      else if (!dispatchOperational) failures.push('DISPATCH_UNAVAILABLE');
      const configured = fresh ? worker.push_configured === true : null;
      const operational = fresh ? worker.push_operational ?? null : null;
      const pushStatus = !features.pushEnabled ? 'DISABLED' : !fresh || !configured ? 'UNKNOWN'
        : operational === true ? 'OPERATIONAL' : operational === false ? 'DEGRADED' : 'CONFIGURED';
      checks.push = {status:pushStatus, configured, operational, required:features.pushEnabled,
        lastSuccessAt:worker?.push_last_success_at ?? null, lastErrorAt:worker?.push_last_error_at ?? null};
      if (features.pushEnabled && fresh && !configured) failures.push('FCM_NOT_CONFIGURED');
      if (features.pushEnabled && fresh && configured && operational === false) failures.push('FCM_DEGRADED');
      const realtimeOperational = fresh ? worker.realtime_operational ?? null : null;
      checks.realtime = {operational:realtimeOperational, required:features.realtimeEnabled,
        lastSuccessAt:worker?.realtime_last_success_at ?? null, lastErrorAt:worker?.realtime_last_error_at ?? null};
      if (features.realtimeEnabled && fresh && realtimeOperational !== true) failures.push('REALTIME_UNAVAILABLE');
    } catch {
      checks.worker = {ok:false, status:'unknown'};
      checks.push = {status:features.pushEnabled ? 'UNKNOWN' : 'DISABLED', required:features.pushEnabled};
      failures.push('WORKER_MONITOR_UNAVAILABLE');
    }
    const redis = await this.geo.healthStatus();
    const redisRequired = (redis.enabled && !features.locationPostgresFallbackEnabled) || features.realtimeEnabled;
    // Geo client only exists when live GEO is enabled; test the realtime Redis separately otherwise.
    let connected = redis.connected;
    if (redisRequired && !redis.enabled) {
      const {Redis} = await import('ioredis');
      let client: InstanceType<typeof Redis> | null = null;
      try {
        if (process.env.REDIS_URL) {
          client = new Redis(process.env.REDIS_URL, {lazyConnect:true, enableOfflineQueue:false, maxRetriesPerRequest:0, connectTimeout:1500, commandTimeout:1500});
          client.on('error', () => undefined);
          await client.connect();
          connected = await client.ping() === 'PONG';
        }
      } catch { connected = false; }
      finally { client?.disconnect(); }
    }
    checks.redis = {...redis, required:redisRequired, connected};
    if (redisRequired && !connected) failures.push('REDIS_UNAVAILABLE');
    const voiceRequired = features.voiceEnabled;
    const turnUrls = process.env.TURN_URLS?.split(',').map(value => value.trim()).filter(Boolean) ?? [];
    const voiceConfigured = turnUrls.length > 0 && turnUrls.every(value => /^turns?:[^\s,]+$/.test(value))
      && Boolean(process.env.TURN_SHARED_SECRET?.trim());
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
