import { Body, Controller, Get, Headers, Param, Post, Request, UseGuards } from '@nestjs/common';
import { IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';
import { estimateV2, payableTotal, ruleFromRow } from './pricing.js';
import { FeesService } from './fees.service.js';
import { AutoDiscountService } from './auto-discounts.service.js';
import { PromoService, toRule } from './promo.service.js';
import { BillingService } from './billing.service.js';

class QuoteDto { @IsUUID() serviceId!: string; @IsOptional() @IsString() @MaxLength(40) promoCode?: string; }
class ClaimDto { @IsString() @MaxLength(40) code!: string; }
class TipDto { @IsInt() @Min(0) @Max(100_000_000) amount!: number; }
class CollectDto { @IsInt() @Min(1) @Max(1_000_000_000) amount!: number; }

const BILL_SQL = `SELECT cr.id AS request_id,cr.status,cr.requester_user_id,cr.service_minutes,
    i.subtotal AS gross_amount,i.discount_amount,i.total_amount AS amount_due,
    CASE i.status WHEN 'PARTIALLY_PAID' THEN 'PARTIAL' WHEN 'ISSUED' THEN 'DUE' ELSE i.status END AS payment_status,
    i.currency_code,cr.nurse_earning,cr.commission_bps_applied,i.surcharge_amount,i.distance_fee,i.tax_amount,
    i.tip_amount,cr.pricing->'fees'->>'taxLabel' AS tax_label,cr.promo_snapshot->>'code' AS promo_code,
    s.title_ar AS service_title,v.id AS visit_id,i.id AS invoice_id,i.invoice_number,i.issued_at,
    coalesce(i.paid_amount,0) AS collected
  FROM care_requests cr JOIN services s ON s.id=cr.service_id
  LEFT JOIN invoices i ON i.request_id=cr.id
  LEFT JOIN visits v ON v.id=i.visit_id
  LEFT JOIN request_assignments a ON a.id=v.assignment_id`;

function shape(r: any) {
  const due = Number(r.amount_due ?? 0), collected = Number(r.collected ?? 0);
  return {
    requestId: r.request_id, visitId: r.visit_id, invoiceId: r.invoice_id, invoiceNumber: r.invoice_number,
    status: r.status, serviceTitle: r.service_title, currency: r.currency_code,
    billed: r.amount_due != null, minutes: r.service_minutes, gross: Number(r.gross_amount ?? 0), discount: Number(r.discount_amount ?? 0),
    promoCode: r.promo_code, due, collected, paymentStatus: r.payment_status,
    surcharge: Number(r.surcharge_amount ?? 0), distanceFee: Number(r.distance_fee ?? 0), tax: Number(r.tax_amount ?? 0), taxLabel: r.tax_label ?? 'ضريبة',
    tip: Number(r.tip_amount ?? 0), payable: payableTotal(due, Number(r.tip_amount ?? 0)),
    remaining: Math.max(0, payableTotal(due, Number(r.tip_amount ?? 0)) - collected),
  };
}

@Controller('v1') @UseGuards(AuthGuard)
export class PricingController {
  constructor(private readonly db: DbService, private readonly promos: PromoService, private readonly fees: FeesService,
    private readonly billing: BillingService, private readonly autos: AutoDiscountService) {}

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
  @Post('requests/:id/tip') async tip(@Request() r: AuthRequest, @Param('id') id: string, @Body() dto: TipDto,
    @Headers('idempotency-key') key:string) {
    requireRole(r.user!, 'PATIENT');
    return this.db.transaction(async c => {
      if (!(await this.fees.row(c)).tips_enabled) conflict('TIPS_DISABLED');
      return this.billing.setTip(c,r.user!.id,id,dto.amount,key);
    });
  }

  /** The nurse records cash received. Short payment -> stays open with the remaining amount; excess -> change. */
  @Post('nurse/requests/:id/collect') async collect(@Request() r: AuthRequest, @Param('id') id: string,
    @Body() dto: CollectDto,@Headers('idempotency-key') key:string) {
    requireRole(r.user!, 'NURSE');
    return this.db.transaction(async c => {
      return this.billing.collectCash(c,r.user!.id,id,dto.amount,key);
    });
  }
}
