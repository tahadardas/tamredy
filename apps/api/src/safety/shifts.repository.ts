import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { SafetyShiftDto } from './shifts.dto.js';

const coverageColumns = `
  p.display_name AS primary_name, b.display_name AS backup_name, g.name_ar AS governorate_name,
  coalesce(pp.checked_out_at IS NULL AND pp.heartbeat_at > now()-interval '90 seconds'
    AND pg.revoked_at IS NULL AND p.status='ACTIVE',false) AS primary_present,
  coalesce(bp.checked_out_at IS NULL AND bp.heartbeat_at > now()-interval '90 seconds'
    AND bg.revoked_at IS NULL AND b.status='ACTIVE',false) AS backup_present`;
const coverageJoins = `
  JOIN users p ON p.id=s.primary_user_id JOIN users b ON b.id=s.backup_user_id
  JOIN safety_staff_grants pg ON pg.user_id=p.id JOIN safety_staff_grants bg ON bg.user_id=b.id
  LEFT JOIN governorates g ON g.id=s.governorate_id
  LEFT JOIN safety_staff_shift_presence pp ON pp.shift_id=s.id AND pp.user_id=p.id
  LEFT JOIN safety_staff_shift_presence bp ON bp.shift_id=s.id AND bp.user_id=b.id`;

@Injectable()
export class ShiftsRepository {
  constructor(private readonly db: DbService) {}

  transaction<T>(work: (client: PoolClient) => Promise<T>) { return this.db.transaction(work); }

  async coverage(client: PoolClient) {
    return (await client.query(`SELECT s.id,s.shift_kind,s.starts_at,s.ends_at,${coverageColumns}
      FROM safety_staff_shifts s ${coverageJoins}
      WHERE s.cancelled_at IS NULL AND s.starts_at<=now() AND s.ends_at>now()
      ORDER BY g.name_ar NULLS FIRST,s.id`)).rows;
  }

  async list(client: PoolClient, actor: string, supervisor: boolean) {
    return (await client.query(`SELECT s.*,${coverageColumns},
      ($1 IN (s.primary_user_id,s.backup_user_id) AND s.starts_at<=now() AND s.ends_at>now()) AS can_check_in
      FROM safety_staff_shifts s ${coverageJoins}
      WHERE s.cancelled_at IS NULL AND s.ends_at>now()-interval '7 days'
        AND ($2 OR $1 IN (s.primary_user_id,s.backup_user_id))
      ORDER BY s.starts_at,s.id LIMIT 200`, [actor,supervisor])).rows;
  }

  async options(client: PoolClient) {
    const staff = (await client.query(`SELECT u.id,u.display_name,g.permission FROM safety_staff_grants g
      JOIN users u ON u.id=g.user_id WHERE g.revoked_at IS NULL AND u.status='ACTIVE' AND u.role IN ('ADMIN','CLINICAL_REVIEWER')
      ORDER BY u.display_name,u.id LIMIT 200`)).rows;
    const regions = (await client.query('SELECT id,name_ar FROM governorates WHERE active ORDER BY sort_order,name_ar')).rows;
    return { staff, regions };
  }

  async eligible(client: PoolClient, people: string[]) {
    return await client.query(`SELECT u.id FROM users u JOIN safety_staff_grants g ON g.user_id=u.id
      WHERE u.id=ANY($1::uuid[]) AND u.status='ACTIVE' AND u.role IN ('ADMIN','CLINICAL_REVIEWER') AND g.revoked_at IS NULL FOR SHARE OF u,g`, [people]);
  }

  async overlaps(client: PoolClient, dto: SafetyShiftDto, id?: string) {
    // Serialize roster writes so two supervisors cannot create overlapping shifts.
    await client.query("SELECT pg_advisory_xact_lock(hashtext('guardian.shift.roster'))");
    return (await client.query(`SELECT id FROM safety_staff_shifts WHERE cancelled_at IS NULL
      AND starts_at<$3 AND ends_at>$2
      AND (governorate_id IS NOT DISTINCT FROM $1::uuid OR primary_user_id=ANY($5::uuid[]) OR backup_user_id=ANY($5::uuid[]))
      AND ($4::uuid IS NULL OR id<>$4) LIMIT 1`,
    [dto.governorateId ?? null,dto.startsAt,dto.endsAt,id ?? null,[dto.primaryUserId,dto.backupUserId]])).rows[0];
  }

  async write(client: PoolClient, actor: string, dto: SafetyShiftDto, id?: string) {
    const values = [dto.governorateId ?? null,dto.shiftKind,dto.primaryUserId,dto.backupUserId,
      dto.startsAt,dto.endsAt,actor];
    return (id
      ? await client.query(`UPDATE safety_staff_shifts SET governorate_id=$1,shift_kind=$2,primary_user_id=$3,
        backup_user_id=$4,starts_at=$5,ends_at=$6,updated_at=now()
        WHERE id=$7 AND cancelled_at IS NULL AND starts_at>now() RETURNING *`, [...values.slice(0,6),id])
      : await client.query(`INSERT INTO safety_staff_shifts
        (governorate_id,shift_kind,primary_user_id,backup_user_id,starts_at,ends_at,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *`, values)).rows[0];
  }

  async lockCurrent(client: PoolClient, actor: string, shift: string) {
    return (await client.query(`SELECT id FROM safety_staff_shifts WHERE id=$1
      AND $2 IN (primary_user_id,backup_user_id) AND cancelled_at IS NULL
      AND starts_at<=clock_timestamp() AND ends_at>clock_timestamp() FOR UPDATE`, [shift,actor])).rows[0];
  }

  async checkin(client: PoolClient, actor: string, shift: string) {
    return (await client.query(`INSERT INTO safety_staff_shift_presence(shift_id,user_id)
      VALUES($1,$2) ON CONFLICT(shift_id,user_id) DO UPDATE
      SET checked_in_at=CASE WHEN safety_staff_shift_presence.checked_out_at IS NULL
        THEN safety_staff_shift_presence.checked_in_at ELSE statement_timestamp() END,
        heartbeat_at=statement_timestamp(),checked_out_at=NULL RETURNING *`, [shift,actor])).rows[0];
  }

  async heartbeat(client: PoolClient, actor: string, shift: string, leave: boolean) {
    return (await client.query(`UPDATE safety_staff_shift_presence SET heartbeat_at=statement_timestamp(),
      checked_out_at=CASE WHEN $3 THEN statement_timestamp() END
      WHERE shift_id=$1 AND user_id=$2 AND checked_out_at IS NULL RETURNING *`, [shift,actor,leave])).rows[0];
  }

  async cancel(client: PoolClient, id: string) {
    return (await client.query(`UPDATE safety_staff_shifts SET cancelled_at=now(),updated_at=now()
      WHERE id=$1 AND cancelled_at IS NULL AND starts_at>now() RETURNING id`, [id])).rows[0];
  }

  async audit(client:PoolClient, actor:string, shift:string, action:string) {
    await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
      VALUES($1,$2,'safety_shift',$3)`, [actor,action,shift]);
  }
}
