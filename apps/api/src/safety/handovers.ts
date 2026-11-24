import { Injectable } from '@nestjs/common';
import { IsInt, IsUUID, Min } from 'class-validator';
import { DbService } from '../db/db.service.js';
import { conflict, forbidden, missing } from '../common/errors.js';
import { StaffCasesRepository } from './staff-cases.repository.js';
import type { PoolClient } from 'pg';

export class HandoverDto {
  @IsUUID() toUserId!: string;
  @IsUUID() toShiftId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
}

@Injectable()
export class HandoversService {
  constructor(private readonly db: DbService, private readonly cases: StaffCasesRepository) {}

  private async scope(client: PoolClient, actor: string, caseId: string) {
    const grant = await this.cases.grant(client,actor);
    if (!grant) forbidden();
    const current = await this.cases.find(client,caseId);
    if (!current || (grant !== 'SAFETY_SUPERVISOR' && current.assigned_user_id !== actor)) missing();
    if (!current.assigned_user_id || !['ACKNOWLEDGED','ESCALATED'].includes(current.state)) {
      conflict('HANDOVER_CASE_NOT_OPEN');
    }
    return current;
  }

  private present(client: PoolClient, caseId: string, owner: string, user?: string, shift?: string) {
    return client.query(`WITH region AS (
      SELECT n.governorate_id FROM safety_cases c
      LEFT JOIN emergency_events e ON e.id=c.emergency_event_id
      LEFT JOIN safety_aborts ab ON ab.emergency_event_id=e.id
      LEFT JOIN safety_alerts al ON al.id=c.alert_id
      LEFT JOIN safety_sessions ss ON ss.id=coalesce(e.session_id,al.session_id)
      LEFT JOIN request_assignments a ON a.id=coalesce(ss.assignment_id,ab.assignment_id)
      LEFT JOIN nurses n ON n.id=a.nurse_id OR (a.id IS NULL AND n.user_id=e.reporter_user_id)
      WHERE c.id=$4
    )
    SELECT p.user_id,p.shift_id,u.display_name,g.name_ar AS governorate_name
      FROM safety_staff_shift_presence p JOIN safety_staff_shifts s ON s.id=p.shift_id
      JOIN safety_staff_grants sg ON sg.user_id=p.user_id JOIN users u ON u.id=p.user_id
      LEFT JOIN governorates g ON g.id=s.governorate_id
      CROSS JOIN region r
      WHERE (s.governorate_id IS NULL OR s.governorate_id=r.governorate_id) AND p.user_id<>$1 AND ($2::uuid IS NULL OR p.user_id=$2) AND ($3::uuid IS NULL OR p.shift_id=$3)
        AND sg.revoked_at IS NULL AND u.status='ACTIVE' AND u.role IN ('ADMIN','CLINICAL_REVIEWER')
        AND p.user_id IN (s.primary_user_id,s.backup_user_id)
        AND p.checked_out_at IS NULL AND p.heartbeat_at>clock_timestamp()-interval '90 seconds'
        AND s.cancelled_at IS NULL AND s.starts_at<=clock_timestamp() AND s.ends_at>clock_timestamp()
      ORDER BY u.display_name,p.user_id,p.shift_id LIMIT 100`, [owner,user ?? null,shift ?? null,caseId]);
  }

  candidates(actor: string, id: string) {
    return this.db.transaction(async client => {
      const current = await this.scope(client,actor,id);
      return (await this.present(client,id,current.assigned_user_id)).rows;
    });
  }

  inbox(actor: string) {
    return this.db.transaction(async client => {
      if (!await this.cases.grant(client,actor)) forbidden();
      return (await client.query(`SELECT h.id,h.case_id,h.expires_at FROM safety_shift_handovers h
        JOIN safety_cases c ON c.id=h.case_id WHERE h.to_user_id=$1 AND h.state='PENDING'
        AND h.expires_at>now() AND c.version=h.case_version
        AND c.state IN ('ACKNOWLEDGED','ESCALATED')
        ORDER BY h.expires_at,h.id LIMIT 100`, [actor])).rows;
    });
  }

  request(actor: string, id: string, dto: HandoverDto) {
    return this.db.transaction(async client => {
      const current = await this.scope(client,actor,id);
      if (current.version !== dto.expectedVersion) conflict('SAFETY_CASE_VERSION_CHANGED');
      await client.query(`UPDATE safety_shift_handovers SET state='EXPIRED'
        WHERE case_id=$1 AND state='PENDING' AND (expires_at<=clock_timestamp() OR case_version<>$2)`, [id,current.version]);
      const previous = (await client.query(`SELECT id,to_user_id,to_shift_id FROM safety_shift_handovers
        WHERE case_id=$1 AND state='PENDING'`, [id])).rows[0];
      if (previous) {
        if (previous.to_user_id === dto.toUserId && previous.to_shift_id === dto.toShiftId) return { id: previous.id };
        conflict('HANDOVER_ALREADY_PENDING');
      }
      if (!(await this.present(client,id,current.assigned_user_id,dto.toUserId,dto.toShiftId)).rowCount) {
        conflict('HANDOVER_RECIPIENT_NOT_PRESENT');
      }
      const offer = (await client.query(`INSERT INTO safety_shift_handovers
        (case_id,requested_by,from_user_id,to_user_id,to_shift_id,case_version)
        VALUES($1,$2,$3,$4,$5,$6) RETURNING id`, [id,actor,current.assigned_user_id,dto.toUserId,dto.toShiftId,current.version])).rows[0];
      await this.cases.audit(client,actor,'safety.handover_requested',id);
      await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
        VALUES('safety.handover_requested',$1,jsonb_build_object('handoverId',$1::uuid,'recipientUserId',$2::uuid))`,
      [offer.id,dto.toUserId]);
      return offer;
    });
  }

  accept(actor: string, id: string) {
    return this.db.transaction(async client => {
      if (!await this.cases.grant(client,actor)) forbidden();
      const candidate = (await client.query('SELECT case_id FROM safety_shift_handovers WHERE id=$1 AND to_user_id=$2', [id,actor])).rows[0];
      if (!candidate) missing();
      const current = await this.cases.find(client,candidate.case_id);
      const offer = (await client.query(`SELECT *,expires_at>clock_timestamp() AS current_offer
        FROM safety_shift_handovers WHERE id=$1 FOR UPDATE`, [id])).rows[0];
      if (offer.state === 'ACCEPTED') return { caseId: candidate.case_id };
      if (offer.state !== 'PENDING' || !offer.current_offer || current.version !== offer.case_version ||
          current.assigned_user_id !== offer.from_user_id || !['ACKNOWLEDGED','ESCALATED'].includes(current.state)) {
        conflict('HANDOVER_NO_LONGER_CURRENT');
      }
      if (!(await this.present(client,candidate.case_id,offer.from_user_id,actor,offer.to_shift_id)).rowCount) {
        conflict('HANDOVER_RECIPIENT_NOT_PRESENT');
      }
      await client.query(`UPDATE safety_cases SET assigned_user_id=$2,assigned_shift_id=$3,
        version=version+1,updated_at=now() WHERE id=$1`, [candidate.case_id,actor,offer.to_shift_id]);
      await client.query("UPDATE safety_shift_handovers SET state='ACCEPTED',accepted_at=now() WHERE id=$1", [id]);
      await this.cases.audit(client,actor,'safety.handover_accepted',candidate.case_id);
      return { caseId: candidate.case_id };
    });
  }
}
