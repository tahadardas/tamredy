import { Injectable } from '@nestjs/common';
import { forbidden, invalid, missing } from '../common/errors.js';
import { DirectoryRepository } from './directory.repository.js';
import { StaffCasesRepository } from './staff-cases.repository.js';
import type { DirectoryEntryDto } from './directory.dto.js';

@Injectable()
export class DirectoryService {
  constructor(private readonly repository: DirectoryRepository, private readonly grants: StaffCasesRepository) {}

  visible() { return this.repository.visible(); }

  list(actor: string) {
    return this.repository.transaction(async client => {
      if (await this.grants.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      return this.repository.list(client);
    });
  }

  save(actor: string, dto: DirectoryEntryDto, id?: string) {
    return this.repository.transaction(async client => {
      if (await this.grants.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      if (dto.area && !dto.governorate) invalid('Governorate is required with an area');
      const row = await this.repository.save(client,actor,dto,id);
      if (!row) missing();
      await this.repository.audit(client,actor,row.id,dto.publishVerified ? 'directory.verified' : 'directory.draft_saved');
      return row;
    });
  }

  deactivate(actor: string, id: string) {
    return this.repository.transaction(async client => {
      if (await this.grants.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      if (!await this.repository.deactivate(client,id)) missing();
      await this.repository.audit(client,actor,id,'directory.deactivated');
      return { ok: true };
    });
  }
}
