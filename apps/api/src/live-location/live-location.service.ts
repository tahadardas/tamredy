import { ConflictException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { LiveLocationUpdateDto } from './location-update.dto.js';
import { GeoIndexService } from './geo-index.service.js';
import { LocationPersistenceService } from './location-persistence.service.js';
import { LocationValidator } from './location-validator.js';
import { TrackingAuthorizationService } from './tracking-authorization.service.js';
import { OperationalMetricsService } from '../observability/operational-metrics.service.js';

export interface LocationIngestionResult {
  accepted: true;
  receivedAt: string;
  sequenceNumber: number;
  tracking: {
    requestId: string;
    assignmentId: string;
    patientUserId: string;
  } | null;
}

@Injectable()
export class LiveLocationService {
  constructor(
    private readonly geo: GeoIndexService,
    private readonly persistence: LocationPersistenceService,
    private readonly validator: LocationValidator,
    private readonly trackingAuthorization: TrackingAuthorizationService,
    private readonly metrics: OperationalMetricsService,
  ) {}

  async ingest(userId: string, deviceSessionId: string | undefined, dto: LiveLocationUpdateDto): Promise<LocationIngestionResult> {
    if (!deviceSessionId) throw new ConflictException({ code: 'DEVICE_SESSION_REQUIRED' });
    const context = await this.persistence.context(userId);
    let previous = null;
    try {
      previous = await this.geo.current(context.nurseId);
    } catch {
      previous = null;
    }
    previous ??= await this.persistence.current(context.nurseId);
    const capturedAt = this.validator.validate(dto, deviceSessionId, previous);
    const receivedAt = new Date();

    let redisAccepted = false;
    let redisFailed = false;
    if (this.geo.active) {
      try {
        redisAccepted = await this.geo.update(context.nurseId, dto, capturedAt, receivedAt);
      } catch {
        redisFailed = true;
      }
      if (!redisFailed && !redisAccepted) throw new ConflictException({ code: 'LOCATION_OUT_OF_ORDER' });
    }

    if (redisFailed && process.env.LOCATION_POSTGRES_FALLBACK_ENABLED !== 'true') {
      throw new ServiceUnavailableException({ code: 'LIVE_LOCATION_UNAVAILABLE' });
    }

    const shouldPersist = !this.geo.active || redisFailed || await this.geo.claimPersistenceWindow(context.nurseId);
    if (shouldPersist) {
      const persisted = await this.persistence.persist(context.nurseId, dto, capturedAt, receivedAt);
      if (!persisted && (!this.geo.active || redisFailed)) {
        throw new ConflictException({ code: 'LOCATION_OUT_OF_ORDER' });
      }
    }

    const tracking = await this.trackingAuthorization.recipient(context.nurseId, dto.assignmentId);
    this.metrics.increment('location_updates_total');
    return {
      accepted: true,
      receivedAt: receivedAt.toISOString(),
      sequenceNumber: dto.sequenceNumber,
      tracking,
    };
  }
}

