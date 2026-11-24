import { Injectable } from '@nestjs/common';
import { IsBoolean, IsIn, IsOptional, IsUUID, Matches } from 'class-validator';
import { DbService } from '../db/db.service.js';
import { forbidden, invalid, missing } from '../common/errors.js';
import { StaffCasesRepository } from './staff-cases.repository.js';

const enabled = () => process.env.GUARDIAN_NIGHT_POLICY_ENABLED === 'true';
const hhmm = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;

export class NightPolicyDto {
  @IsOptional() @IsUUID() governorateId?: string;
  @IsOptional() @IsUUID() areaId?: string;
  @IsOptional() @IsUUID() serviceId?: string;
  @IsIn(['ALLOW','RESTRICT','REQUIRE_COVERAGE','REQUIRE_OPT_IN_AND_COVERAGE']) mode!: string;
  @Matches(hhmm) startsAt!: string;
  @Matches(hhmm) endsAt!: string;
}

export class NightPreferenceDto {
  @IsBoolean() optedIn!: boolean;
}

@Injectable()
export class NightPolicyService {
  constructor(private readonly db: DbService, private readonly staff: StaffCasesRepository) {}

  rules(actor: string) {
    return this.db.transaction(async c => {
      if (await this.staff.grant(c,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      const rules = (await c.query(`SELECT DISTINCT ON (governorate_id,area_id,service_id)
        id,governorate_id,area_id,service_id,mode,starts_at,ends_at,created_at
        FROM guardian_night_rules ORDER BY governorate_id,area_id,service_id,created_at DESC,id DESC LIMIT 200`)).rows;
      const regions = (await c.query('SELECT id,name_ar FROM governorates WHERE active ORDER BY name_ar')).rows;
      const areas = (await c.query('SELECT id,governorate_id,name_ar FROM areas WHERE active ORDER BY name_ar')).rows;
      const services = (await c.query('SELECT id,title_ar FROM services WHERE active ORDER BY title_ar')).rows;
      return { enabled: enabled(), rules, regions, areas, services };
    });
  }

  publish(actor: string, dto: NightPolicyDto) {
    return this.db.transaction(async c => {
      if (await this.staff.grant(c,actor) !== 'SAFETY_SUPERVISOR') forbidden();
      if (dto.startsAt === dto.endsAt || (dto.areaId && !dto.governorateId)) invalid('Invalid policy window or scope');
      if (dto.areaId && !(await c.query('SELECT 1 FROM areas WHERE id=$1 AND governorate_id=$2 AND active',
        [dto.areaId,dto.governorateId])).rowCount) invalid('Area must belong to the governorate');
      if (dto.governorateId && !(await c.query('SELECT 1 FROM governorates WHERE id=$1 AND active',[dto.governorateId])).rowCount) missing();
      if (dto.serviceId && !(await c.query('SELECT 1 FROM services WHERE id=$1 AND active',[dto.serviceId])).rowCount) missing();
      const rule = (await c.query(`INSERT INTO guardian_night_rules(governorate_id,area_id,service_id,mode,starts_at,ends_at,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
      [dto.governorateId ?? null,dto.areaId ?? null,dto.serviceId ?? null,dto.mode,dto.startsAt,dto.endsAt,actor])).rows[0];
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
        VALUES($1,'safety.night_policy_published','guardian_night_rule',$2)`, [actor,rule.id]);
      return rule;
    });
  }

  async preference(actor: string) {
    const row = (await this.db.query(`SELECT p.opted_in FROM nurses n
      LEFT JOIN nurse_night_preferences p ON p.nurse_id=n.id WHERE n.user_id=$1`, [actor])).rows[0];
    if (!row) missing();
    return { enabled: enabled(), optedIn: row.opted_in ?? false };
  }

  preferenceUpdate(actor: string, dto: NightPreferenceDto) {
    return this.db.transaction(async c => {
      const nurse = (await c.query('SELECT id FROM nurses WHERE user_id=$1 FOR UPDATE',[actor])).rows[0];
      if (!nurse) missing();
      await c.query(`INSERT INTO nurse_night_preferences(nurse_id,opted_in) VALUES($1,$2)
        ON CONFLICT(nurse_id) DO UPDATE SET opted_in=EXCLUDED.opted_in,recorded_at=now()`,[nurse.id,dto.optedIn]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
        VALUES($1,$2,'nurse',$3)`,[actor,dto.optedIn ? 'safety.night_opted_in' : 'safety.night_opted_out',nurse.id]);
      return { enabled: enabled(), optedIn: dto.optedIn };
    });
  }
}
