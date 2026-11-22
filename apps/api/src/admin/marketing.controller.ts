import { BadRequestException, Body, Controller, Get, Param, Post, Put, Query, Request, UseGuards } from '@nestjs/common';
import { IsBoolean, IsIn, IsInt, IsObject, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';

const KEYS = ['offpeak', 'loyalty', 'packs', 'winback', 'badge', 'broadcasts', 'alarm'] as const;
const HHMM = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const bad = (code: string): never => { throw new BadRequestException({ code }); };
const num = (v: unknown, min: number, max: number, code: string) => { const n = Number(v); return Number.isFinite(n) && n >= min && n <= max ? n : bad(code); };

/** Validates and normalises each feature's configuration (never trust the client). */
export function sanitizeConfig(key: string, c: any): Record<string, unknown> {
  if (c == null || typeof c !== 'object') return bad('CONFIG_REQUIRED');
  switch (key) {
    case 'offpeak':
      if (!HHMM.test(c.start) || !HHMM.test(c.end)) bad('INVALID_TIME');
      if (!Array.isArray(c.days) || !c.days.length || c.days.some((d: unknown) => !Number.isInteger(d) || (d as number) < 0 || (d as number) > 6)) bad('INVALID_DAYS');
      return { percent: num(c.percent, 1, 100, 'INVALID_PERCENT'), days: [...new Set(c.days.map(Number))], start: c.start, end: c.end, maxDiscount: c.maxDiscount ? num(c.maxDiscount, 1, 1e9, 'INVALID_MAX') : null };
    case 'loyalty':
      return { everyN: num(c.everyN, 2, 100, 'INVALID_EVERY_N'), percent: num(c.percent, 1, 100, 'INVALID_PERCENT'), maxDiscount: c.maxDiscount ? num(c.maxDiscount, 1, 1e9, 'INVALID_MAX') : null };
    case 'packs': {
      if (!Array.isArray(c.templates) || c.templates.length > 20) bad('INVALID_TEMPLATES');
      return { templates: c.templates.map((t: any) => ({ name: String(t.name ?? '').slice(0, 60) || bad('INVALID_NAME'), visits: num(t.visits, 1, 100, 'INVALID_VISITS'), percent: num(t.percent, 1, 100, 'INVALID_PERCENT'), validDays: num(t.validDays, 1, 730, 'INVALID_DAYS') })) };
    }
    case 'winback':
      return { inactiveDays: num(c.inactiveDays, 7, 365, 'INVALID_DAYS'), percent: num(c.percent, 1, 100, 'INVALID_PERCENT'), validDays: num(c.validDays, 1, 90, 'INVALID_DAYS'),
        maxDiscount: c.maxDiscount ? num(c.maxDiscount, 1, 1e9, 'INVALID_MAX') : null, maxPerRun: num(c.maxPerRun, 1, 5000, 'INVALID_MAX_PER_RUN') };
    case 'badge':
      return { minReputation: num(c.minReputation, 1, 5, 'INVALID_REPUTATION'), minReviews: num(c.minReviews, 0, 10000, 'INVALID_REVIEWS') };
    default:
      return {};
  }
}

class FeatureDto { @IsOptional() @IsBoolean() enabled?: boolean; @IsOptional() @IsObject() config?: Record<string, unknown>; }
class GrantDto {
  @Matches(/^\+[1-9]\d{7,14}$/) phone!: string;
  @IsString() @MinLength(2) @MaxLength(60) name!: string;
  @IsInt() @Min(1) @Max(100) visits!: number;
  @IsInt() @Min(1) @Max(100) percent!: number;
  @IsInt() @Min(1) @Max(730) validDays!: number;
}
class BroadcastDto {
  @IsIn(['ALL_PATIENTS', 'ALL_NURSES', 'AVAILABLE_NURSES']) audience!: 'ALL_PATIENTS' | 'ALL_NURSES' | 'AVAILABLE_NURSES';
  @IsString() @MinLength(2) @MaxLength(80) title!: string;
  @IsString() @MinLength(2) @MaxLength(300) body!: string;
  @IsOptional() @IsString() @MaxLength(40) promoCode?: string;
}

/** Audience = users with at least one registered device. Patients must have opted in to marketing messages. */
export const AUDIENCE_SQL: Record<string, string> = {
  ALL_PATIENTS: `u.role='PATIENT' AND u.status='ACTIVE' AND u.marketing_opt_in`,
  ALL_NURSES: `u.role='NURSE' AND u.status='ACTIVE'`,
  AVAILABLE_NURSES: `u.role='NURSE' AND u.status='ACTIVE' AND EXISTS(SELECT 1 FROM nurses n WHERE n.user_id=u.id AND n.work_status='AVAILABLE')`,
};

@Controller('v1/admin') @UseGuards(AuthGuard)
export class MarketingController {
  constructor(private readonly db: DbService) {}

  @Get('marketing') async overview(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const features = (await this.db.query('SELECT key,enabled,config,updated_at FROM marketing_features ORDER BY key')).rows;
    const s = (await this.db.query(`SELECT
      (SELECT count(*)::int FROM users WHERE role='PATIENT' AND marketing_opt_in) AS opted_in,
      (SELECT count(*)::int FROM pack_grants WHERE expires_at>now()) AS active_packs,
      (SELECT count(*)::int FROM promo_codes WHERE source='WINBACK' AND created_at>now()-interval '30 days') AS winback_30d,
      (SELECT count(*)::int FROM care_requests WHERE promo_snapshot->>'auto'='true' AND status NOT IN ('CANCELLED','UNFULFILLED') AND created_at>now()-interval '30 days') AS auto_discount_orders_30d,
      (SELECT count(*)::int FROM broadcasts WHERE created_at>now()-interval '30 days') AS broadcasts_30d`)).rows[0];
    return { features, stats: s };
  }

  @Put('marketing/:key') async setFeature(@Request() r: AuthRequest, @Param('key') key: string, @Body() d: FeatureDto) {
    requireRole(r.user!, 'ADMIN');
    if (!(KEYS as readonly string[]).includes(key)) missing();
    if (d.enabled === undefined && d.config === undefined) bad('NOTHING_TO_UPDATE');
    const config = d.config === undefined ? undefined : sanitizeConfig(key, d.config);
    return this.db.transaction(async c => {
      const cur = (await c.query('SELECT enabled,config FROM marketing_features WHERE key=$1 FOR UPDATE', [key])).rows[0];
      if (!cur) missing();
      const next = { enabled: d.enabled ?? cur.enabled, config: config ?? cur.config };
      if (next.enabled && config === undefined) sanitizeConfig(key, cur.config); // never switch on a broken config
      await c.query('UPDATE marketing_features SET enabled=$2,config=$3::jsonb,updated_at=now(),updated_by=$4 WHERE key=$1', [key, next.enabled, JSON.stringify(next.config), r.user!.id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'marketing.updated','marketing',gen_random_uuid(),$2::jsonb)`, [r.user!.id, JSON.stringify({ key, enabled: next.enabled })]);
      return { key, ...next };
    });
  }

  // ---------- visit packs ----------
  @Get('marketing/packs') async packs(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return { items: (await this.db.query(`SELECT g.id,g.name,g.visits,g.percent,g.expires_at,coalesce(u.display_name,u.phone_e164) AS patient,
      (SELECT count(*)::int FROM care_requests cr WHERE cr.promo_snapshot->>'packGrantId'=g.id::text AND cr.status NOT IN ('CANCELLED','UNFULFILLED')) AS used
      FROM pack_grants g JOIN users u ON u.id=g.user_id ORDER BY g.created_at DESC LIMIT 100`)).rows };
  }

  @Post('marketing/packs/grant') async grant(@Request() r: AuthRequest, @Body() d: GrantDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const u = (await c.query(`SELECT id FROM users WHERE phone_e164=$1 AND role='PATIENT' AND status='ACTIVE'`, [d.phone])).rows[0];
      if (!u) missing();
      const g = (await c.query(`INSERT INTO pack_grants(user_id,name,visits,percent,expires_at,created_by) VALUES($1,$2,$3,$4,now()+($5||' days')::interval,$6) RETURNING id`,
        [u.id, d.name, d.visits, d.percent, String(d.validDays), r.user!.id])).rows[0];
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'pack.granted','user',$2,$3::jsonb)`, [r.user!.id, u.id, JSON.stringify({ name: d.name, visits: d.visits, percent: d.percent })]);
      await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('pack.granted',$1,$2::jsonb)`, [g.id, JSON.stringify({ recipientUserId: u.id })]);
      return { id: g.id };
    });
  }

  // ---------- broadcasts ----------
  @Get('broadcasts/preview') async preview(@Request() r: AuthRequest, @Query('audience') audience: string) {
    requireRole(r.user!, 'ADMIN');
    if (!AUDIENCE_SQL[audience]) bad('INVALID_AUDIENCE');
    const q = (await this.db.query(`SELECT count(DISTINCT u.id)::int AS users,count(t.id)::int AS devices FROM users u JOIN device_tokens t ON t.user_id=u.id WHERE ${AUDIENCE_SQL[audience]}`)).rows[0];
    return q;
  }

  @Post('broadcasts') async broadcast(@Request() r: AuthRequest, @Body() d: BroadcastDto) {
    requireRole(r.user!, 'ADMIN');
    const f = (await this.db.query(`SELECT enabled FROM marketing_features WHERE key='broadcasts'`)).rows[0];
    if (!f?.enabled) conflict('BROADCASTS_DISABLED');
    return this.db.transaction(async c => {
      const reach = (await c.query(`SELECT count(t.id)::int AS devices FROM users u JOIN device_tokens t ON t.user_id=u.id WHERE ${AUDIENCE_SQL[d.audience]}`)).rows[0].devices;
      if (!reach) conflict('NO_REACHABLE_DEVICES');
      const b = (await c.query(`INSERT INTO broadcasts(audience,title,body,promo_code,total,created_by) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
        [d.audience, d.title.trim(), d.body.trim(), d.promoCode?.trim().toUpperCase() ?? null, reach, r.user!.id])).rows[0];
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'broadcast.queued','broadcast',$2,$3::jsonb)`, [r.user!.id, b.id, JSON.stringify({ audience: d.audience, devices: reach })]);
      return { id: b.id, queuedFor: reach }; // delivered by the worker
    });
  }

  @Get('broadcasts') async history(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return { items: (await this.db.query('SELECT id,audience,title,body,promo_code,status,total,sent,failed,created_at,finished_at FROM broadcasts ORDER BY created_at DESC LIMIT 50')).rows };
  }
}
