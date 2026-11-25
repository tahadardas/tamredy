import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import type { LiveLocationUpdateDto } from './location-update.dto.js';
import type { PreviousLocation } from './location-validator.js';

export interface NurseLocationContext {
  nurseId: string;
  workStatus: string;
  availabilityIntent: string;
}

@Injectable()
export class LocationPersistenceService {
  constructor(private readonly db: DbService) {}

  async context(userId: string): Promise<NurseLocationContext> {
    const result = await this.db.query(
      `SELECT id,work_status,availability_intent FROM nurses WHERE user_id=$1`,
      [userId],
    );
    if (!result.rowCount) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });
    const nurse = result.rows[0];
    const active = ['RESERVED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE'].includes(nurse.work_status);
    if ((nurse.availability_intent === 'OFFLINE' && !active) || nurse.work_status === 'SUSPENDED') {
      throw new ConflictException({ code: 'LOCATION_UPDATES_NOT_ALLOWED' });
    }
    return { nurseId: nurse.id, workStatus: nurse.work_status, availabilityIntent: nurse.availability_intent };
  }

  async current(nurseId: string): Promise<PreviousLocation | null> {
    const result = await this.db.query(
      `SELECT ST_Y(location::geometry) AS latitude,ST_X(location::geometry) AS longitude,
        captured_at,sequence_number,session_id FROM nurse_locations WHERE nurse_id=$1`,
      [nurseId],
    );
    if (!result.rowCount) return null;
    const row = result.rows[0];
    return {
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      capturedAt: new Date(row.captured_at),
      sequenceNumber: Number(row.sequence_number),
      sessionId: row.session_id,
    };
  }

  async persist(nurseId: string, dto: LiveLocationUpdateDto, capturedAt: Date, receivedAt: Date): Promise<boolean> {
    const result = await this.db.query(
      `INSERT INTO nurse_locations(
        nurse_id,location,accuracy_m,recorded_at,captured_at,received_at,sequence_number,
        session_id,speed_mps,heading_degrees,location_source)
       VALUES($1,ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,$4,$5,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT(nurse_id) DO UPDATE SET
        location=EXCLUDED.location,accuracy_m=EXCLUDED.accuracy_m,recorded_at=EXCLUDED.captured_at,
        captured_at=EXCLUDED.captured_at,received_at=EXCLUDED.received_at,
        sequence_number=EXCLUDED.sequence_number,session_id=EXCLUDED.session_id,
        speed_mps=EXCLUDED.speed_mps,heading_degrees=EXCLUDED.heading_degrees,
        location_source=EXCLUDED.location_source
       WHERE nurse_locations.captured_at < EXCLUDED.captured_at
         AND (nurse_locations.session_id <> EXCLUDED.session_id
           OR nurse_locations.sequence_number < EXCLUDED.sequence_number)
       RETURNING nurse_id`,
      [
        nurseId, dto.longitude, dto.latitude, dto.accuracyMeters, capturedAt.toISOString(),
        receivedAt.toISOString(), dto.sequenceNumber, dto.sessionId,
        dto.speedMetersPerSecond ?? null, dto.heading ?? null, dto.locationSource,
      ],
    );
    return Boolean(result.rowCount);
  }
}

