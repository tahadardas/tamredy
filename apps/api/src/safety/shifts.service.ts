import { Injectable } from '@nestjs/common';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import { ShiftsRepository } from './shifts.repository.js';
import { StaffCasesRepository } from './staff-cases.repository.js';
import type { SafetyShiftDto } from './shifts.dto.js';

type PresenceAction = 'checkin' | 'heartbeat' | 'checkout';

@Injectable()
export class ShiftsService {
  constructor(private readonly shifts: ShiftsRepository, private readonly grants: StaffCasesRepository) {}

  list(actor: string) {
    return this.shifts.transaction(async client => {
      const grant = await this.grants.grant(client,actor);
      if (!grant) forbidden();
      const supervisor = grant === 'SAFETY_SUPERVISOR';
      const shifts = await this.shifts.list(client,actor,supervisor);
      return { shifts, ...(supervisor ? await this.shifts.options(client) : {}) };
    });
  }

  save(actor: string, dto: SafetyShiftDto, id?: string) {
    return this.shifts.transaction(async client => {
      if (await this.grants.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      const start = Date.parse(dto.startsAt);
      const end = Date.parse(dto.endsAt);
      if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start ||
          end-start > 86_400_000 || end <= Date.now()) invalid('Invalid shift window');
      if (dto.primaryUserId === dto.backupUserId) invalid('Primary and backup must be different');
      if ((await this.shifts.eligible(client,[dto.primaryUserId,dto.backupUserId])).rowCount !== 2) {
        invalid('Both assigned staff need an active safety grant');
      }
      if (await this.shifts.overlaps(client,dto,id)) conflict('SAFETY_SHIFT_OVERLAP');
      const shift = await this.shifts.write(client,actor,dto,id);
      if (!shift) conflict('SAFETY_SHIFT_NOT_EDITABLE');
      await this.shifts.audit(client,actor,shift.id,id ? 'shift.updated' : 'shift.created');
      return shift;
    });
  }

  cancel(actor: string, id: string) {
    return this.shifts.transaction(async client => {
      if (await this.grants.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      if (!await this.shifts.cancel(client,id)) conflict('SAFETY_SHIFT_NOT_EDITABLE');
      await this.shifts.audit(client,actor,id,'shift.cancelled');
      return { ok: true };
    });
  }

  presence(actor: string, id: string, action: PresenceAction) {
    return this.shifts.transaction(async client => {
      if (!await this.grants.grant(client,actor)) forbidden();
      if (!await this.shifts.lockCurrent(client,actor,id)) missing();
      const presence = action === 'checkin'
        ? await this.shifts.checkin(client,actor,id)
        : await this.shifts.heartbeat(client,actor,id,action === 'checkout');
      if (!presence) conflict('SAFETY_SHIFT_CHECKIN_REQUIRED');
      if (action !== 'heartbeat') await this.shifts.audit(client,actor,id,`shift.${action}`);
      return presence;
    });
  }
}
