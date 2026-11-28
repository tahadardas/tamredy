import { Controller, Get, Header } from '@nestjs/common';
import { ReadinessService } from './capabilities/readiness.service.js';
import { FeatureCapabilitiesService } from './capabilities/feature-capabilities.service.js';
import { OperationalMetricsService } from './observability/operational-metrics.service.js';

@Controller()
export class AppController {
  constructor(private readonly readiness: ReadinessService,
    private readonly features: FeatureCapabilitiesService,
    private readonly metrics: OperationalMetricsService) {}

  @Get('/health')
  health() { return {service:'tamreedy-api', status:'ok'}; }

  @Get('/ready')
  ready() { return this.readiness.report(); }

  @Get('/health/ready')
  healthReady() { return this.readiness.report(); }

  @Get('/v1/capabilities')
  capabilities() { return this.features.snapshot(); }

  @Get('/metrics')
  @Header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  metricsEndpoint() { return this.metrics.render(); }
}
