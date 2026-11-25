import { Body, Controller, Get, Post, Query, Request, UseGuards } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { ReferenceCacheService } from '../cache/reference-cache.service.js';
import { FeesService } from '../pricing/fees.service.js';
import { PromoService, toRule } from '../pricing/promo.service.js';
import { estimateV2, ruleFromRow } from '../pricing/pricing.js';
import { invalid } from '../common/errors.js';

interface EstimateItemDto {
  serviceId: string;
  quantity?: number;
}

interface MultiServiceEstimateDto {
  serviceIds?: string[];
  items?: EstimateItemDto[];
  promoCode?: string;
}

@Controller('v1')
export class CatalogController {
  constructor(
    private readonly db: DbService,
    private readonly cache: ReferenceCacheService,
    private readonly fees: FeesService = new FeesService(),
    private readonly promos: PromoService = new PromoService(db),
  ) {}

  /** Service categories: visible to all users */
  @Get('categories')
  async categories() {
    return this.cache.getOrLoad('catalog:categories', async () =>
      (await this.db.query(`
        SELECT id, code, title_ar, title_en, description_ar, icon, sort_order, active
        FROM service_categories
        WHERE active = true
        ORDER BY sort_order ASC, title_ar ASC
      `)).rows, 300);
  }

  /** Public catalog endpoint: visible to patients before and after login */
  @Get('services')
  async services(@Query('category') categoryFilter?: string, @Query('q') searchValue?: string) {
    const search = searchValue?.trim().slice(0, 80) || undefined;
    const fetchServices = async (cat?: string, querySearch?: string) => {
      let query = `
        SELECT s.id, s.code, s.category_id, sc.code AS category_code, sc.title_ar AS category_title_ar,
               s.title_ar, s.title_en, s.description_ar, s.price_amount, s.currency_code,
               s.included_minutes, s.block_minutes, s.block_price, s.expected_minutes,
               s.requires_prescription, s.requires_clinical_review, s.required_skills,
               s.consumables_included, s.night_availability, s.scheduling_allowed,
               s.recurring_visits_allowed, s.risk_classification, s.active, s.dispatch_approved, s.sort_order
        FROM services s
        LEFT JOIN service_categories sc ON sc.id = s.category_id
        WHERE s.active = true AND s.dispatch_approved = true
      `;
      const params: unknown[] = [];
      if (cat) {
        params.push(cat);
        query += ` AND (sc.code = $1 OR sc.id::text = $1 OR s.category_id::text = $1)`;
      }
      if (querySearch) {
        params.push(querySearch);
        query += ` AND (tamreedy_ar_normalize(s.title_ar) % tamreedy_ar_normalize($${params.length})
          OR tamreedy_ar_normalize(s.title_ar) LIKE tamreedy_ar_normalize($${params.length})||'%'
          OR tamreedy_ar_normalize(s.description_ar) % tamreedy_ar_normalize($${params.length}))`;
      }
      query += ` ORDER BY ${querySearch ? `similarity(tamreedy_ar_normalize(s.title_ar),tamreedy_ar_normalize($${params.length})) DESC,` : ''}
        sc.sort_order ASC NULLS LAST, s.sort_order ASC, s.title_ar ASC, s.id ASC`;
      return (await this.db.query(query, params)).rows;
    };

    if (search) {
      return fetchServices(categoryFilter, search);
    }
    if (categoryFilter) {
      return this.cache.getOrLoad(`services:public:${categoryFilter}`, () => fetchServices(categoryFilter), 300);
    }
    return this.cache.getOrLoad('services:public', () => fetchServices(), 300);
  }

  /** Multi-service estimate calculator: computes combined duration, items, base pricing, and fees */
  @Post('catalog/estimate')
  async estimateServices(@Body() body: MultiServiceEstimateDto) {
    const rawItems: { serviceId: string; quantity: number }[] = [];
    if (Array.isArray(body.items) && body.items.length > 0) {
      for (const it of body.items) {
        if (it.serviceId) rawItems.push({ serviceId: it.serviceId, quantity: Math.max(1, Number(it.quantity) || 1) });
      }
    } else if (Array.isArray(body.serviceIds) && body.serviceIds.length > 0) {
      for (const sid of body.serviceIds) {
        if (sid) rawItems.push({ serviceId: sid, quantity: 1 });
      }
    }

    if (rawItems.length === 0) {
      invalid('At least one serviceId must be provided');
    }

    const uniqueIds = [...new Set(rawItems.map(i => i.serviceId))];
    const servicesRes = await this.db.query(
      `SELECT * FROM services WHERE id = ANY($1::uuid[]) AND active = true AND dispatch_approved = true`,
      [uniqueIds]
    );

    if (servicesRes.rowCount !== uniqueIds.length) {
      invalid('One or more selected services are unavailable');
    }

    const serviceMap = new Map(servicesRes.rows.map(r => [r.id, r]));
    let totalBasePrice = 0;
    let totalExpectedMinutes = 0;
    const requiredSkills = new Set<string>();
    let requiresPrescription = false;
    let requiresClinicalReview = false;

    const breakdown = rawItems.map(it => {
      const s = serviceMap.get(it.serviceId)!;
      const unitPrice = Number(s.price_amount);
      const subtotal = unitPrice * it.quantity;
      const expectedMinutes = (Number(s.expected_minutes) || 30) * it.quantity;
      totalBasePrice += subtotal;
      totalExpectedMinutes += expectedMinutes;
      if (s.requires_prescription) requiresPrescription = true;
      if (s.requires_clinical_review) requiresClinicalReview = true;
      if (Array.isArray(s.required_skills)) {
        for (const sk of s.required_skills) requiredSkills.add(sk);
      }
      return {
        serviceId: s.id,
        code: s.code,
        titleAr: s.title_ar,
        quantity: it.quantity,
        unitPrice,
        subtotal,
        expectedMinutes,
      };
    });

    const primaryService = servicesRes.rows.reduce((prev, curr) =>
      Number(curr.price_amount) > Number(prev.price_amount) ? curr : prev
    , servicesRes.rows[0]);

    const combinedRule = {
      ...ruleFromRow(primaryService),
      basePrice: totalBasePrice,
      expectedMinutes: totalExpectedMinutes,
    };

    const feeSnapshot = await this.fees.snapshot(this.db);
    const promo = body.promoCode ? await this.promos.resolve(this.db, 'anonymous', primaryService.id, totalBasePrice, body.promoCode, false).catch(() => null) : null;
    const est = estimateV2(combinedRule, promo ? toRule(promo) : null, feeSnapshot);

    return {
      breakdown,
      totalBasePrice,
      totalExpectedMinutes,
      currencyCode: primaryService.currency_code ?? 'SYP_NEW',
      requiresPrescription,
      requiresClinicalReview,
      requiredSkills: Array.from(requiredSkills),
      estimate: est,
      singleTravelFeeGuaranteed: true,
    };
  }

  /** Beneficiaries requires patient authentication */
  @Get('beneficiaries/mine')
  @UseGuards(AuthGuard)
  async beneficiaries(@Request() r: AuthRequest) {
    requireRole(r.user!, 'PATIENT');
    return (await this.db.query(
      `SELECT id, display_name FROM beneficiaries WHERE owner_user_id = $1 AND consent_status = 'GRANTED' ORDER BY created_at DESC`,
      [r.user!.id],
    )).rows;
  }
}
