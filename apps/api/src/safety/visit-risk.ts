import { Injectable } from '@nestjs/common';
import { IsIn, IsISO8601, IsString, IsUUID, Length } from 'class-validator';
import { DbService } from '../db/db.service.js';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import { StaffCasesRepository } from './staff-cases.repository.js';
import type { PoolClient } from 'pg';

export class VisitRiskDto {
  @IsIn(['CLEAR','HOLD','REQUIRE_COMPANION']) decision!: string;
  @IsIn(['VERIFIED_INCIDENT','DOCUMENTED_THREAT','INFORMATION_MISMATCH','SOLO_WORK','REASSESSMENT']) basis!: string;
  @IsString() @Length(1,120) reference!: string;
  @IsISO8601({strict:true}) effectiveUntil!: string;
}
export class VisitCompanionDto {
  @IsUUID() nurseId!: string;
  @IsUUID() companionId!: string;
}
export class ConfirmVisitCompanionDto {
  @IsUUID() nurseId!: string;
}

@Injectable()
export class VisitRiskService {
  constructor(private readonly db: DbService, private readonly staff: StaffCasesRepository) {}

  private async requireSupervisor(client: PoolClient, actor: string, request: string) {
    if (await this.staff.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
    const row = (await client.query('SELECT status FROM care_requests WHERE id=$1 FOR UPDATE',[request])).rows[0];
    if (!row) missing();
    if (!['OFFERING','SCHEDULED'].includes(row.status)) conflict('VISIT_REVIEW_NOT_EDITABLE');
  }

  assess(actor: string, request: string, dto: VisitRiskDto) {
    return this.db.transaction(async client => {
      await this.requireSupervisor(client,actor,request);
      const expiry = Date.parse(dto.effectiveUntil) - Date.now();
      if (!Number.isFinite(expiry) || expiry<=0 || expiry>7*86_400_000 || !dto.reference.trim()) invalid('Invalid safety review');
      const row = (await client.query(`INSERT INTO safety_visit_reviews(request_id,assessed_by,decision,basis,reference,effective_until)
        VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
      [request,actor,dto.decision,dto.basis,dto.reference.trim(),dto.effectiveUntil])).rows[0];
      await this.staff.audit(client,actor,'safety.visit_review_recorded',row.id);
      return row;
    });
  }

  nominate(actor: string, request: string, dto: VisitCompanionDto) {
    return this.db.transaction(async client => {
      await this.requireSupervisor(client,actor,request);
      if (dto.nurseId === dto.companionId) invalid('The companion must be a different nurse');
      const eligible = await client.query(`SELECT n.id FROM nurses n JOIN users u ON u.id=n.user_id
        WHERE n.id=ANY($1::uuid[]) AND n.verified AND u.status='ACTIVE'
        AND EXISTS (SELECT 1 FROM nurse_credentials k WHERE k.nurse_id=n.id AND k.approved AND k.expires_at>now())`,
      [[dto.nurseId,dto.companionId]]);
      if (eligible.rowCount !== 2) invalid('Both nurses require verified credentials');
      await client.query(`INSERT INTO safety_visit_companions(request_id,nurse_id,companion_id,nominated_by)
        VALUES($1,$2,$3,$4) ON CONFLICT(request_id,nurse_id) DO UPDATE SET companion_id=EXCLUDED.companion_id,
        nominated_by=EXCLUDED.nominated_by,nominated_at=clock_timestamp(),confirmed_at=NULL`,
      [request,dto.nurseId,dto.companionId,actor]);
      await this.staff.audit(client,actor,'safety.companion_nominated',request);
      return { ok: true };
    });
  }

  async pending(actor: string) {
    return (await this.db.query(`SELECT c.request_id,c.nurse_id,c.nominated_at,s.title_ar AS service_title
      FROM safety_visit_companions c JOIN nurses n ON n.id=c.companion_id
      JOIN care_requests r ON r.id=c.request_id JOIN services s ON s.id=r.service_id WHERE n.user_id=$1 AND c.confirmed_at IS NULL
      AND r.status IN ('SCHEDULED','OFFERING') ORDER BY c.nominated_at DESC LIMIT 30`,[actor])).rows;
  }

  confirm(actor: string, request: string, nurse: string) {
    return this.db.transaction(async client => {
      const target = (await client.query('SELECT status FROM care_requests WHERE id=$1 FOR UPDATE',[request])).rows[0];
      if (!target || !['SCHEDULED','OFFERING'].includes(target.status)) missing();
      const row = await client.query(`UPDATE safety_visit_companions c SET confirmed_at=coalesce(c.confirmed_at,now())
        FROM nurses n WHERE c.request_id=$1 AND c.nurse_id=$2 AND n.id=c.companion_id AND n.user_id=$3 RETURNING c.request_id`,
      [request,nurse,actor]);
      if (!row.rowCount) missing();
      await this.staff.audit(client,actor,'safety.companion_confirmed',request);
      return { ok: true };
    });
  }
}
