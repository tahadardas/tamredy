import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { ContactConsentDto, TrustedContactDto } from './trusted-contact.dto.js';

const summary = 'id,name,phone_e164,relationship,priority,communication,request_location,consent_state,location_allowed,verified_at,updated_at';

@Injectable()
export class TrustedContactsRepository {
  constructor(private readonly db: DbService) {}

  transaction<T>(work: (client: PoolClient) => Promise<T>) {
    return this.db.transaction(work);
  }

  async list(owner: string) {
    return (await this.db.query(`SELECT ${summary} FROM trusted_contacts
      WHERE owner_user_id=$1 AND deleted_at IS NULL ORDER BY priority`, [owner])).rows;
  }

  async lock(client: PoolClient, id: string, owner?: string) {
    return (await client.query(`SELECT * FROM trusted_contacts WHERE id=$1 AND deleted_at IS NULL
      AND ($2::uuid IS NULL OR owner_user_id=$2) FOR UPDATE`, [id, owner ?? null])).rows[0];
  }

  async save(client: PoolClient, owner: string, dto: TrustedContactDto, id?: string, reset = false) {
    const values = [owner,dto.name,dto.phone,dto.relationship,dto.priority,dto.communication,dto.requestLocation];
    const row = id
      ? await client.query(`UPDATE trusted_contacts SET name=$2,phone_e164=$3,relationship=$4,priority=$5,
        communication=$6,request_location=$7,updated_at=now(),
        consent_state=CASE WHEN $9 THEN 'PENDING' ELSE consent_state END,
        verified_at=CASE WHEN $9 THEN NULL ELSE verified_at END,
        location_allowed=CASE WHEN $9 THEN false ELSE location_allowed END
        WHERE owner_user_id=$1 AND id=$8 AND deleted_at IS NULL RETURNING ${summary}`, [...values,id,reset])
      : await client.query(`INSERT INTO trusted_contacts(owner_user_id,name,phone_e164,relationship,priority,communication,request_location)
        VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING ${summary}`, values);
    return row.rows[0];
  }

  async remove(client: PoolClient, owner: string, id: string) {
    await client.query(`UPDATE trusted_contacts SET deleted_at=now(),updated_at=now(),consent_state='REVOKED',
      verified_at=NULL,location_allowed=false WHERE owner_user_id=$1 AND id=$2`, [owner,id]);
  }

  async supervisor(client: PoolClient, actor: string) {
    const direct = (await client.query(`SELECT 1 FROM safety_staff_grants
      WHERE user_id=$1 AND permission='SAFETY_SUPERVISOR' AND revoked_at IS NULL FOR SHARE`, [actor])).rowCount;
    if (direct) return direct;
    const user = (await client.query(`SELECT role FROM users WHERE id=$1 AND status='ACTIVE'`, [actor])).rows[0];
    return user?.role === 'ADMIN' ? 1 : 0;
  }

  async applyConsent(client: PoolClient, id: string, dto: ContactConsentDto) {
    return (await client.query(`UPDATE trusted_contacts SET consent_state=$2,location_allowed=$3,
      verified_at=CASE WHEN $2='ACCEPTED' THEN now() END,updated_at=now() WHERE id=$1 RETURNING ${summary}`,
    [id,dto.decision,dto.allowsLocation])).rows[0];
  }

  async record(client: PoolClient, contact: string, actor: string, decision: string, location = false, reference?: string) {
    await client.query(`INSERT INTO trusted_contact_consents(contact_id,actor_user_id,decision,allows_location,verification_reference)
      VALUES($1,$2,$3,$4,$5)`, [contact,actor,decision,location,reference ?? null]);
    await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
      VALUES($1,$2,'trusted_contact',$3)`, [actor,`trusted_contact.${decision.toLowerCase()}`,contact]);
  }
}
