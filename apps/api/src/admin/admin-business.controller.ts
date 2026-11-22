import { BadRequestException, Body, Controller, Get, Param, Patch, Post, Query, Request, UseGuards } from '@nestjs/common';
import { IsArray, IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, IsDateString, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { ReferenceCacheService } from '../cache/reference-cache.service.js';
import { conflict, missing } from '../common/errors.js';

class ServiceDto {
  @IsOptional() @Matches(/^[A-Z0-9_]{3,40}$/) code?: string;
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) titleAr?: string;
  @IsOptional() @IsString() @MaxLength(400) descriptionAr?: string;
  @IsOptional() @IsInt() @Min(0) @Max(100_000_000) price?: number;
  @IsOptional() @IsInt() @Min(1) @Max(1440) includedMinutes?: number;
  @IsOptional() @IsInt() @Min(1) @Max(240) blockMinutes?: number;
  @IsOptional() @IsInt() @Min(0) @Max(100_000_000) blockPrice?: number;
  @IsOptional() @IsInt() @Min(1) @Max(1440) expectedMinutes?: number;
  @IsOptional() @IsInt() @Min(1) @Max(100_000) roundingStep?: number;
  @IsOptional() @IsInt() @Min(0) @Max(10000) commissionBps?: number;
  @IsOptional() @IsInt() @Min(0) @Max(10_000) sortOrder?: number;
  @IsOptional() @IsBoolean() active?: boolean;
  /** Clinical/legal approval for dispatch. Only enable for services your clinical lead approved. */
  @IsOptional() @IsBoolean() dispatchApproved?: boolean;
}

class PromoDto {
  @IsOptional() @Matches(/^[A-Za-z0-9_-]{3,30}$/) code?: string;
  @IsOptional() @IsString() @MaxLength(200) description?: string;
  @IsOptional() @IsIn(['PERCENT', 'FIXED']) type?: 'PERCENT' | 'FIXED';
  @IsOptional() @IsInt() @Min(1) @Max(100_000_000) value?: number;
  @IsOptional() @IsInt() @Min(1) maxDiscount?: number;
  @IsOptional() @IsInt() @Min(0) minAmount?: number;
  @IsOptional() @IsDateString() validFrom?: string;
  @IsOptional() @IsDateString() validTo?: string;
  @IsOptional() @IsInt() @Min(1) maxRedemptions?: number;
  @IsOptional() @IsInt() @Min(1) @Max(1000) perUserLimit?: number;
  @IsOptional() @IsBoolean() firstOrderOnly?: boolean;
  @IsOptional() @IsArray() @IsUUID('all', { each: true }) serviceIds?: string[];
  @IsOptional() @IsBoolean() active?: boolean;
}

class RewardDto {
  @IsUUID() nurseId!: string;
  @IsIn(['REPUTATION', 'WORK', 'REVENUE', 'OTHER']) kind!: 'REPUTATION' | 'WORK' | 'REVENUE' | 'OTHER';
  @IsInt() @Min(1) @Max(1_000_000_000) amount!: number;
  @IsString() @MaxLength(30) period!: string;
  @IsOptional() @IsString() @MaxLength(300) note?: string;
}

const SERVICE_COLS: Record<string, string> = {
  titleAr: 'title_ar', descriptionAr: 'description_ar', price: 'price_amount', includedMinutes: 'included_minutes', blockMinutes: 'block_minutes',
  blockPrice: 'block_price', expectedMinutes: 'expected_minutes', roundingStep: 'rounding_step', commissionBps: 'commission_bps',
  sortOrder: 'sort_order', active: 'active', dispatchApproved: 'dispatch_approved',
};
const PROMO_COLS: Record<string, string> = {
  description: 'description', type: 'type', value: 'value', maxDiscount: 'max_discount', minAmount: 'min_amount', validFrom: 'valid_from', validTo: 'valid_to',
  maxRedemptions: 'max_redemptions', perUserLimit: 'per_user_limit', firstOrderOnly: 'first_order_only', serviceIds: 'service_ids', active: 'active',
};

/** Back-office business controls: service catalogue + prices, promo codes, top nurses + rewards. */
@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminBusinessController {
  constructor(private readonly db: DbService, private readonly cache: ReferenceCacheService) {}

  // ---------- services & prices ----------
  @Get('services') async services(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return { items: (await this.db.query(`SELECT id,code,title_ar,description_ar,price_amount,currency_code,included_minutes,block_minutes,block_price,expected_minutes,
      rounding_step,commission_bps,sort_order,active,dispatch_approved,requires_prescription FROM services ORDER BY sort_order,title_ar`)).rows };
  }

  @Post('services') async createService(@Request() r: AuthRequest, @Body() d: ServiceDto) {
    requireRole(r.user!, 'ADMIN');
    if (!d.code || !d.titleAr || d.price == null) throw new BadRequestException({ code: 'CODE_TITLE_PRICE_REQUIRED' });
    return this.db.transaction(async c => {
      if ((await c.query('SELECT 1 FROM services WHERE code=$1', [d.code])).rowCount) conflict('SERVICE_CODE_EXISTS');
      // New services stay hidden until active AND clinically approved are both switched on.
      const s = (await c.query(`INSERT INTO services(code,title_ar,description_ar,price_amount,included_minutes,block_minutes,block_price,expected_minutes,rounding_step,commission_bps,sort_order,active,dispatch_approved)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,
        [d.code, d.titleAr, d.descriptionAr ?? null, d.price, d.includedMinutes ?? 30, d.blockMinutes ?? 15, d.blockPrice ?? 0, d.expectedMinutes ?? 30,
         d.roundingStep ?? 1, d.commissionBps ?? 2000, d.sortOrder ?? 0, d.active ?? false, d.dispatchApproved ?? false])).rows[0];
      await this.after(c, r.user!.id, 'service.created', s.id, { code: d.code, price: d.price });
      return { id: s.id };
    }).finally(() => this.cache.invalidate('services:public'));
  }

  @Patch('services/:id') async updateService(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: ServiceDto) {
    requireRole(r.user!, 'ADMIN');
    const sets: string[] = [], vals: unknown[] = [id];
    for (const [k, col] of Object.entries(SERVICE_COLS)) if ((d as any)[k] !== undefined) { vals.push((d as any)[k]); sets.push(`${col}=$${vals.length}`); }
    if (!sets.length) throw new BadRequestException({ code: 'NOTHING_TO_UPDATE' });
    return this.db.transaction(async c => {
      const u = await c.query(`UPDATE services SET ${sets.join(',')},updated_at=now() WHERE id=$1 RETURNING id,active,price_amount`, vals);
      if (!u.rowCount) missing();
      await this.after(c, r.user!.id, 'service.updated', id, d);
      return u.rows[0];
    }).finally(() => this.cache.invalidate('services:public'));
  }

  // ---------- promo codes ----------
  @Get('promos') async promos(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return { items: (await this.db.query(`SELECT p.*,
      (SELECT count(*)::int FROM care_requests cr WHERE cr.promo_id=p.id AND cr.status NOT IN ('CANCELLED','UNFULFILLED')) AS used,
      (SELECT coalesce(sum(cr.discount_amount),0) FROM care_requests cr WHERE cr.promo_id=p.id AND cr.status='COMPLETED') AS discount_given,
      (SELECT count(*)::int FROM promo_claims k WHERE k.promo_id=p.id) AS claimed
      FROM promo_codes p ORDER BY p.created_at DESC LIMIT 200`)).rows };
  }

  @Post('promos') async createPromo(@Request() r: AuthRequest, @Body() d: PromoDto) {
    requireRole(r.user!, 'ADMIN');
    if (!d.code || !d.type || !d.value) throw new BadRequestException({ code: 'CODE_TYPE_VALUE_REQUIRED' });
    if (d.type === 'PERCENT' && d.value > 100) throw new BadRequestException({ code: 'PERCENT_MAX_100' });
    return this.db.transaction(async c => {
      if ((await c.query('SELECT 1 FROM promo_codes WHERE upper(code)=upper($1)', [d.code])).rowCount) conflict('PROMO_CODE_EXISTS');
      const p = (await c.query(`INSERT INTO promo_codes(code,description,type,value,max_discount,min_amount,valid_from,valid_to,max_redemptions,per_user_limit,first_order_only,service_ids,active,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING id`,
        [d.code, d.description ?? null, d.type, d.value, d.maxDiscount ?? null, d.minAmount ?? 0, d.validFrom ?? null, d.validTo ?? null, d.maxRedemptions ?? null,
         d.perUserLimit ?? 1, d.firstOrderOnly ?? false, d.serviceIds ?? null, d.active ?? true, r.user!.id])).rows[0];
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'promo.created','promo',$2,$3::jsonb)`, [r.user!.id, p.id, JSON.stringify({ code: d.code })]);
      return { id: p.id };
    });
  }

  /** Edits apply to FUTURE orders only: each order keeps the discount snapshot taken when it was placed. */
  @Patch('promos/:id') async updatePromo(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: PromoDto) {
    requireRole(r.user!, 'ADMIN');
    const sets: string[] = [], vals: unknown[] = [id];
    for (const [k, col] of Object.entries(PROMO_COLS)) if ((d as any)[k] !== undefined) { vals.push((d as any)[k]); sets.push(`${col}=$${vals.length}`); }
    if (!sets.length) throw new BadRequestException({ code: 'NOTHING_TO_UPDATE' });
    return this.db.transaction(async c => {
      const u = await c.query(`UPDATE promo_codes SET ${sets.join(',')} WHERE id=$1 RETURNING id,active`, vals);
      if (!u.rowCount) missing();
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'promo.updated','promo',$2,$3::jsonb)`, [r.user!.id, id, JSON.stringify(d)]);
      return u.rows[0];
    });
  }

  // ---------- top nurses + rewards ----------
  /** Reputation = Bayesian average of patient stars (a few perfect ratings do not beat many good ones).
   *  Work = completed visits; Revenue = company commission brought in. */
  @Get('leaderboard') async leaderboard(@Request() r: AuthRequest, @Query('period') period = 'month') {
    requireRole(r.user!, 'ADMIN');
    if (!['week', 'month', 'all'].includes(period)) throw new BadRequestException({ code: 'INVALID_PERIOD' });
    const from = period === 'week' ? `now()-interval '7 days'` : period === 'month' ? `date_trunc('month',now())` : `'-infinity'::timestamptz`;
    const rows = (await this.db.query(`WITH work AS (
        SELECT a.nurse_id,count(*)::int AS visits,sum(cr.amount_due) AS revenue,sum(cr.amount_due*cr.commission_bps/10000) AS commission
        FROM request_assignments a JOIN care_requests cr ON cr.id=a.request_id JOIN visits v ON v.assignment_id=a.id
        WHERE cr.status='COMPLETED' AND v.completed_at>=${from} GROUP BY a.nurse_id),
      rate AS (
        SELECT a.nurse_id,count(*)::int AS n,avg(vr.stars) AS avg FROM visit_reviews vr JOIN visits v ON v.id=vr.visit_id
        JOIN request_assignments a ON a.id=v.assignment_id WHERE vr.reviewer_role='PATIENT' AND vr.created_at>=${from} GROUP BY a.nurse_id),
      g AS (SELECT coalesce(avg(stars),4) AS m FROM visit_reviews WHERE reviewer_role='PATIENT')
      SELECT n.id AS nurse_id,coalesce(u.display_name,u.phone_e164) AS name,coalesce(w.visits,0) AS visits,coalesce(w.revenue,0) AS revenue,
        coalesce(w.commission,0) AS commission,coalesce(r.n,0) AS reviews,round(r.avg::numeric,2) AS avg_stars,
        round(((5*g.m)+coalesce(r.avg*r.n,0))/(5+coalesce(r.n,0))::numeric,2) AS reputation
      FROM nurses n JOIN users u ON u.id=n.user_id LEFT JOIN work w ON w.nurse_id=n.id LEFT JOIN rate r ON r.nurse_id=n.id CROSS JOIN g
      WHERE w.visits>0 OR r.n>0`)).rows;
    const top = (key: string) => [...rows].sort((a, b) => Number(b[key]) - Number(a[key]) || Number(b.visits) - Number(a.visits)).slice(0, 10);
    return { period, byReputation: top('reputation'), byWork: top('visits'), byCompanyRevenue: top('commission') };
  }

  @Post('rewards') async reward(@Request() r: AuthRequest, @Body() d: RewardDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      if (!(await c.query('SELECT 1 FROM nurses WHERE id=$1', [d.nurseId])).rowCount) missing();
      const w = (await c.query(`INSERT INTO nurse_rewards(nurse_id,period,kind,amount,note,created_by) VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
        [d.nurseId, d.period, d.kind, d.amount, d.note ?? null, r.user!.id])).rows[0];
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'reward.granted','nurse',$2,$3::jsonb)`,
        [r.user!.id, d.nurseId, JSON.stringify({ kind: d.kind, amount: d.amount, period: d.period })]);
      return { id: w.id };
    });
  }

  @Get('rewards') async rewards(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return { items: (await this.db.query(`SELECT w.id,w.period,w.kind,w.amount,w.note,w.created_at,coalesce(u.display_name,u.phone_e164) AS nurse_name
      FROM nurse_rewards w JOIN nurses n ON n.id=w.nurse_id JOIN users u ON u.id=n.user_id ORDER BY w.created_at DESC LIMIT 100`)).rows };
  }

  /** Audit + outbox event: invalidates the catalogue cache everywhere and tells every connected app to reload services. */
  private async after(c: { query: (s: string, p?: unknown[]) => Promise<any> }, actor: string, action: string, id: string, detail: unknown) {
    await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,$2,'service',$3,$4::jsonb)`, [actor, action, id, JSON.stringify(detail)]);
    await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('cache.invalidate',$1,$2::jsonb)`, [id, JSON.stringify({ namespace: 'services:public' })]);
  }
}
