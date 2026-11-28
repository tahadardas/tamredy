import { FeatureCapabilitiesService } from '../capabilities/feature-capabilities.service.js';
import { cancelRequest, cancellationClassification } from './cancellation.service.js';
import type { CancelRequestDto } from './cancel-request.dto.js';
import { createHash } from 'node:crypto';
import { Injectable, Optional, ServiceUnavailableException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { CreateRequestDto } from '../common/dto.js';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import { PageArgs, makePage } from '../common/pagination.js';
import { PromoService, toRule } from '../pricing/promo.service.js';
import { FeesService } from '../pricing/fees.service.js';
import { AutoDiscountService } from '../pricing/auto-discounts.service.js';
import { PricingCompositionService } from '../pricing/pricing-composition.service.js';

import { saveSchedule, validateAppointment, verifyScheduledSafety } from '../scheduling/scheduling.js';
import { buildNotificationPayload } from '../notifications/notification-routing.js';
import { LiveLocationReadService } from '../live-location/live-location-read.service.js';

@Injectable()
export class RequestsService {
  constructor(
    private readonly db: DbService,
    private readonly promos: PromoService,
    private readonly fees: FeesService = new FeesService(),
    private readonly autos: AutoDiscountService = new AutoDiscountService(),
    private readonly pricingComposition: PricingCompositionService = new PricingCompositionService(promos, fees, autos),
    @Optional() private readonly liveLocationRead?: LiveLocationReadService,
    @Optional() private readonly capabilities: FeatureCapabilitiesService = new FeatureCapabilitiesService(db),
  ) {}
  async create(userId: string, dto: CreateRequestDto, key: string) {
    if (!key || key.length > 128) invalid('Idempotency-Key required, maximum 128 chars');
    if (!dto.nonEmergencyConfirmed) invalid('Emergency triage declaration is mandatory');
    const digest = createHash('sha256').update(JSON.stringify(dto)).digest('hex');
    return this.db.transaction(async client => {
      if (!(await client.query("SELECT id FROM users WHERE id=$1 AND status='ACTIVE' FOR SHARE", [userId])).rowCount) forbidden();
      await client.query(`INSERT INTO request_create_keys(user_id,key,request_hash) VALUES($1,$2,$3)
        ON CONFLICT (user_id,key) DO NOTHING`, [userId,key,digest]);
      const k = await client.query('SELECT * FROM request_create_keys WHERE user_id=$1 AND key=$2 FOR UPDATE',[userId,key]);
      if (k.rows[0].request_hash !== digest) conflict('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD');
      if (k.rows[0].request_id) {
        const replayed = await this.findOneWithRunner(client, userId, k.rows[0].request_id);
        return {
          ...replayed,
          clinicalApprovalStatus: replayed.clinical_approval_status,
          ...(replayed.scheduled_at ? { scheduledAt: replayed.scheduled_at } : {}),
          estimate: null,
          promoCode: null,
          replayed: true,
        };
      }
      const appointment = validateAppointment(dto.scheduledAt);
      if (dto.bookingMode === 'SCHEDULED' && !appointment) invalid('SCHEDULED_TIME_REQUIRED');
      if (dto.bookingMode !== undefined && dto.bookingMode !== 'SCHEDULED' && appointment) {
        invalid('SCHEDULED_TIME_REQUIRES_SCHEDULED_MODE');
      }
      if (dto.bookingMode !== 'OPEN' && (dto.openDurationMinutes !== undefined || dto.latestAcceptableArrivalAt)) {
        invalid('OPEN_MARKETPLACE_FIELDS_REQUIRE_OPEN_MODE');
      }
      this.capabilities.assertBookingMode(dto.bookingMode ?? (dto.scheduledAt ? 'SCHEDULED' : 'INSTANT'));
      await this.capabilities.assertAccepting(client);
      const beneficiary = await client.query(`SELECT id FROM beneficiaries WHERE id=$1 AND owner_user_id=$2 AND consent_status='GRANTED'`,[dto.beneficiaryId,userId]);
      if (!beneficiary.rowCount) forbidden();

      const composed = await this.pricingComposition.compose(client, {
        patientUserId: userId,
        items: dto.items,
        serviceIds: dto.serviceIds,
        serviceId: dto.serviceId,
        promoCode: dto.promoCode,
        consumePromoLock: true,
      });

      if (appointment) {
        for (const sid of composed.serviceIds) {
          await verifyScheduledSafety(client, sid, appointment);
        }
      }

      const {
        canonicalItems,
        primaryService,
        combinedPricingRule: combinedRule,
        totalBasePrice,
        combinedCommissionBps,
        promo,
        autoDiscount: auto,
        feeSnapshot,
        clinicalRequirements,
        currencyCode,
        estimate,
      } = composed;
      const primaryServiceId = primaryService.id;
      const needsClinicalApproval = clinicalRequirements.requiresPrescription || clinicalRequirements.requiresClinicalReview;

      const isOpenMode = dto.bookingMode === 'OPEN';
      const bookingMode = isOpenMode ? 'OPEN' : (appointment ? 'SCHEDULED' : 'INSTANT');
      let initialStatus = 'OFFERING';
      if (isOpenMode) initialStatus = 'OPEN_FOR_PROPOSALS';
      else if (appointment) initialStatus = 'SCHEDULED';

      const now = new Date();
      const openDurationMins = dto.openDurationMinutes ?? 120;
      const openExpiresAt = isOpenMode && !needsClinicalApproval
        ? new Date(now.getTime() + openDurationMins * 60000)
        : null;
      const latestArrivalAt = isOpenMode
        ? (dto.latestAcceptableArrivalAt ? new Date(dto.latestAcceptableArrivalAt) : new Date(now.getTime() + (openDurationMins + 60) * 60000))
        : null;

      const areaId = (await client.query(`SELECT a.id FROM areas a
        WHERE a.active AND a.lat IS NOT NULL AND a.lng IS NOT NULL
        ORDER BY ST_SetSRID(ST_MakePoint($1,$2),4326)::geography
          <-> ST_SetSRID(ST_MakePoint(a.lng,a.lat),4326)::geography
        LIMIT 1`, [dto.longitude, dto.latitude])).rows[0]?.id ?? null;

      const r = await client.query(`INSERT INTO care_requests(
        requester_user_id, beneficiary_id, service_id, location, location_source, address_text,
        status, price_amount, currency_code, commission_bps, pricing, promo_id, promo_snapshot,
        booking_mode, original_booking_mode, marketplace_status, published_at, open_expires_at,
        latest_acceptable_arrival_at, area_id, clinical_approval_status, open_duration_minutes, original_latest_acceptable_arrival_at
      )
      VALUES($1,$2,$3,ST_SetSRID(ST_MakePoint($4,$5),4326)::geography,$6,$7,$14,$8,$9,$10,$11::jsonb,$12,$13::jsonb,$15,$15,$16,$17,$18,$19,$20,$21,$22,$19)
      RETURNING id,status,version,price_amount,currency_code,booking_mode,open_expires_at,latest_acceptable_arrival_at`,[
        userId,dto.beneficiaryId,primaryServiceId,dto.longitude,dto.latitude,dto.locationSource,dto.addressText,totalBasePrice,currencyCode,combinedCommissionBps,
        JSON.stringify({...combinedRule,fees:feeSnapshot}),promo?.id??null,promo?JSON.stringify(toRule(promo)):auto?JSON.stringify(auto):null, initialStatus,
        bookingMode, isOpenMode ? 'OPEN_FOR_PROPOSALS' : (appointment ? 'INITIAL' : 'SEARCHING'),
        isOpenMode && !needsClinicalApproval ? now.toISOString() : null, openExpiresAt?.toISOString() ?? null,
        latestArrivalAt?.toISOString() ?? null, areaId, needsClinicalApproval ? 'PENDING' : 'NOT_REQUIRED', openDurationMins
      ]);
      const request = r.rows[0];

      // Save care_request_items snapshot for all selected services
      for (const it of canonicalItems) {
        const s = it.row;
        await client.query(`
          INSERT INTO care_request_items(
            request_id, service_id, quantity, unit_price, expected_minutes,
            pricing_snapshot, clinical_requirements_snapshot
          )
          VALUES($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)
        `, [
          request.id,
          it.serviceId,
          it.quantity,
          it.unitPrice,
          it.expectedMinutes,
          JSON.stringify({
            basePrice: s.price_amount,
            currency: s.currency_code,
            includedMinutes: s.included_minutes,
            blockMinutes: s.block_minutes,
            blockPrice: s.block_price,
          }),
          JSON.stringify({
            requiresPrescription: s.requires_prescription,
            requiresClinicalReview: s.requires_clinical_review,
            requiredSkills: s.required_skills,
            riskClassification: s.risk_classification,
          }),
        ]);
      }
      await client.query('UPDATE request_create_keys SET request_id=$1 WHERE user_id=$2 AND key=$3',[request.id,userId,key]);

      if (needsClinicalApproval) {
        await client.query(`INSERT INTO request_clinical_reviews(
          request_id,required_prescription,required_clinical_review
        ) VALUES($1,$2,$3)`, [
          request.id,
          clinicalRequirements.requiresPrescription,
          clinicalRequirements.requiresClinicalReview,
        ]);
        if (appointment) await saveSchedule(client,request.id,appointment);
      }

      if (isOpenMode && !needsClinicalApproval) {
        await client.query(
          `INSERT INTO outbox_events(event_type, aggregate_id, payload)
           VALUES('marketplace.request.published', $1, $2::jsonb)`,
          [
            request.id,
            JSON.stringify(buildNotificationPayload({
              eventType: 'marketplace.request.published',
              recipientUserId: userId,
              recipientRole: 'PATIENT',
              targetApp: 'PATIENT_APP',
              requestId: request.id,
              entityVersion: request.version,
              expiresAt: openExpiresAt?.toISOString() ?? null,
              skipPush: true,
              extra: { openExpiresAt },
            })),
          ],
        );
        await client.query('INSERT INTO request_events(request_id,actor_user_id,event_type) VALUES($1,$2,$3)',[request.id,userId,'marketplace.request.published']);
      } else if (!needsClinicalApproval) {
        const policy = (await client.query("SELECT value FROM app_settings WHERE key='dispatch'")).rows[0]?.value;
        if (!appointment && process.env.OPEN_DISPATCH_ENABLED === 'true' && policy?.openEnabled === true) {
          const search = await client.query(`UPDATE care_requests SET
            search_started_at=statement_timestamp(),
            search_expires_at=statement_timestamp()+$2::integer*interval '1 second',
            search_radius_meters=$3,
            search_max_heartbeat_seconds=$4, search_max_location_seconds=$5, search_max_accuracy_meters=$6
            WHERE id=$1 RETURNING search_started_at, search_expires_at`,
          [request.id, policy.offerDurationSeconds ?? 60, policy.radiusMeters ?? 10000,
            policy.maxHeartbeatAgeSeconds ?? 60, policy.maxLocationAgeSeconds ?? 120,
            policy.maxLocationAccuracyMeters ?? 100]);
          Object.assign(request, search.rows[0]);
        }
        if (appointment) await saveSchedule(client, request.id, appointment);
        else await client.query('INSERT INTO dispatch_jobs(request_id) VALUES($1)',[request.id]);
        await client.query('INSERT INTO request_events(request_id,actor_user_id,event_type) VALUES($1,$2,$3)',[request.id,userId,'request.created']);
        await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('request.created',$1,$2::jsonb)`,[
          request.id,
          JSON.stringify(buildNotificationPayload({
            eventType: 'request.created',
            recipientUserId: userId,
            recipientRole: 'PATIENT',
            targetApp: 'PATIENT_APP',
            requestId: request.id,
            entityVersion: request.version,
          })),
        ]);
      }
      const canonical = await this.findOneWithRunner(client, userId, request.id);
      return {
        ...canonical,
        clinicalApprovalStatus: needsClinicalApproval ? 'PENDING' : 'NOT_REQUIRED',
        ...(appointment ? { scheduledAt: appointment.toISOString() } : {}),
        estimate,
        promoCode: promo?.code ?? auto?.label ?? null,
        replayed: false,
      };
    });
  }
  async findOne(userId: string, requestId: string) {
    return this.findOneWithRunner(this.db, userId, requestId);
  }
  async findOneWithRunner(
    q: { query: (sql: string, params?: unknown[]) => Promise<{ rows: any[]; rowCount: number | null }> },
    userId: string,
    requestId: string,
  ) {
    const found = await q.query(`SELECT cr.id,cr.requester_user_id,cr.beneficiary_id,cr.service_id,cr.status,cr.version,cr.price_amount,cr.currency_code,cr.created_at,
       cr.booking_mode, cr.marketplace_status, cr.published_at, cr.open_expires_at, cr.latest_acceptable_arrival_at,cr.clinical_approval_status,
       cr.address_text, cr.payment_status, cr.amount_due, cr.tip_amount, cr.search_expires_at,
       v.outcome AS visit_outcome, a.reason AS visit_outcome_reason,
       s.title_ar AS service_title, b.display_name AS beneficiary_name,
       sv.appointment_at AS scheduled_at,
       a.id AS assignment_id, a.nurse_id AS assigned_nurse_id,
       CASE WHEN cr.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE','COMPLETED') THEN u.display_name END AS nurse_name,
       (SELECT count(*)::int FROM marketplace_proposals mp WHERE mp.request_id = cr.id AND mp.status = 'PENDING' AND mp.expires_at > now()) AS active_proposals_count
       FROM care_requests cr
       JOIN services s ON s.id = cr.service_id
       JOIN beneficiaries b ON b.id = cr.beneficiary_id
       LEFT JOIN scheduled_visits sv ON sv.request_id = cr.id
       LEFT JOIN request_assignments a ON a.request_id = cr.id AND a.status IN ('RESERVED','ACTIVE','RELEASED')
       LEFT JOIN visits v ON v.assignment_id=a.id
       LEFT JOIN nurses n ON n.id = a.nurse_id
       LEFT JOIN users u ON u.id = n.user_id
       WHERE cr.id=$1 AND cr.requester_user_id=$2
       ORDER BY a.accepted_at DESC NULLS LAST LIMIT 1`,[requestId,userId]);
    if(!found.rowCount) missing();
    const items = await q.query(`
      SELECT cri.id, cri.service_id, cri.quantity, cri.unit_price, cri.expected_minutes,
             cri.item_status, s.title_ar, s.code, s.requires_prescription
      FROM care_request_items cri
      JOIN services s ON s.id=cri.service_id
      WHERE cri.request_id=$1
      ORDER BY cri.created_at ASC
    `, [requestId]);
    return { ...found.rows[0], items: items.rows };
  }
  async list(userId: string, page: PageArgs) {
    // One joined query for request + service + beneficiary + winning assignment.
    // A correlated lookup per row would be a N+1 anti-pattern.
    const result = await this.db.query(`SELECT cr.id,cr.status,cr.price_amount,cr.currency_code,cr.clinical_approval_status,
      cr.created_at,cr.version,cr.payment_status,cr.amount_due,cr.tip_amount,
      (SELECT v.outcome FROM visits v JOIN request_assignments va ON va.id=v.assignment_id WHERE va.request_id=cr.id ORDER BY v.completed_at DESC NULLS LAST LIMIT 1) AS visit_outcome,
      cr.booking_mode, cr.marketplace_status, cr.open_expires_at, cr.latest_acceptable_arrival_at,
      sv.appointment_at AS scheduled_at,
      (SELECT count(*)::int FROM marketplace_proposals mp WHERE mp.request_id = cr.id AND mp.status = 'PENDING') AS active_proposals_count,
      to_char(cr.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_created_at,
      s.title_ar AS service_title,b.display_name AS beneficiary_name,
      a.nurse_id AS assigned_nurse_id
      FROM care_requests cr
      JOIN services s ON s.id=cr.service_id
      JOIN beneficiaries b ON b.id=cr.beneficiary_id
      LEFT JOIN scheduled_visits sv ON sv.request_id=cr.id
      LEFT JOIN request_assignments a ON a.request_id=cr.id AND a.status='ACTIVE'
      WHERE cr.requester_user_id=$1
        AND ($2::timestamptz IS NULL OR (cr.created_at,cr.id)<($2::timestamptz,$3::uuid))
      ORDER BY cr.created_at DESC,cr.id DESC LIMIT $4`,
      [userId,page.cursor?.at??null,page.cursor?.id??null,page.limit+1]);
    return makePage(result.rows,page.limit,`patient:${userId}`);
  }
  async cancellationPolicy(userId: string, requestId: string) {
    const row = (await this.db.query(`SELECT r.status,r.version,a.departed_at IS NOT NULL AS departed,
      a.eta_status='AVAILABLE' AS eta_available,
      statement_timestamp()>=a.expected_arrival_at+interval '30 minutes' AS threshold_met
      FROM care_requests r LEFT JOIN request_assignments a ON a.request_id=r.id AND a.status='ACTIVE'
      WHERE r.id=$1 AND r.requester_user_id=$2`,[requestId,userId])).rows[0];
    if (!row) missing();
    const canCancel = [
      'REQUESTED',
      'SCHEDULED',
      'OFFERING',
      'AWAITING_RECOVERY_CHOICE',
      'OPEN_FOR_PROPOSALS',
      'ASSIGNED',
      'EN_ROUTE',
      'UNFULFILLED',
    ].includes(row.status);
    const classification = canCancel ? cancellationClassification({
      status: row.status, departed: row.departed,
      etaAvailable: row.eta_available === true, thresholdMet: row.threshold_met === true,
    },false) : null;
    return { canCancel, status: row.status, version: row.version, classification,
      requiresAcknowledgement: classification === 'EN_ROUTE_COUNTED' };
  }
  async cancel(userId: string, requestId: string, dto: CancelRequestDto = {}) {
    return this.db.transaction(client => cancelRequest(client, userId, requestId, dto));
  }
  async track(userId:string, requestId:string) {
    const r=await this.db.query(`SELECT a.nurse_id,cr.id,cr.status,cr.version,cr.booking_mode,cr.clinical_approval_status,
      cr.search_max_location_seconds,cr.search_max_accuracy_meters,
      ST_Y(cr.location::geometry) AS patient_lat,ST_X(cr.location::geometry) AS patient_lng,
      CASE WHEN cr.status='EN_ROUTE' AND least(nl.captured_at,nl.received_at) > now() - coalesce(cr.search_max_location_seconds,120)*interval '1 second' AND nl.accuracy_m<=coalesce(cr.search_max_accuracy_meters,100) THEN ST_Y(nl.location::geometry) END AS nurse_lat,
      CASE WHEN cr.status='EN_ROUTE' AND least(nl.captured_at,nl.received_at) > now() - coalesce(cr.search_max_location_seconds,120)*interval '1 second' AND nl.accuracy_m<=coalesce(cr.search_max_accuracy_meters,100) THEN ST_X(nl.location::geometry) END AS nurse_lng,
      CASE WHEN cr.status='EN_ROUTE' THEN nl.recorded_at END AS location_at,
      nl.captured_at AS location_captured_at,nl.received_at AS location_received_at,
      nl.accuracy_m AS location_accuracy_m,nl.session_id AS location_session_id
      FROM care_requests cr LEFT JOIN request_assignments a ON a.request_id=cr.id AND a.status='ACTIVE'
      LEFT JOIN nurse_locations nl ON nl.nurse_id=a.nurse_id
      WHERE cr.id=$1 AND cr.requester_user_id=$2`,[requestId,userId]);
    if(!r.rowCount) missing();
    const { nurse_id: nurseId, search_max_location_seconds: maxLocAgeSec, search_max_accuracy_meters:maxAccuracy, ...row } = r.rows[0];
    row.location_freshness='unavailable';
    row.location_source=null;
    if (nurseId && row.status==='EN_ROUTE' && this.liveLocationRead) {
      // Clearing first prevents a Redis read failure from silently revealing a stale checkpoint.
      row.nurse_lat=null;row.nurse_lng=null;row.location_at=null;
      const liveLoc=await this.liveLocationRead.getNurseLocation(nurseId).catch(()=>null);
      if (liveLoc) {
        row.location_captured_at=liveLoc.capturedAt;
        row.location_received_at=liveLoc.recordedAt;
        row.location_accuracy_m=liveLoc.accuracyMeters;
        row.location_session_id=liveLoc.sessionId;
        row.location_source=liveLoc.source;
        const fresh=Date.now()-Math.min(liveLoc.capturedAt.getTime(),liveLoc.recordedAt.getTime())
          <=Number(maxLocAgeSec??120)*1000 && liveLoc.accuracyMeters<=Number(maxAccuracy??100);
        row.location_freshness=fresh?'fresh':'stale';
        if (fresh) {row.nurse_lat=liveLoc.latitude;row.nurse_lng=liveLoc.longitude;row.location_at=liveLoc.recordedAt;}
      }
    } else if (row.status==='EN_ROUTE') {
      row.location_source='postgres';
      row.location_freshness=row.nurse_lat!=null?'fresh':'stale';
    } else {
      row.location_captured_at=null;row.location_received_at=null;row.location_accuracy_m=null;row.location_session_id=null;
    }
    Object.assign(row,{locationCapturedAt:row.location_captured_at,locationReceivedAt:row.location_received_at,
      locationAccuracy:row.location_accuracy_m,locationFreshness:row.location_freshness,
      locationSource:row.location_source,locationSessionId:row.location_session_id});
    // "Top nurse" badge shown to the patient (marketing feature, switched on/off from the dashboard).
    let badge: { badge: boolean; rating: number; reviews: number } | null = null;
    if (nurseId) {
      const f = (await this.db.query(`SELECT enabled,config FROM marketing_features WHERE key='badge'`)).rows[0];
      if (f?.enabled) {
        const rep = await this.fees.reputation(this.db, nurseId);
        badge = { badge: rep.reviews >= Number(f.config.minReviews) && rep.reputation >= Number(f.config.minReputation), rating: Math.round(rep.reputation * 10) / 10, reviews: rep.reviews };
      }
    }
    return { ...row, nurseBadge: badge };
  }
}
