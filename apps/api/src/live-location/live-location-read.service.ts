import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import { GeoIndexService } from './geo-index.service.js';

export interface LiveLocationSnapshot {
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  recordedAt: Date;
  capturedAt: Date;
  sequenceNumber: number | null;
  source: 'redis' | 'postgres';
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
    let redisFailed = false;
    if (this.geo.active) {
      try {
        const live = await this.geo.currentDetailed(nurseId);
        if (live) return live;
      } catch {
        redisFailed = true;
      }
    }
    if (redisFailed && process.env.LOCATION_POSTGRES_FALLBACK_ENABLED === 'false') {
      throw new ServiceUnavailableException({ code: 'LIVE_LOCATION_UNAVAILABLE' });
    }
    const sql = `SELECT ST_Y(location::geometry) AS latitude,
              ST_X(location::geometry) AS longitude,
              accuracy_m,
              recorded_at,
              captured_at,
              sequence_number
       FROM nurse_locations
       WHERE nurse_id = $1`;
    const r = client ? await client.query(sql, [nurseId]) : await this.db.query(sql, [nurseId]);
    if (!r.rowCount) return null;
    const row = r.rows[0];
    if (row.latitude === null || row.longitude === null || !row.recorded_at) return null;
    return {
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      accuracyMeters: Number(row.accuracy_m ?? 9999),
      recordedAt: new Date(row.recorded_at),
      capturedAt: new Date(row.captured_at ?? row.recorded_at),
      sequenceNumber: row.sequence_number !== null && row.sequence_number !== undefined
        ? Number(row.sequence_number)
        : null,
      source: 'postgres',
    };
  }
}
