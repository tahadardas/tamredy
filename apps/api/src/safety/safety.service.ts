import { Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import { SafetyRepository, SafetyPointRecord } from './safety.repository.js';
import type { ReportSosDto, SafetyLocationBatchDto } from './safety.dto.js';

const maxTrackingHours = 12;
const clockToleranceMs = 60_000;

@Injectable()
export class SafetyService {
  constructor(private readonly repository: SafetyRepository) {}

  status(owner: string) {
    return this.repository.status(owner);
  }

  start(owner: string, assignmentId: string) {
    return this.repository.transaction(async client => {
      const assignment = await this.repository.assignment(client, owner, assignmentId);
      if (!assignment) missing();
      if (assignment.status !== 'ACTIVE' || !['EN_ROUTE','ARRIVED','IN_SERVICE'].includes(assignment.request_status)) {
        conflict('SAFETY_ASSIGNMENT_NOT_IN_PROGRESS');
      }
      const session = await this.repository.start(client, assignmentId);
      if (session.checked_out_at) conflict('SAFETY_SESSION_ALREADY_CHECKED_OUT');
      return session;
    });
  }

  upload(owner: string, sessionId: string, dto: SafetyLocationBatchDto) {
    return this.repository.transaction(async client => {
      const session = await this.repository.session(client, owner, sessionId);
      if (!session) missing();
      const started = new Date(session.started_at).getTime();
      const now = Date.now();
      const stopped = session.checked_out_at ? new Date(session.checked_out_at).getTime() : Infinity;
      if (now > Math.min(stopped,started + maxTrackingHours * 3_600_000) + 24 * 3_600_000) {
        conflict('SAFETY_UPLOAD_WINDOW_EXPIRED');
      }
      const maximum = Math.min(
        now + clockToleranceMs,
        started + maxTrackingHours * 3_600_000,
        stopped,
      );
      const points = new Map<number, SafetyPointRecord>();
      for (const point of dto.points) {
        const captured = Date.parse(point.capturedAt);
        if (!Number.isFinite(captured) || captured < started - clockToleranceMs || captured > maximum) {
          invalid('Location capture time is outside the safety session');
        }
        const record = {
          sequence: point.sequence, latitude: point.latitude, longitude: point.longitude,
          accuracy: point.accuracy, captured_at: new Date(captured).toISOString(),
        };
        const hash = createHash('sha256').update(JSON.stringify(record)).digest('hex');
        const previous = points.get(point.sequence);
        if (previous && previous.hash !== hash) conflict('SAFETY_POINT_SEQUENCE_CONFLICT');
        points.set(point.sequence, { ...record, hash });
      }
      await this.repository.insertPoints(client, sessionId, [...points.values()]);
      const stored = await this.repository.storedHashes(client, sessionId, [...points.keys()]);
      if (stored.length !== points.size || stored.some(row => row.payload_hash !== points.get(row.sequence_no)?.hash)) {
        conflict('SAFETY_POINT_SEQUENCE_CONFLICT');
      }
      return { acceptedSequences: [...points.keys()] };
    });
  }

  checkout(owner: string, sessionId: string) {
    return this.repository.transaction(async client => {
      if (!await this.repository.session(client, owner, sessionId)) missing();
      return this.repository.checkout(client, sessionId);
    });
  }

  sos(owner: string, dto: ReportSosDto) {
    if (dto.expectedReporterId !== undefined && dto.expectedReporterId !== owner) forbidden();
    const triggerTime = dto.triggeredAt === undefined ? null : Date.parse(dto.triggeredAt);
    if (triggerTime !== null && (!Number.isFinite(triggerTime) || triggerTime > Date.now() + 60_000)) {
      invalid('SOS trigger time is invalid');
    }
    return this.repository.transaction(async client => {
      let event = await this.repository.eventByKey(client, owner, dto.clientEventId);
      if (!event) {
        if (dto.sessionId && !await this.repository.session(client, owner, dto.sessionId)) missing();
        event = await this.repository.report(client, owner, dto);
        if (event) await this.repository.recordReceived(client, event.id, owner);
        else event = await this.repository.eventByKey(client, owner, dto.clientEventId);
      }
      if (event.session_id !== (dto.sessionId ?? null) || event.silent !== dto.silent ||
          (event.triggered_at ? new Date(event.triggered_at).getTime() : null) !== triggerTime) {
        conflict('SOS_CLIENT_EVENT_ID_CONFLICT');
      }
      return event;
    });
  }

  async event(owner: string, id: string) {
    return await this.repository.event(owner, id) ?? missing();
  }
}
