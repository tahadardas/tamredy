import { Controller, Get, Header, ServiceUnavailableException } from '@nestjs/common';
import { DbService } from './db/db.service.js';
import { GeoIndexService } from './live-location/geo-index.service.js';
import { OperationalMetricsService } from './observability/operational-metrics.service.js';

@Controller()
export class AppController {
  constructor(
    private readonly db: DbService,
    private readonly geo: GeoIndexService,
    private readonly metrics: OperationalMetricsService,
  ) {}

  @Get('/health')
  health() { return { service: 'tamreedy-api', status: 'ok' }; }

  @Get('/ready')
  async ready() {
    return this.buildReadinessReport();
  }

  /** BUG-048: Full readiness probe verifying DB, migrations, Redis, outbox backlog, and FCM readiness. */
  @Get('/health/ready')
  async healthReady() {
    return this.buildReadinessReport();
  }

  /** BUG-047: Canonical server capability flags for mobile feature gating. */
  @Get('/v1/capabilities')
  async capabilities() {
    let orders: { accepting?: boolean; pausedMessage?: string } | null = null;
    try {
      const r = await this.db.query(`SELECT value FROM app_settings WHERE key='orders'`);
      orders = (r.rows[0]?.value as { accepting?: boolean; pausedMessage?: string } | undefined) ?? null;
    } catch {
      orders = null;
    }
    return {
      scheduledVisitsEnabled: process.env.SCHEDULED_VISITS_ENABLED === 'true',
      openMarketplaceEnabled: true,
      openDispatchEnabled: process.env.OPEN_DISPATCH_ENABLED === 'true',
      liveLocationRedisEnabled: process.env.LIVE_LOCATION_REDIS_ENABLED === 'true',
      guardianNightPolicyEnabled: process.env.GUARDIAN_NIGHT_POLICY_ENABLED === 'true',
      walletProviderEnabled: process.env.WALLET_PROVIDER_ENABLED === 'true',
      ordersAccepting: orders?.accepting !== false,
      pausedMessage: orders?.pausedMessage ?? null,
      serverTime: new Date().toISOString(),
    };
  }

  private async buildReadinessReport() {
    try {
      await this.db.query('SELECT 1');
      await this.geo.assertReady();
    } catch {
      throw new ServiceUnavailableException({ code: 'DATABASE_UNAVAILABLE' });
    }

    let latestMigration: string | null = null;
    let appliedMigrations = 0;
    try {
      const mig = await this.db.query(
        `SELECT name FROM schema_migrations ORDER BY name DESC LIMIT 1`,
      );
      const count = await this.db.query(`SELECT count(*)::int AS cnt FROM schema_migrations`);
      latestMigration = mig.rows[0]?.name ?? null;
      appliedMigrations = Number(count.rows[0]?.cnt ?? 0);
    } catch {
      latestMigration = null;
    }

    let pendingOutbox = 0;
    let oldestPendingAt: string | null = null;
    try {
      const ob = await this.db.query(
        `SELECT count(*)::int AS pending,
                min(created_at) AS oldest_at
         FROM outbox_events
         WHERE realtime_published_at IS NULL OR push_delivered_at IS NULL`,
      );
      pendingOutbox = Number(ob.rows[0]?.pending ?? 0);
      oldestPendingAt = ob.rows[0]?.oldest_at ? new Date(ob.rows[0].oldest_at).toISOString() : null;
    } catch {
      pendingOutbox = 0;
    }

    const redisHealth = await this.geo.healthStatus();
    const pushConfigured = Boolean(
      process.env.FCM_SERVICE_ACCOUNT_FILE || process.env.FCM_SERVICE_ACCOUNT_JSON,
    );

    return {
      service: 'tamreedy-api',
      status: 'ready',
      checks: {
        database: { ok: true, pool: this.db.poolStats() },
        migrations: { appliedCount: appliedMigrations, latest: latestMigration },
        redis: redisHealth,
        outbox: { pendingCount: pendingOutbox, oldestPendingAt },
        push: { configured: pushConfigured },
      },
    };
  }

  @Get('/metrics')
  @Header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  metricsEndpoint() { return this.metrics.render(); }
}
