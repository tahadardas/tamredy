import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { conflict, missing } from '../common/errors.js';
import { SafetyRepository } from './safety.repository.js';
import { SafeAbortRepository } from './safe-abort.repository.js';
import type { SafeAbortDto } from './safety.dto.js';

@Injectable()
export class SafeAbortService {
  constructor(private readonly aborts: SafeAbortRepository, private readonly safety: SafetyRepository) {}

  abort(owner: string, assignment: string, dto: SafeAbortDto) {
    return this.aborts.transaction(async client => {
      const target = await this.aborts.lockAssignment(client, assignment, owner);
      if (!target) missing();
      const previous = await this.aborts.existing(client, assignment);
      if (previous) return { status: 'ESCALATED', eventId: previous.emergency_event_id };
      if (target.assignmentStatus !== 'ACTIVE' ||
          !['ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE'].includes(target.request.status)) {
        conflict('SAFETY_ABORT_ASSIGNMENT_INACTIVE');
      }
      const session = await this.aborts.safetySession(client, assignment);
      let eventId = session ? await this.aborts.openEvent(client, session) : undefined;
      if (!eventId) {
        const event = await this.safety.report(client, owner, {
          clientEventId: randomUUID(), sessionId: session, silent: true,
        });
        await this.safety.recordReceived(client, event.id, owner);
        eventId = event.id as string;
      }
      await this.aborts.finish(client, {
        assignment, requestId: target.request.id, requester: target.request.requester_user_id,
        nurse: target.nurseId, actor: owner, eventId, reason: dto.reason,
      });
      return { status: 'ESCALATED', eventId };
    });
  }
}
