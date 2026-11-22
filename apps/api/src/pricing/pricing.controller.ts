import { BadRequestException, Body, Controller, Get, Param, Post, Request, UseGuards } from '@nestjs/common';
import { IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, forbidden, missing } from '../common/errors.js';
import { applyCollection, estimateV2, payableTotal, ruleFromRow } from './pricing.js';
import { DuesService, FeesService } from './fees.service.js';
import { ReferralService } from './referral.service.js';
import { AutoDiscountService } from './auto-discounts.service.js';
import { PromoService, toRule } from './promo.service.js';

class QuoteDto { @IsUUID() serviceId!: string; @IsOptional() @IsString() @MaxLength(40) promoCode?: string; }
class ClaimDto { @IsString() @MaxLength(40) code!: string; }
class TipDto { @IsInt() @Min(0) @Max(100_000_000) amount!: number; }
class CollectDto { @IsInt() @Min(1) @Max(1_000_000_000) amount!: number; }

const BILL_SQL = `SELECT cr.id AS request_id,cr.status,cr.requester_user_id,cr.service_minutes,cr.gross_amount,cr.discount_amount,cr.amount_due,
    cr.payment_status,cr.currency_code,cr.nurse_earning,cr.commission_bps_applied,cr.surcharge_amount,cr.distance_fee,cr.tax_amount,cr.tip_amount,cr.pricing->'fees'->>'taxLabel' AS tax_label,cr.promo_snapshot->>'code' AS promo_code,s.title_ar AS service_title,v.id AS visit_id,
    coalesce((SELECT sum(cc.amount) FROM cash_collections cc WHERE cc.visit_id=v.id),0) AS collected
  FROM care_requests cr JOIN services s ON s.id=cr.service_id
  LEFT JOIN request_assignments a ON a.request_id=cr.id
  LEFT JOIN visits v ON v.assignment_id=a.id`;

function shape(r: any) {
  const due = Number(r.amount_due ?? 0), collected = Number(r.collected ?? 0);
  return {
    requestId: r.request_id, visitId: r.visit_id, status: r.status, serviceTitle: r.service_title, currency: r.currency_code,
    billed: r.amount_due != null, minutes: r.service_minutes, gross: Number(r.gross_amount ?? 0), discount: Number(r.discount_amount ?? 0),
    promoCode: r.promo_code, due, collected, paymentStatus: r.payment_status,
    surcharge: Number(r.surcharge_amount ?? 0), distanceFee: Number(r.distance_fee ?? 0), tax: Number(r.tax_amount ?? 0), taxLabel: r.tax_label ?? 'ضريبة',
    tip: Number(r.tip_amount ?? 0), payable: payableTotal(due, Number(r.tip_amount ?? 0)),
    remaining: Math.max(0, payableTotal(due, Number(r.tip_amount ?? 0)) - collected),
  };
}

@Controller('v1') @UseGuards(AuthGuard)
export class PricingController {
  constructor(private readonly db: DbService, private readonly promos: PromoService, private readonly fees: FeesService = new FeesService(),
    private readonly dues: DuesService = new DuesService(), private readonly referrals: ReferralService = new ReferralService(),
    private readonly autos: AutoDiscountService = new AutoDiscountService()) {}

  /** Instant estimate before ordering (optionally with a promo code). */
  @Post('pricing/quote') async quote(@Request() r: AuthRequest, @Body() dto: QuoteDto) {
    requireRole(r.user!, 'PATIENT');
    const s = (await this.db.query(`SELECT * FROM services WHERE id=$1 AND active=true AND dispatch_approved=true`, [dto.serviceId])).rows[0];
    if (!s) missing();
    const rule = ruleFromRow(s);
    const promo = await this.promos.resolve(this.db, r.user!.id, dto.serviceId, rule.basePrice, dto.promoCode);
    const auto = promo ? null : await this.autos.pick(this.db, r.user!.id);
    return { currency: s.currency_code, promoCode: promo?.code ?? auto?.label ?? null, autoDiscount: auto ? auto.kind : null,
      ...estimateV2(rule, promo ? toRule(promo) : auto, await this.fees.snapshot(this.db)) };
  }

  /** Save a company code (e.g. after install) so it applies automatically to the next order. */
  @Post('promos/claim') async claim(@Request() r: AuthRequest, @Body() dto: ClaimDto) {
    requireRole(r.user!, 'PATIENT');
    const p = await this.promos.claim(this.db, r.user!.id, dto.code);
    return { claimed: true, code: p.code, description: p.description, type: p.type, value: Number(p.value) };
  }

  @Get('requests/:id/bill') async patientBill(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'PATIENT');
    const q = await this.db.query(`${BILL_SQL} WHERE cr.id=$1 AND cr.requester_user_id=$2 LIMIT 1`, [id, r.user!.id]);
    if (!q.rowCount) missing();
    return shape(q.rows[0]);
  }

  @Get('nurse/requests/:id/bill') async nurseBill(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'NURSE');
    const q = await this.db.query(`${BILL_SQL} JOIN nurses n ON n.id=a.nurse_id WHERE cr.id=$1 AND n.user_id=$2 LIMIT 1`, [id, r.user!.id]);
    if (!q.rowCount) missing();
    const row = q.rows[0];
    return { ...shape(row), nurseEarning: Number(row.nurse_earning ?? 0) + Number(row.tip_amount ?? 0), commissionBps: row.commission_bps_applied };
  }

  /** Optional tip, added to the cash the patient hands over; 100% goes to the nurse. Allowed until the bill is fully paid. */
  @Post('requests/:id/tip') async tip(@Request() r: AuthRequest, @Param('id') id: string, @Body() dto: TipDto) {
    requireRole(r.user!, 'PATIENT');
    return this.db.transaction(async c => {
      if (!(await this.fees.row(c)).tips_enabled) conflict('TIPS_DISABLED');
      const q = (await c.query(`SELECT cr.id,cr.status,cr.payment_status,nu.id AS nurse_user FROM care_requests cr
        LEFT JOIN request_assignments a ON a.request_id=cr.id LEFT JOIN visits v ON v.assignment_id=a.id AND v.completed_at IS NOT NULL
        LEFT JOIN nurses n ON n.id=a.nurse_id AND v.id IS NOT NULL LEFT JOIN users nu ON nu.id=n.user_id
        WHERE cr.id=$1 AND cr.requester_user_id=$2 FOR UPDATE OF cr`, [id, r.user!.id])).rows[0];
      if (!q) missing();
      if (q.status !== 'COMPLETED') conflict('NOT_COMPLETED_YET');
      if (q.payment_status === 'PAID') conflict('ALREADY_PAID');
      await c.query('UPDATE care_requests SET tip_amount=$2,updated_at=now() WHERE id=$1', [id, dto.amount]);
      if (q.nurse_user) await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('payment.tip',$1,$2::jsonb)`, [id, JSON.stringify({ requestId: id, recipientUserId: q.nurse_user })]);
      return { tip: dto.amount };
    });
  }

  /** The nurse records cash received. Short payment -> stays open with the remaining amount; excess -> change. */
  @Post('nurse/requests/:id/collect') async collect(@Request() r: AuthRequest, @Param('id') id: string, @Body() dto: CollectDto) {
    requireRole(r.user!, 'NURSE');
    return this.db.transaction(async c => {
      const req = (await c.query(`SELECT cr.id,cr.requester_user_id,cr.amount_due,cr.tip_amount,cr.payment_status FROM care_requests cr WHERE cr.id=$1 FOR UPDATE`, [id])).rows[0];
      if (!req) missing();
      const v = (await c.query(`SELECT v.id,a.nurse_id FROM visits v JOIN request_assignments a ON a.id=v.assignment_id JOIN nurses n ON n.id=a.nurse_id
        WHERE a.request_id=$1 AND n.user_id=$2`, [id, r.user!.id])).rows[0];
      if (!v) forbidden();
      if (req.payment_status === 'PAID') conflict('ALREADY_PAID');
      if (!['DUE', 'PARTIAL'].includes(req.payment_status)) conflict('NOT_BILLED_YET');
      const already = Number((await c.query('SELECT coalesce(sum(amount),0) AS s FROM cash_collections WHERE visit_id=$1', [v.id])).rows[0].s);
      let res;
      try { res = applyCollection(payableTotal(Number(req.amount_due), Number(req.tip_amount)), already, dto.amount); } catch { throw new BadRequestException({ code: 'INVALID_AMOUNT' }); }
      await c.query(`INSERT INTO cash_collections(visit_id,collector_nurse_id,amount) VALUES($1,$2,$3)`, [v.id, v.nurse_id, res.applied]);
      await c.query(`UPDATE care_requests SET payment_status=$2,paid_at=CASE WHEN $2='PAID' THEN now() END,version=version+1,updated_at=now() WHERE id=$1`, [id, res.status]);
      if (res.status === 'PAID') {
        await this.dues.enforce(c, v.nurse_id);                           // owes too much to the company -> stops receiving requests
        await this.referrals.rewardIfFirstPaid(c, req.requester_user_id); // first paid order of a referred friend -> reward the referrer
      }
      await c.query(`INSERT INTO request_events(request_id,actor_user_id,event_type,payload) VALUES($1,$2,$3,$4::jsonb)`,
        [id, r.user!.id, `payment.${res.status.toLowerCase()}`, JSON.stringify({ received: dto.amount, applied: res.applied, remaining: res.remaining })]);
      await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES($1,$2,$3::jsonb)`,
        [`payment.${res.status.toLowerCase()}`, id, JSON.stringify({ requestId: id, recipientUserId: req.requester_user_id })]);
      return { ...res, due: Number(req.amount_due), tip: Number(req.tip_amount), payable: payableTotal(Number(req.amount_due), Number(req.tip_amount)), message: res.status === 'PAID' ? (res.change > 0 ? `تم الدفع. أعد للمريض ${res.change} فكة.` : 'تم استلام المبلغ كاملًا.') : `المبلغ ناقص: المتبقي ${res.remaining}. أكمل التحصيل.` };
    });
  }
}
