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
  health() { return {service:'tamreedy-api',status:'ok'}; }

  @Get('/ready')
  async ready() {
    try {
      await this.db.query('SELECT 1');
      await this.geo.assertReady();
    } catch {
      throw new ServiceUnavailableException({code:'DATABASE_UNAVAILABLE'});
    }
    return {service:'tamreedy-api',status:'ready'};
  }

  @Get('/metrics')
  @Header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  metricsEndpoint() { return this.metrics.render(); }
}
