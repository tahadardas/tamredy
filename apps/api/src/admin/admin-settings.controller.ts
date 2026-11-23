import { BadRequestException, Body, Controller, Delete, Get, Param, Patch, Put, Query, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';

const bad = (code: string): never => { throw new BadRequestException({ code }); };
const num = (v: unknown, min: number, max: number, code: string) => { const x = Number(v); if (!Number.isFinite(x) || x < min || x > max) bad(code); return x; };
const str = (v: unknown, max: number, code: string) => { if (typeof v !== 'string' || v.length > max) bad(code); return v as string; };

/** Each setting group validates its own shape; unknown keys are dropped so junk can never be stored. */
const VALIDATORS: Record<string, (v: any) => unknown> = {
  company: v => ({ name: str(v?.name ?? '', 80, 'BAD_NAME'), phone: str(v?.phone ?? '', 30, 'BAD_PHONE'), email: str(v?.email ?? '', 120, 'BAD_EMAIL'), address: str(v?.address ?? '', 200, 'BAD_ADDRESS'), currencyLabel: str(v?.currencyLabel ?? 'ل.س', 12, 'BAD_CURRENCY') }),
  dispatch: v => {
    if (!Array.isArray(v?.waves) || v.waves.length < 1 || v.waves.length > 5) bad('BAD_WAVES');
    let prev = 0;
    return {
      openEnabled: v.openEnabled === true,
      pauseAfterTravelCancellation: v.pauseAfterTravelCancellation === true,
      offerDurationSeconds: Math.trunc(num(v.offerDurationSeconds ?? 60, 15, 300, 'BAD_OFFER_DURATION')),
      radiusMeters: Math.trunc(num(v.radiusMeters ?? 10000, 500, 50000, 'BAD_RADIUS')),
      maxHeartbeatAgeSeconds: Math.trunc(num(v.maxHeartbeatAgeSeconds ?? 60, 15, 300, 'BAD_HEARTBEAT_AGE')),
      maxLocationAgeSeconds: Math.trunc(num(v.maxLocationAgeSeconds ?? 120, 15, 600, 'BAD_LOCATION_AGE')),
      maxLocationAccuracyMeters: Math.trunc(num(v.maxLocationAccuracyMeters ?? 100, 10, 5000, 'BAD_LOCATION_ACCURACY')),
      waves: v.waves.map((w: any) => {
      const radiusM = num(w?.radiusM, 500, 50_000, 'BAD_RADIUS');
      if (radiusM <= prev) bad('WAVES_MUST_GROW'); prev = radiusM;
      return { radiusM, seconds: Math.trunc(num(w?.seconds, 5, 120, 'BAD_SECONDS')) };
    }) };
  },
  orders: v => ({ accepting: v?.accepting === true, pausedMessage: str(v?.pausedMessage ?? '', 200, 'BAD_MESSAGE') }),
  registration: v => ({ patients: v?.patients !== false, nurses: v?.nurses !== false }),
  security: v => ({ idleMinutes: Math.trunc(num(v?.idleMinutes, 5, 240, 'BAD_IDLE')), passwordMinLength: Math.trunc(num(v?.passwordMinLength, 8, 64, 'BAD_PWLEN')), defaultPassword: (() => { const p = str(v?.defaultPassword ?? '123456', 64, 'BAD_DEFAULT_PW'); if (p.length < 6) bad('BAD_DEFAULT_PW'); return p; })() }),
};

class UpdateAdminDto {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) displayName?: string;
  @IsOptional() @Matches(/^\+[1-9]\d{7,14}$/) phone?: string;
  @IsOptional() @IsIn(['ADMIN', 'CLINICAL_REVIEWER']) role?: 'ADMIN' | 'CLINICAL_REVIEWER';
}

@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminSettingsController {
  constructor(private readonly db: DbService) {}

  @Get('system-settings') async all(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const rows = (await this.db.query('SELECT key,value,updated_at FROM app_settings')).rows;
    return { settings: Object.fromEntries(rows.map((x: any) => [x.key, x.value])), updatedAt: Object.fromEntries(rows.map((x: any) => [x.key, x.updated_at])) };
  }

  @Put('system-settings/:key') async save(@Request() r: AuthRequest, @Param('key') key: string, @Body() body: any) {
    requireRole(r.user!, 'ADMIN');
    const check = VALIDATORS[key];
    if (!check) missing();
    const value = check(body);
    return this.db.transaction(async c => {
      await c.query(`INSERT INTO app_settings(key,value,updated_by) VALUES($1,$2::jsonb,$3) ON CONFLICT(key) DO UPDATE SET value=$2::jsonb,updated_at=now(),updated_by=$3`, [key, JSON.stringify(value), r.user!.id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'settings.changed','setting',gen_random_uuid(),$2::jsonb)`, [r.user!.id, JSON.stringify({ key, value })]);
      return { key, value };
    });
  }

  @Get('audit') async audit(@Request() r: AuthRequest, @Query('action') action?: string, @Query('limit') limit?: string) {
    requireRole(r.user!, 'ADMIN');
    const rows = (await this.db.query(`SELECT a.id,a.action,a.target_type,a.target_id,a.detail,a.occurred_at,coalesce(u.display_name,u.phone_e164) AS actor
      FROM audit_log a JOIN users u ON u.id=a.actor_user_id WHERE ($1::text IS NULL OR a.action LIKE $1||'%') ORDER BY a.id DESC LIMIT $2`,
      [action?.slice(0, 40) || null, Math.min(Math.max(Number(limit) || 100, 1), 300)])).rows;
    return { items: rows };
  }

  // ---- admin / reviewer accounts ----
  @Get('staff') async staff(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return { items: (await this.db.query(`SELECT id,display_name,phone_e164,role,status,created_at FROM users WHERE role IN ('ADMIN','CLINICAL_REVIEWER') AND status<>'DELETED' ORDER BY created_at`)).rows };
  }

  @Patch('staff/:id') async updateStaff(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: UpdateAdminDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const u = (await c.query(`SELECT id,role FROM users WHERE id=$1 AND role IN ('ADMIN','CLINICAL_REVIEWER') AND status<>'DELETED' FOR UPDATE`, [id])).rows[0];
      if (!u) missing();
      if (d.role && d.role !== u.role && id === r.user!.id) conflict('CANNOT_CHANGE_OWN_ROLE');
      if (d.phone && (await c.query('SELECT 1 FROM users WHERE phone_e164=$1 AND id<>$2', [d.phone, id])).rowCount) conflict('PHONE_ALREADY_REGISTERED');
      await c.query('UPDATE users SET display_name=coalesce($2,display_name),phone_e164=coalesce($3,phone_e164),role=coalesce($4,role) WHERE id=$1', [id, d.displayName ?? null, d.phone ?? null, d.role ?? null]);
      if (d.role && d.role !== u.role) await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'staff.updated','user',$2,$3::jsonb)`, [r.user!.id, id, JSON.stringify({ fields: Object.keys(d) })]);
      return { id };
    });
  }

  @Delete('staff/:id') async deleteStaff(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'ADMIN');
    if (id === r.user!.id) conflict('CANNOT_DELETE_SELF');
    return this.db.transaction(async c => {
      const u = (await c.query(`SELECT id,role FROM users WHERE id=$1 AND role IN ('ADMIN','CLINICAL_REVIEWER') AND status<>'DELETED' FOR UPDATE`, [id])).rows[0];
      if (!u) missing();
      if (u.role === 'ADMIN' && Number((await c.query(`SELECT count(*)::int AS n FROM users WHERE role='ADMIN' AND status='ACTIVE'`)).rows[0].n) <= 1) conflict('LAST_ADMIN');
      await c.query(`UPDATE users SET status='DELETED',phone_e164='deleted-'||id::text WHERE id=$1`, [id]);
      await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'staff.deleted','user',$2,'{}'::jsonb)`, [r.user!.id, id]);
      return { id, deleted: true };
    });
  }
}
