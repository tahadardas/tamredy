import { BadRequestException, Body, Controller, Delete, Get, Headers, Param, Patch, Post, Put, Request, UseGuards } from '@nestjs/common';
import { IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, Matches, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { missing } from '../common/errors.js';
import { DuesService } from '../pricing/fees.service.js';
import { LedgerService } from '../wallet/ledger.service.js';

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
class SettleDto { @IsString() @Matches(/^[A-Z][A-Z0-9_]{2,15}$/) currencyCode!: string; @IsIn(['FROM_NURSE', 'TO_NURSE']) direction!: 'FROM_NURSE' | 'TO_NURSE'; @IsInt() @Min(1) @Max(1_000_000_000) amount!: number; @IsOptional() @IsString() @MaxLength(300) note?: string; }

/** Administrator controls for fees, tax, holidays, commission tiers, nurse dues and promo-abuse review. */
@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminFeesController {
  constructor(private readonly db: DbService, private readonly dues: DuesService, private readonly ledger: LedgerService) {}

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
    const rows = (await this.db.query(`WITH positions AS (
        SELECT split_part(e.account_id,':',2)::uuid AS nurse_id,e.currency AS currency_code,
          sum(CASE WHEN e.account_id LIKE 'CASH_HELD_BY_NURSE:%' THEN e.debit_amount-e.credit_amount ELSE 0 END) AS cash_held,
          sum(CASE WHEN e.account_id LIKE 'NURSE_PAYABLE:%' THEN e.credit_amount-e.debit_amount ELSE 0 END) AS nurse_payable,
          sum(CASE WHEN t.transaction_type='NURSE_SETTLEMENT_FROM_NURSE' AND e.account_id LIKE 'CASH_HELD_BY_NURSE:%' THEN e.credit_amount ELSE 0 END) AS settled_from_nurse,
          sum(CASE WHEN t.transaction_type='NURSE_SETTLEMENT_TO_NURSE' AND e.account_id LIKE 'NURSE_PAYABLE:%' THEN e.debit_amount ELSE 0 END) AS paid_to_nurse
        FROM financial_ledger_entries e JOIN financial_transactions t ON t.id=e.transaction_id
        WHERE e.account_id LIKE 'CASH_HELD_BY_NURSE:%' OR e.account_id LIKE 'NURSE_PAYABLE:%'
        GROUP BY split_part(e.account_id,':',2)::uuid,e.currency
      ) SELECT n.id AS nurse_id,p.currency_code,coalesce(u.display_name,u.phone_e164) AS name,
        greatest(coalesce(p.cash_held,0)-coalesce(p.nurse_payable,0),0) AS owed,coalesce(o.cnt,0) AS visits,
        coalesce(p.settled_from_nurse,0) AS settled_from_nurse,coalesce(p.paid_to_nurse,0) AS paid_to_nurse,
        coalesce(p.cash_held,0)-coalesce(p.nurse_payable,0) AS balance,
        a.credit_limit,a.settlement_required
      FROM nurses n JOIN users u ON u.id=n.user_id
      LEFT JOIN positions p ON p.nurse_id=n.id
      LEFT JOIN nurse_financial_currency_accounts a ON a.nurse_id=n.id AND a.currency_code=p.currency_code
      LEFT JOIN (SELECT a.nurse_id,count(*)::int AS cnt FROM request_assignments a
        JOIN visits v ON v.assignment_id=a.id AND v.completed_at IS NOT NULL GROUP BY a.nurse_id) o ON o.nurse_id=n.id
      WHERE p.nurse_id IS NOT NULL ORDER BY balance DESC`)).rows;
    return { limit:null, totalsByCurrency: Object.fromEntries([...new Set(rows.map(row=>String(row.currency_code)))].map(currency=>[currency,rows.filter(row=>row.currency_code===currency).reduce((total,row)=>total+Math.max(0,Number(row.balance)),0)])),
      items: rows.map(x => ({ ...x, blocked: x.settlement_required===true ||
        (Number(x.credit_limit)>0 && Number(x.balance)>Number(x.credit_limit)) })) };
  }

  @Post('dues/:nurseId/settle') async settle(@Request() r: AuthRequest, @Param('nurseId') nurseId: string,
    @Body() d: SettleDto, @Headers('idempotency-key') idempotencyKey: string) {
    requireRole(r.user!, 'ADMIN');
    if (!idempotencyKey || idempotencyKey.length > 128) throw new BadRequestException({ code: 'IDEMPOTENCY_KEY_REQUIRED' });
    return this.db.transaction(async c => {
      if (!(await c.query('SELECT 1 FROM nurses WHERE id=$1', [nurseId])).rowCount) missing();
      const transaction = await this.ledger.postTransaction(c, {
        transactionType:d.direction==='FROM_NURSE'?'NURSE_SETTLEMENT_FROM_NURSE':'NURSE_SETTLEMENT_TO_NURSE',
        referenceType:'NURSE',referenceId:nurseId,currencyCode:d.currencyCode,
        idempotencyKey:`nurse-settlement:${r.user!.id}:${idempotencyKey}`,actorUserId:r.user!.id,
        legs:d.direction==='FROM_NURSE'
          ? [{accountId:'CASH_CLEARING',debitAmount:d.amount,creditAmount:0},{accountId:`CASH_HELD_BY_NURSE:${nurseId}`,debitAmount:0,creditAmount:d.amount}]
          : [{accountId:`NURSE_PAYABLE:${nurseId}`,debitAmount:d.amount,creditAmount:0},{accountId:'CASH_CLEARING',debitAmount:0,creditAmount:d.amount}],
      });
      await c.query(`INSERT INTO nurse_settlements(nurse_id,direction,amount,note,created_by,transaction_id)
        VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(transaction_id) DO NOTHING`,
      [nurseId,d.direction,d.amount,d.note ?? null,r.user!.id,transaction.transactionId]);
      if (!transaction.replayed) {
        await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'dues.settled','nurse',$2,$3::jsonb)`, [r.user!.id, nurseId, JSON.stringify({ direction: d.direction, amount: d.amount, transactionId: transaction.transactionId })]);
      }
      return this.dues.balance(c,nurseId,d.currencyCode);
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
