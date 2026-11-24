import { Injectable } from '@nestjs/common';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import type { SafetyCaseActionDto } from './staff-cases.dto.js';
import { ShiftsRepository } from './shifts.repository.js';
import { StaffCasesRepository } from './staff-cases.repository.js';

export type StaffAction = 'ACKNOWLEDGED' | 'ESCALATED' | 'RESOLVED';

@Injectable()
export class StaffCasesService {
  constructor(private readonly repository: StaffCasesRepository, private readonly shifts: ShiftsRepository) {}

  dashboard(actor: string) {
    return this.repository.transaction(async client => {
      const grant = await this.repository.grant(client, actor);
      if (!grant) forbidden();
      const supervisor = grant === 'SAFETY_SUPERVISOR';
      const counts = await this.repository.dashboard(client, actor, supervisor);
      const shifts = await this.shifts.coverage(client);
      const covered = shifts.filter(shift => shift.primary_present || shift.backup_present).length;
      const coverage = covered === 0 ? 'UNCOVERED' : covered < shifts.length ? 'PARTIAL' : 'COVERED';
      return { canResolve: supervisor, counts, coverage, shifts };
    });
  }

  list(actor: string) {
    return this.repository.transaction(async client => {
      const grant = await this.repository.grant(client, actor);
      if (!grant) forbidden();
      const cases = await this.repository.list(client, actor, grant === 'SAFETY_SUPERVISOR');
      await this.repository.audit(client, actor, 'safety.queue_viewed', actor);
      return cases;
    });
  }

  detail(actor: string, id: string) {
    return this.repository.transaction(async client => {
      const grant = await this.repository.grant(client, actor);
      if (!grant) forbidden();
      const current = await this.repository.find(client, id);
      if (!current || (grant !== 'SAFETY_SUPERVISOR' && current.assigned_user_id !== actor)) missing();
      const details = await this.repository.detail(client, id);
      await this.repository.audit(client, actor, 'safety.case_viewed', id);
      return { id, state: current.state, version: current.version, ...details };
    });
  }

  act(actor: string, id: string, action: StaffAction, dto: SafetyCaseActionDto) {
    return this.repository.transaction(async client => {
      const grant = await this.repository.grant(client, actor);
      if (!grant) forbidden();
      const supervisor = grant === 'SAFETY_SUPERVISOR';
      const current = await this.repository.find(client, id);
      if (!current || (!supervisor && current.assigned_user_id && current.assigned_user_id !== actor)) missing();
      const replay = await this.repository.replay(client, id, actor, dto.clientActionId);
      if (replay) {
        if (replay.action !== action || replay.note !== (dto.note || null) ||
            replay.resulting_version !== dto.expectedVersion + 1) conflict('SAFETY_ACTION_ID_CONFLICT');
        return { id, state: replay.action, version: replay.resulting_version };
      }
      if (current.version !== dto.expectedVersion) conflict('SAFETY_CASE_VERSION_CHANGED');
      if (action === 'ACKNOWLEDGED' ? current.state !== 'RECEIVED'
          : action === 'ESCALATED' ? current.state !== 'ACKNOWLEDGED'
          : !['ACKNOWLEDGED','ESCALATED'].includes(current.state)) {
        conflict('SAFETY_CASE_TRANSITION_INVALID');
      }
      if (action === 'RESOLVED' && !supervisor) forbidden();
      if (action !== 'ACKNOWLEDGED' && !dto.note) invalid('Safety action requires a note');
      const updated = await this.repository.update(client, id, actor, action, dto);
      await this.repository.audit(client, actor, `safety.case_${action.toLowerCase()}`, id);
      return updated;
    });
  }
}
