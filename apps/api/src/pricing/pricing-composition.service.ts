import { Injectable } from '@nestjs/common';
import { assertCashCurrency } from './cash-currency.js';
import { invalid } from '../common/errors.js';
import { AutoDiscountService, type AutoDiscount } from './auto-discounts.service.js';
import { FeesService, type Q } from './fees.service.js';
import { estimateV2, ruleFromRow, type FeeSettings, type PricingRule } from './pricing.js';
import { PromoService, toRule, type PromoRow } from './promo.service.js';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface ComposePricingInput {
  patientUserId: string;
  items?: Array<{ serviceId?: string; quantity?: unknown }>;
  serviceIds?: string[];
  serviceId?: string;
  promoCode?: string | null;
  consumePromoLock?: boolean;
}

export interface CanonicalPricingItem {
  serviceId: string;
  code: string;
  titleAr: string;
  quantity: number;
  unitPrice: number;
  subtotal: number;
  expectedMinutes: number;
  row: Record<string, any>;
}

export interface PricingCompositionResult {
  canonicalItems: CanonicalPricingItem[];
  serviceIds: string[];
  primaryService: Record<string, any>;
  currencyCode: string;
  combinedPricingRule: PricingRule;
  totalBasePrice: number;
  totalExpectedMinutes: number;
  includedMinutes: number;
  combinedCommissionBps: number;
  promo: PromoRow | null;
  autoDiscount: AutoDiscount | null;
  feeSnapshot: FeeSettings;
  estimate: ReturnType<typeof estimateV2> & { promoCode: string | null; autoDiscount: string | null; discount: number };
  clinicalRequirements: {
    requiresPrescription: boolean;
    requiresClinicalReview: boolean;
    requiredSkills: string[];
  };
  pricingVersion: number;
}

/**
 * BUG-007 / BUG-008: Single canonical pricing composition engine shared across
 * Catalog Estimate, Pricing Quote, and Request Creation so estimates, fees,
 * personal promos, auto-discounts, includedMinutes, and currency rules always match.
 */
@Injectable()
export class PricingCompositionService {
  constructor(
    private readonly promos: PromoService,
    private readonly fees: FeesService = new FeesService(),
    private readonly autos: AutoDiscountService = new AutoDiscountService(),
  ) {}

  async compose(q: Q, input: ComposePricingInput): Promise<PricingCompositionResult> {
    if (!input.patientUserId || input.patientUserId === 'anonymous' || !UUID_RE.test(input.patientUserId)) {
      invalid('AUTHENTICATED_PATIENT_REQUIRED');
    }

    const rawItems: { serviceId: string; quantity: number }[] = [];
    if (Array.isArray(input.items) && input.items.length > 0) {
      for (const it of input.items) {
        if (!it?.serviceId) continue;
        const qty = Number(it.quantity ?? 1);
        if (!Number.isInteger(qty) || qty < 1 || qty > 10) {
          invalid('INVALID_SERVICE_QUANTITY');
        }
        rawItems.push({ serviceId: it.serviceId, quantity: qty });
      }
    } else if (Array.isArray(input.serviceIds) && input.serviceIds.length > 0) {
      for (const sid of input.serviceIds) {
        if (sid) rawItems.push({ serviceId: sid, quantity: 1 });
      }
    } else if (input.serviceId) {
      rawItems.push({ serviceId: input.serviceId, quantity: 1 });
    }

    if (rawItems.length === 0) invalid('At least one service must be selected');

    const mergedItems = new Map<string, number>();
    for (const item of rawItems) {
      if (!UUID_RE.test(item.serviceId)) invalid('INVALID_SERVICE_ID');
      const quantity = (mergedItems.get(item.serviceId) ?? 0) + item.quantity;
      if (quantity > 10) invalid('SERVICE_QUANTITY_LIMIT_EXCEEDED');
      mergedItems.set(item.serviceId, quantity);
    }
    if (mergedItems.size > 10) invalid('REQUEST_ITEM_LIMIT_EXCEEDED');

    const serviceIds = [...mergedItems.keys()];
    const servicesRes = await q.query(
      `SELECT * FROM services WHERE id = ANY($1::uuid[]) AND active = true AND dispatch_approved = true`,
      [serviceIds],
    );
    if (servicesRes.rowCount !== serviceIds.length) {
      invalid('One or more selected services are unavailable or not clinically approved');
    }
    if (new Set(servicesRes.rows.map(row => row.currency_code)).size !== 1) {
      invalid('REQUEST_ITEMS_REQUIRE_SINGLE_CURRENCY');
    }
    for (const service of servicesRes.rows) assertCashCurrency(service.currency_code);

    const serviceMap = new Map(servicesRes.rows.map(r => [r.id, r]));
    const requiredSkills = new Set<string>();
    let requiresPrescription = false;
    let requiresClinicalReview = false;
    let totalBasePrice = 0;
    let totalExpectedMinutes = 0;
    let totalIncludedMinutes = 0;
    let weightedCommission = 0;

    const canonicalItems: CanonicalPricingItem[] = [];
    for (const [serviceId, quantity] of mergedItems.entries()) {
      const s = serviceMap.get(serviceId)!;
      const rule = ruleFromRow(s);
      const unitPrice = Number(s.price_amount);
      const subtotal = unitPrice * quantity;
      const expectedMinutes = (Number(s.expected_minutes) || 30) * quantity;
      totalBasePrice += subtotal;
      totalExpectedMinutes += expectedMinutes;
      totalIncludedMinutes += rule.includedMinutes * quantity;
      weightedCommission += subtotal * Number(s.commission_bps ?? 2000);
      if (s.requires_prescription) requiresPrescription = true;
      if (s.requires_clinical_review) requiresClinicalReview = true;
      if (Array.isArray(s.required_skills)) {
        for (const sk of s.required_skills) requiredSkills.add(String(sk));
      }
      canonicalItems.push({
        serviceId: s.id,
        code: s.code,
        titleAr: s.title_ar,
        quantity,
        unitPrice,
        subtotal,
        expectedMinutes,
        row: s,
      });
    }

    const primaryService = servicesRes.rows.reduce(
      (prev, curr) => (Number(curr.price_amount) > Number(prev.price_amount) ? curr : prev),
      servicesRes.rows[0],
    );
    const baseRule = ruleFromRow(primaryService);
    const combinedPricingRule: PricingRule = {
      ...baseRule,
      basePrice: totalBasePrice,
      includedMinutes: Math.max(1, totalIncludedMinutes),
      expectedMinutes: totalExpectedMinutes,
    };

    const feeSnapshot = await this.fees.snapshot(q);
    // Do NOT swallow invalid promo codes or pass 'anonymous'; promos fail explicitly with PROMO_* errors.
    const promo = await this.promos.resolve(
      q,
      input.patientUserId,
      primaryService.id,
      combinedPricingRule.basePrice,
      input.promoCode,
      Boolean(input.consumePromoLock),
    );
    const autoDiscount = promo ? null : await this.autos.pick(q, input.patientUserId);
    const activeDiscount = promo ? toRule(promo) : autoDiscount;
    const est = estimateV2(combinedPricingRule, activeDiscount, feeSnapshot);

    const promoCodeApplied = promo?.code ?? autoDiscount?.label ?? null;
    const discountAmount = Math.max(0, est.expected - (estimateV2(combinedPricingRule, null, feeSnapshot).expected));
    const expectedSavings = Math.max(
      0,
      estimateV2(combinedPricingRule, null, feeSnapshot).expected - est.expected,
    );

    return {
      canonicalItems,
      serviceIds,
      primaryService,
      currencyCode: primaryService.currency_code,
      combinedPricingRule,
      totalBasePrice,
      totalExpectedMinutes,
      includedMinutes: combinedPricingRule.includedMinutes,
      combinedCommissionBps: totalBasePrice > 0 ? Math.round(weightedCommission / totalBasePrice) : 0,
      promo,
      autoDiscount,
      feeSnapshot,
      estimate: {
        ...est,
        promoCode: promoCodeApplied,
        autoDiscount: autoDiscount ? autoDiscount.kind : null,
        discount: Math.max(0, expectedSavings),
      },
      clinicalRequirements: {
        requiresPrescription,
        requiresClinicalReview,
        requiredSkills: Array.from(requiredSkills),
      },
      pricingVersion: 2,
    };
  }
}
