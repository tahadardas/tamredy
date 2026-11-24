import { Injectable } from '@nestjs/common';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import type { ContactConsentDto, TrustedContactDto } from './trusted-contact.dto.js';
import { TrustedContactsRepository } from './trusted-contacts.repository.js';

@Injectable()
export class TrustedContactsService {
  constructor(private readonly repository: TrustedContactsRepository) {}

  list(owner: string) {
    return this.repository.list(owner);
  }

  async save(owner: string, dto: TrustedContactDto, id?: string) {
    try {
      return await this.repository.transaction(async client => {
        const old = id ? await this.repository.lock(client, id, owner) : null;
        if (id && !old) missing();
        const reset = old != null && (old.phone_e164 !== dto.phone ||
          old.request_location !== dto.requestLocation || old.communication !== dto.communication);
        const contact = await this.repository.save(client, owner, dto, id, reset);
        if (reset) await this.repository.record(client, contact.id, owner, 'RESET');
        return contact;
      });
    } catch (error) {
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
        conflict('TRUSTED_CONTACT_PHONE_OR_PRIORITY_IN_USE');
      }
      throw error;
    }
  }

  remove(owner: string, id: string) {
    return this.repository.transaction(async client => {
      if (!await this.repository.lock(client,id,owner)) missing();
      await this.repository.remove(client,owner,id);
      await this.repository.record(client,id,owner,'REVOKED');
      return { ok: true };
    });
  }

  consent(actor: string, id: string, dto: ContactConsentDto) {
    return this.repository.transaction(async client => {
      if (!await this.repository.supervisor(client,actor)) forbidden();
      const contact = await this.repository.lock(client,id);
      if (!contact) missing();
      if (contact.phone_e164 !== dto.verifiedPhone) conflict('TRUSTED_CONTACT_PHONE_CHANGED');
      if (dto.allowsLocation && (dto.decision !== 'ACCEPTED' || !contact.request_location)) {
        invalid('Location consent must match the contact decision and requested scope');
      }
      const updated = await this.repository.applyConsent(client,id,dto);
      await this.repository.record(client,id,actor,dto.decision,dto.allowsLocation,dto.verificationReference);
      return updated;
    });
  }
}
