import { Injectable } from '@nestjs/common';
import { Transform } from 'class-transformer';
import { IsInt, IsString, Length, Max, Min } from 'class-validator';
import type { PoolClient } from 'pg';
import { forbidden, missing } from '../common/errors.js';
import { DbService } from '../db/db.service.js';
import { StaffCasesRepository } from './staff-cases.repository.js';

const trim = ({value}: {value: unknown}) => typeof value === 'string' ? value.trim() : value;

export class RetentionPolicyDto {
  @IsInt() @Min(1) @Max(365) pointDays!: number;
  @IsInt() @Min(1) @Max(365) exportDays!: number;
}
export class LegalHoldDto {
  @Transform(trim) @IsString() @Length(1,240) reason!: string;
  @Transform(trim) @IsString() @Length(1,120) reference!: string;
}
export class ReleaseHoldDto {
  @Transform(trim) @IsString() @Length(1,240) reason!: string;
}

@Injectable()
export class RetentionService {
  constructor(private readonly db: DbService, private readonly staff: StaffCasesRepository) {}

  private async supervisor(client: PoolClient, actor: string) {
    if (await this.staff.grant(client,actor) !== 'SAFETY_SUPERVISOR') forbidden();
  }

  private async lock(client: PoolClient) {
    await client.query("SELECT pg_advisory_xact_lock(hashtext('guardian.evidence.retention'))");
  }

  status(actor: string) {
    return this.db.transaction(async client => {
      await this.supervisor(client,actor);
      return {
        policy:(await client.query(`SELECT id,point_days,export_days,created_at FROM safety_retention_policies
          ORDER BY created_at DESC,id DESC LIMIT 1`)).rows[0] ?? null,
        recentRuns:(await client.query(`SELECT point_count,export_count,ran_at FROM safety_retention_runs
          ORDER BY id DESC LIMIT 20`)).rows,
      };
    });
  }

  configure(actor: string, dto: RetentionPolicyDto) {
    return this.db.transaction(async client => {
      await this.supervisor(client,actor);
      await this.lock(client);
      const policy = (await client.query(`INSERT INTO safety_retention_policies(point_days,export_days,set_by)
        VALUES($1,$2,$3) RETURNING id,point_days,export_days,created_at`,
      [dto.pointDays,dto.exportDays,actor])).rows[0];
      await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
        VALUES($1,'safety.retention_policy_saved','safety_retention_policy',$2)`,[actor,policy.id]);
      return policy;
    });
  }

  holds(actor: string, caseId: string) {
    return this.db.transaction(async client => {
      await this.supervisor(client,actor);
      if (!await this.staff.find(client,caseId)) missing();
      await this.staff.audit(client,actor,'safety.legal_holds_viewed',caseId);
      return (await client.query(`SELECT id,reason,reference,held_by,held_at,released_by,released_at,release_reason
        FROM safety_legal_holds WHERE case_id=$1 ORDER BY held_at,id`,[caseId])).rows;
    });
  }

  hold(actor: string, caseId: string, dto: LegalHoldDto) {
    return this.db.transaction(async client => {
      await this.supervisor(client,actor);
      await this.lock(client);
      if (!await this.staff.find(client,caseId)) missing();
      const hold = (await client.query(`INSERT INTO safety_legal_holds(case_id,reason,reference,held_by)
        VALUES($1,$2,$3,$4) ON CONFLICT(case_id) WHERE released_at IS NULL DO NOTHING
        RETURNING id,held_at`,[caseId,dto.reason,dto.reference,actor])).rows[0];
      if (hold) {
        await this.staff.audit(client,actor,'safety.legal_hold_applied',caseId);
        return hold;
      }
      return (await client.query('SELECT id,held_at FROM safety_legal_holds WHERE case_id=$1 AND released_at IS NULL',[caseId])).rows[0];
    });
  }

  release(actor: string, caseId: string, holdId: string, dto: ReleaseHoldDto) {
    return this.db.transaction(async client => {
      await this.supervisor(client,actor);
      await this.lock(client);
      const changed = (await client.query(`UPDATE safety_legal_holds SET released_at=clock_timestamp(),
        released_by=$3,release_reason=$4 WHERE id=$1 AND case_id=$2 AND released_at IS NULL RETURNING id,released_at`,
      [holdId,caseId,actor,dto.reason])).rows[0];
      if (!changed) missing();
      await this.staff.audit(client,actor,'safety.legal_hold_released',caseId);
      return changed;
    });
  }
}
