import { cancelRequest, cancellationClassification } from './cancellation.service.js';
import type { CancelRequestDto } from './cancel-request.dto.js';
import { createHash } from 'node:crypto';
import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { CreateRequestDto } from '../common/dto.js';
import { conflict, forbidden, invalid, missing } from '../common/errors.js';
import { PageArgs, makePage } from '../common/pagination.js';
import { PromoService, toRule } from '../pricing/promo.service.js';
import { estimateV2, ruleFromRow } from '../pricing/pricing.js';
import { FeesService } from '../pricing/fees.service.js';
import { AutoDiscountService } from '../pricing/auto-discounts.service.js';

@Injectable()
export class RequestsService {
  constructor(private readonly db: DbService, private readonly promos: PromoService, private readonly fees: FeesService = new FeesService(), private readonly autos: AutoDiscountService = new AutoDiscountService()) {}
  async create(userId: string, dto: CreateRequestDto, key: string) {
    if (!key || key.length > 128) invalid('Idempotency-Key required, maximum 128 chars');
    if (!dto.nonEmergencyConfirmed) invalid('Emergency triage declaration is mandatory');
    const digest = createHash('sha256').update(JSON.stringify(dto)).digest('hex');
    return this.db.transaction(async client => {
      await client.query(`INSERT INTO request_create_keys(user_id,key,request_hash) VALUES($1,$2,$3)
        ON CONFLICT (user_id,key) DO NOTHING`, [userId,key,digest]);
      const k = await client.query('SELECT * FROM request_create_keys WHERE user_id=$1 AND key=$2 FOR UPDATE',[userId,key]);
      if (k.rows[0].request_hash !== digest) conflict('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD');
      if (k.rows[0].request_id) return this.findOne(userId, k.rows[0].request_id);
      const orders = (await client.query(`SELECT value FROM app_settings WHERE key='orders'`)).rows[0]?.value;
      if (orders && orders.accepting === false) throw new ServiceUnavailableException({ code: 'ORDERS_PAUSED', message: orders.pausedMessage ?? '' });
      const beneficiary = await client.query(`SELECT id FROM beneficiaries WHERE id=$1 AND owner_user_id=$2 AND consent_status='GRANTED'`,[dto.beneficiaryId,userId]);
      if (!beneficiary.rowCount) forbidden();
      const service = await client.query(`SELECT * FROM services WHERE id=$1 AND active=true AND dispatch_approved=true`,[dto.serviceId]);
      if (!service.rowCount) invalid('Service unavailable or not clinically approved');
      const s=service.rows[0];
      if (s.requires_prescription && !dto.prescriptionConfirmed) {
        invalid('PRESCRIPTION_CONFIRMATION_REQUIRED: Medical prescription verification is mandatory for this service');
      }
      const rule=ruleFromRow(s);
      const feeSnapshot=await this.fees.snapshot(client); // night/holiday/distance/tax rules frozen for this order
      // Explicit code must be valid; otherwise a claimed welcome code is applied silently. Row is locked against over-use.
      const promo=await this.promos.resolve(client,userId,dto.serviceId,rule.basePrice,dto.promoCode,true);
      // No code used -> the best automatic discount (off-peak / loyalty / visit pack), if any feature is switched on.
      const auto=promo?null:await this.autos.pick(client,userId);
      const r = await client.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,pricing,promo_id,promo_snapshot)
        VALUES($1,$2,$3,ST_SetSRID(ST_MakePoint($4,$5),4326)::geography,$6,$7,'OFFERING',$8,$9,$10,$11::jsonb,$12,$13::jsonb)
        RETURNING id,status,version,price_amount,currency_code`,[
        userId,dto.beneficiaryId,dto.serviceId,dto.longitude,dto.latitude,dto.locationSource,dto.addressText,s.price_amount,s.currency_code,s.commission_bps,
        JSON.stringify({...rule,fees:feeSnapshot}),promo?.id??null,promo?JSON.stringify(toRule(promo)):auto?JSON.stringify(auto):null
      ]);
      const request = r.rows[0];
      await client.query('UPDATE request_create_keys SET request_id=$1 WHERE user_id=$2 AND key=$3',[request.id,userId,key]);
      const policy = (await client.query("SELECT value FROM app_settings WHERE key='dispatch'")).rows[0]?.value;
      if (process.env.OPEN_DISPATCH_ENABLED === 'true' && policy?.openEnabled === true) {
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
      await client.query('INSERT INTO dispatch_jobs(request_id) VALUES($1)',[request.id]);
      await client.query('INSERT INTO request_events(request_id,actor_user_id,event_type) VALUES($1,$2,$3)',[request.id,userId,'request.created']);
      await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('request.created',$1,$2::jsonb)`,[request.id,JSON.stringify({recipientUserId:userId,requestId:request.id})]);
      return {...request,estimate:estimateV2(rule,promo?toRule(promo):auto,feeSnapshot),promoCode:promo?.code??auto?.label??null};
    });
  }
  async findOne(userId: string, requestId: string) {
    const found = await this.db.query(`SELECT id,requester_user_id,beneficiary_id,service_id,status,version,price_amount,currency_code,created_at
       FROM care_requests WHERE id=$1 AND requester_user_id=$2`,[requestId,userId]);
    if(!found.rowCount) missing();
    return found.rows[0];
  }
  async list(userId: string, page: PageArgs) {
    // One joined query for request + service + beneficiary + winning assignment.
    // A correlated lookup per row would be a N+1 anti-pattern.
    const result = await this.db.query(`SELECT cr.id,cr.status,cr.price_amount,cr.currency_code,
      cr.created_at,cr.version,
      to_char(cr.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_created_at,
      s.title_ar AS service_title,b.display_name AS beneficiary_name,
      a.nurse_id AS assigned_nurse_id
      FROM care_requests cr
      JOIN services s ON s.id=cr.service_id
      JOIN beneficiaries b ON b.id=cr.beneficiary_id
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
    const canCancel = ['OFFERING','ASSIGNED','EN_ROUTE','UNFULFILLED'].includes(row.status);
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
    const r=await this.db.query(`SELECT a.nurse_id,cr.id,cr.status,ST_Y(cr.location::geometry) AS patient_lat,ST_X(cr.location::geometry) AS patient_lng,
      CASE WHEN cr.status='EN_ROUTE' AND nl.recorded_at > now() - interval '120 seconds' THEN ST_Y(nl.location::geometry) END AS nurse_lat,
      CASE WHEN cr.status='EN_ROUTE' AND nl.recorded_at > now() - interval '120 seconds' THEN ST_X(nl.location::geometry) END AS nurse_lng,
      CASE WHEN cr.status='EN_ROUTE' THEN nl.recorded_at END AS location_at
      FROM care_requests cr LEFT JOIN request_assignments a ON a.request_id=cr.id AND a.status='ACTIVE'
      LEFT JOIN nurse_locations nl ON nl.nurse_id=a.nurse_id
      WHERE cr.id=$1 AND cr.requester_user_id=$2`,[requestId,userId]);
    if(!r.rowCount) missing();
    const { nurse_id: nurseId, ...row } = r.rows[0];
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
