import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import { readLiveLocation } from '../../../../packages/backend-policy/live-location.mjs';
import { GeoIndexService } from './geo-index.service.js';

export interface LiveLocationSnapshot {
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  recordedAt: Date;
  capturedAt: Date;
  sequenceNumber: number | null;
  source: 'redis' | 'postgres';
  sessionId: string | null;
}

export function haversineDistanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const radians = (value: number) => (value * Math.PI) / 180;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * BUG-033 / BUG-037: Canonical Redis-first live location reader with PostGIS fallback.
 * Prevents stale 30s PostgreSQL checkpoints from masking fresher Redis coordinates
 * during tracking, readiness checks, ETA estimation, and arrival geofence verification.
 */
@Injectable()
export class LiveLocationReadService {
  constructor(
    private readonly db: DbService,
    private readonly geo: GeoIndexService,
  ) {}

  async getNurseLocation(nurseId: string, client?: PoolClient): Promise<LiveLocationSnapshot | null> {
    try {
      const location = await readLiveLocation({nurseId,redis:this.geo.connection,db:client??this.db,
        redisEnabled:this.geo.active,allowPostgresFallback:process.env.LOCATION_POSTGRES_FALLBACK_ENABLED==='true'});
      if (!location?.sessionId) return null;
      const sql=`SELECT 1 FROM device_sessions ds JOIN nurses n ON n.user_id=ds.user_id
        WHERE n.id=$1 AND ds.id=$2 AND ds.revoked_at IS NULL`;
      const params=[nurseId,location.sessionId];
      const validSession=client ? await client.query(sql,params) : await this.db.query(sql,params);
      return validSession.rowCount ? location : null;
    } catch {
      throw new ServiceUnavailableException({code:'LIVE_LOCATION_UNAVAILABLE'});
    }
  }
}
