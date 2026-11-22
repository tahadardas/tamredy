import { BadRequestException, Body, Controller, Delete, Get, Param, Patch, Post, Put, Request, UseGuards } from '@nestjs/common';
import { IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, Matches, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { missing } from '../common/errors.js';
import { DuesService } from '../pricing/fees.service.js';

const HHMM = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
class SettingsDto {
  @IsOptional() @IsBoolean() distanceEnabled?: boolean;
  @IsOptional() @IsNumber() @Min(0) @Max(500) freeKm?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(1_000_000) perKm?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(100_000_000) maxDistanceFee?: number;
  @IsOptional() @IsBoolean() nightEnabled?: boolean;
  @IsOptional() @Matches(HHMM) nightStart?: string;
  @IsOptional() @Matches(HHMM) nightEnd?: string;
  @IsOptional() @IsNumber() @Min(0) @Max(300) nightPercent?: number;
  @IsOptional() @IsBoolean() holidayEnabled?: boolean;
  @IsOptional() @IsNumber() @Min(0) @Max(300) holidayPercent?: number;
  @IsOptional() @IsArray() @IsInt({ each: true }) @Min(0, { each: true }) @Max(6, { each: true }) weekendDays?: number[];
  @IsOptional() @IsBoolean() stackSurcharges?: boolean;
  @IsOptional() @IsBoolean() taxEnabled?: boolean;
  @IsOptional() @IsNumber() @Min(0) @Max(100) taxPercent?: number;
  @IsOptional() @IsString() @MaxLength(30) taxLabel?: string;
  @IsOptional() @IsBoolean() tipsEnabled?: boolean;
  @IsOptional() @IsNumber() @Min(0) nurseDebtLimit?: number;
  @IsOptional() @IsBoolean() referralEnabled?: boolean;
  @IsOptional() @IsNumber() @Min(1) @Max(100) referralReferredPercent?: number;
  @IsOptional() @IsNumber() @Min(1) @Max(100) referralReferrerPercent?: number;
  @IsOptional() @IsNumber() @Min(1) referralMaxDiscount?: number;
  @IsOptional() @IsInt() @Min(0) referralMaxRewardsPerMonth?: number;
  @IsOptional() @IsInt() @Min(1) @Max(1000) promoAttemptsPerHour?: number;
  @IsOptional() @IsInt() @Min(0) promoMaxOrders30d?: number;
}
const SETTING_COLS: Record<string, string> = {
  distanceEnabled: 'distance_enabled', freeKm: 'free_km', perKm: 'per_km', maxDistanceFee: 'max_distance_fee', nightEnabled: 'night_enabled', nightStart: 'night_start',
  nightEnd: 'night_end', nightPercent: 'night_percent', holidayEnabled: 'holiday_enabled', holidayPercent: 'holiday_percent', weekendDays: 'weekend_days',
  stackSurcharges: 'stack_surcharges', taxEnabled: 'tax_enabled', taxPercent: 'tax_percent', taxLabel: 'tax_label', tipsEnabled: 'tips_enabled',
  nurseDebtLimit: 'nurse_debt_limit', referralEnabled: 'referral_enabled', referralReferredPercent: 'referral_referred_percent', referralReferrerPercent: 'referral_referrer_percent',
  referralMaxDiscount: 'referral_max_discount', referralMaxRewardsPerMonth: 'referral_max_rewards_per_month', promoAttemptsPerHour: 'promo_attempts_per_hour', promoMaxOrders30d: 'promo_max_orders_30d',
};
class HolidayDto { @Matches(/^\d{4}-\d{2}-\d{2}$/) day!: string; @IsString() @MaxLength(80) name!: string; }
class TierDto {
  @IsOptional() @IsNumber() @Min(1) @Max(5) minReputation?: number;
  @IsOptional() @IsInt() @Min(0) minReviews?: number;
  @IsOptional() @IsInt() @Min(0) @Max(10000) commissionBps?: number;
  @IsOptional() @IsBoolean() active?: boolean;
}
class SettleDto { @IsIn(['FROM_NURSE', 'TO_NURSE']) direction!: 'FROM_NURSE' | 'TO_NURSE'; @IsInt() @Min(1) @Max(1_000_000_000) amount!: number; @IsOptional() @IsString() @MaxLength(300) note?: string; }

/** Administrator controls for fees, tax, holidays, commission tiers, nurse dues and promo-abuse review. */
@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminFeesController {
  constructor(private readonly db: DbService, private readonly dues: DuesService = new DuesService()) {}

  @Get('pricing-settings') async settings(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const s = (await this.db.query('SELECT * FROM pricing_settings WHERE id=1')).rows[0];
    return { settings: s, holidays: (await this.db.query(`SELECT to_char(day,'YYYY-MM-DD') AS day,name,active FROM holidays ORDER BY day`)).rows,
      tiers: (await this.db.query('SELECT * FROM commission_tiers ORDER BY min_reputation DESC')).rows };
  }

  @Put('pricing-settings') async updateSettings(@Request() r: AuthRequest, @Body() d: SettingsDto) {
    requireRole(r.user!, 'ADMIN');
    const sets: string[] = [], vals: unknown[] = [];
    for (const [k, col] of Object.entries(SETTING_COLS)) if ((d as any)[k] !== undefined) { vals.push((d as any)[k]); sets.push(`${col}=$${vals.length}`); }
    if (!sets.length) throw new BadRequestException({ code: 'NOTHING_TO_UPDATE' });
    return this.db.transaction(async c => {
      vals.push(r.user!.id);
      const u = await c.query(`UPDATE pricing_settings SET ${sets.join(',')},updated_at=now(),updated_by=$${vals.length} WHERE id=1 RETURNING *`, vals);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'pricing_settings.updated','settings',gen_random_uuid(),$2::jsonb)`, [r.user!.id, JSON.stringify(d)]);
      return u.rows[0]; // applies to NEW orders; existing orders keep the snapshot taken when they were placed
    });
  }

  @Post('holidays') async addHoliday(@Request() r: AuthRequest, @Body() d: HolidayDto) {
    requireRole(r.user!, 'ADMIN');
    await this.db.query(`INSERT INTO holidays(day,name) VALUES($1,$2) ON CONFLICT (day) DO UPDATE SET name=EXCLUDED.name,active=true`, [d.day, d.name]);
    return { day: d.day };
  }
  @Delete('holidays/:day') async removeHoliday(@Request() r: AuthRequest, @Param('day') day: string) {
    requireRole(r.user!, 'ADMIN');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new BadRequestException({ code: 'INVALID_DATE' });
    await this.db.query('DELETE FROM holidays WHERE day=$1', [day]);
    return { removed: day };
  }

  @Post('commission-tiers') async addTier(@Request() r: AuthRequest, @Body() d: TierDto) {
    requireRole(r.user!, 'ADMIN');
    if (d.minReputation == null || d.commissionBps == null) throw new BadRequestException({ code: 'REPUTATION_AND_COMMISSION_REQUIRED' });
    const t = (await this.db.query('INSERT INTO commission_tiers(min_reputation,min_reviews,commission_bps) VALUES($1,$2,$3) RETURNING id', [d.minReputation, d.minReviews ?? 10, d.commissionBps])).rows[0];
    return { id: t.id };
  }
  @Patch('commission-tiers/:id') async updateTier(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: TierDto) {
    requireRole(r.user!, 'ADMIN');
    const cols: Record<string, string> = { minReputation: 'min_reputation', minReviews: 'min_reviews', commissionBps: 'commission_bps', active: 'active' };
    const sets: string[] = [], vals: unknown[] = [id];
    for (const [k, col] of Object.entries(cols)) if ((d as any)[k] !== undefined) { vals.push((d as any)[k]); sets.push(`${col}=$${vals.length}`); }
    if (!sets.length) throw new BadRequestException({ code: 'NOTHING_TO_UPDATE' });
    if (!(await this.db.query(`UPDATE commission_tiers SET ${sets.join(',')} WHERE id=$1 RETURNING id`, vals)).rowCount) missing();
    return { id };
  }
  @Delete('commission-tiers/:id') async deleteTier(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'ADMIN');
    await this.db.query('DELETE FROM commission_tiers WHERE id=$1', [id]);
    return { removed: id };
  }

  // ---------- company dues from nurses ----------
  @Get('dues') async allDues(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const limit = Number((await this.db.query('SELECT nurse_debt_limit FROM pricing_settings WHERE id=1')).rows[0].nurse_debt_limit);
    const rows = (await this.db.query(`SELECT n.id AS nurse_id,coalesce(u.display_name,u.phone_e164) AS name,coalesce(o.owed,0) AS owed,coalesce(o.cnt,0) AS visits,
        coalesce(f.s,0) AS settled_from_nurse,coalesce(t.s,0) AS paid_to_nurse,coalesce(o.owed,0)-coalesce(f.s,0)+coalesce(t.s,0) AS balance
      FROM nurses n JOIN users u ON u.id=n.user_id
      LEFT JOIN (SELECT a.nurse_id,sum(cr.owed_to_company) AS owed,count(*)::int AS cnt FROM care_requests cr JOIN request_assignments a ON a.request_id=cr.id
         JOIN visits v ON v.assignment_id=a.id AND v.completed_at IS NOT NULL WHERE cr.payment_status='PAID' GROUP BY a.nurse_id) o ON o.nurse_id=n.id
      LEFT JOIN (SELECT nurse_id,sum(amount) AS s FROM nurse_settlements WHERE direction='FROM_NURSE' GROUP BY nurse_id) f ON f.nurse_id=n.id
      LEFT JOIN (SELECT nurse_id,sum(amount) AS s FROM nurse_settlements WHERE direction='TO_NURSE' GROUP BY nurse_id) t ON t.nurse_id=n.id
      WHERE o.owed IS NOT NULL OR f.s IS NOT NULL OR t.s IS NOT NULL ORDER BY balance DESC`)).rows;
    return { limit, totalOwedToCompany: rows.reduce((a, x) => a + Math.max(0, Number(x.balance)), 0), items: rows.map(x => ({ ...x, blocked: limit > 0 && Number(x.balance) > limit })) };
  }

  @Post('dues/:nurseId/settle') async settle(@Request() r: AuthRequest, @Param('nurseId') nurseId: string, @Body() d: SettleDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      if (!(await c.query('SELECT 1 FROM nurses WHERE id=$1', [nurseId])).rowCount) missing();
      await c.query('INSERT INTO nurse_settlements(nurse_id,direction,amount,note,created_by) VALUES($1,$2,$3,$4,$5)', [nurseId, d.direction, d.amount, d.note ?? null, r.user!.id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'dues.settled','nurse',$2,$3::jsonb)`, [r.user!.id, nurseId, JSON.stringify({ direction: d.direction, amount: d.amount })]);
      return this.dues.balance(c, nurseId);
    });
  }

  // ---------- promo abuse review ----------
  /** Detection, not blocking: several accounts using promos from the same address, and accounts guessing codes. */
  @Get('promos/abuse') async abuse(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const sameAddress = (await this.db.query(`SELECT lower(trim(cr.address_text)) AS address,count(DISTINCT cr.requester_user_id)::int AS accounts,count(*)::int AS orders,
        array_agg(DISTINCT p.code) AS codes FROM care_requests cr JOIN promo_codes p ON p.id=cr.promo_id
        WHERE cr.status NOT IN ('CANCELLED','UNFULFILLED') GROUP BY 1 HAVING count(DISTINCT cr.requester_user_id)>1 ORDER BY accounts DESC,orders DESC LIMIT 50`)).rows;
    const guessing = (await this.db.query(`SELECT pa.user_id,coalesce(u.display_name,u.phone_e164) AS name,count(*) FILTER (WHERE NOT pa.ok)::int AS failed_attempts
        FROM promo_attempts pa JOIN users u ON u.id=pa.user_id WHERE pa.created_at>now()-interval '24 hours'
        GROUP BY pa.user_id,u.display_name,u.phone_e164 HAVING count(*) FILTER (WHERE NOT pa.ok)>=5 ORDER BY failed_attempts DESC LIMIT 50`)).rows;
    return { sameAddress, guessing };
  }
}
