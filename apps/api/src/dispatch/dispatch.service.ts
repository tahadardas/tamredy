import { closeOpenOffers } from './offer-outbox.js';
import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { conflict, forbidden, gone, missing } from '../common/errors.js';
import { commissionFor, computeBill, ruleFromRow } from '../pricing/pricing.js';
import { DuesService, FeesService } from '../pricing/fees.service.js';
import { RoutesService } from '../maps/routes.service.js';

@Injectable()
export class DispatchService {
  constructor(private readonly db: DbService, private readonly fees: FeesService = new FeesService(), private readonly dues: DuesService = new DuesService(), private readonly routes: RoutesService = new RoutesService()) {}

  async offersForUser(userId: string) {
    const results = await this.db.query(`SELECT o.id,o.request_id,o.expires_at,o.wave_no,statement_timestamp() AS server_now,
      s.title_ar,s.code AS service_code,s.expected_minutes,
      round(ST_Distance(nl.location,cr.location))::integer AS distance_m,
      cr.price_amount,cr.currency_code,cr.commission_bps,
      round(cr.price_amount * (10000 - cr.commission_bps) / 10000)::integer AS nurse_share,
      'ضمن نطاق الخدمة' AS area
      FROM request_offers o JOIN nurses n ON n.id=o.nurse_id
      JOIN care_requests cr ON cr.id=o.request_id JOIN services s ON s.id=cr.service_id
      LEFT JOIN nurse_locations nl ON nl.nurse_id=n.id
      WHERE n.user_id=$1 AND o.status='OPEN' AND o.expires_at>now() AND cr.status='OFFERING'
      ORDER BY o.expires_at LIMIT 20`,[userId]);
    // Privacy: no exact patient coordinate, full address or phone before assignment.
    return results.rows;
  }

  async accept(userId: string, offerId: string) {
    return this.db.transaction(async c => {
      const lookup = await c.query(`SELECT o.request_id,o.nurse_id FROM request_offers o
        JOIN nurses n ON n.id=o.nurse_id WHERE o.id=$1 AND n.user_id=$2`,[offerId,userId]);
      if(!lookup.rowCount) missing();
      const {request_id:requestId,nurse_id:nurseId}=lookup.rows[0];
      // The order of locks is consistent for every mutation: request, nurse, offer.
      const rr=await c.query(`SELECT * FROM care_requests WHERE id=$1 FOR UPDATE`,[requestId]);
      const request=rr.rows[0];
      const nightPolicy = process.env.GUARDIAN_NIGHT_POLICY_ENABLED === 'true';
      const companion = nightPolicy ? (await c.query(`WITH review AS (
        SELECT decision,effective_until FROM safety_visit_reviews WHERE request_id=$1
        ORDER BY created_at DESC,id DESC LIMIT 1
      ) SELECT v.companion_id FROM safety_visit_companions v CROSS JOIN review r
        WHERE v.request_id=$1 AND v.nurse_id=$2 AND v.confirmed_at IS NOT NULL
          AND r.decision='REQUIRE_COMPANION' AND r.effective_until>clock_timestamp()`,
      [requestId,nurseId])).rows[0]?.companion_id : undefined;
      const nr=companion
        ? await c.query('SELECT * FROM nurses WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE', [[nurseId,companion]])
        : await c.query('SELECT * FROM nurses WHERE id=$1 FOR UPDATE',[nurseId]);
      const nurse=companion ? nr.rows.find(row => row.id===nurseId) : nr.rows[0];
      const oo=await c.query(`SELECT status, expires_at > clock_timestamp() AS unexpired
        FROM request_offers WHERE id=$1 FOR UPDATE`,[offerId]);
      const offer=oo.rows[0];
      if (offer?.status === 'ACCEPTED') {
        const existing = await c.query(`SELECT id FROM request_assignments
          WHERE request_id=$1 AND nurse_id=$2 ORDER BY accepted_at DESC LIMIT 1`,[requestId,nurseId]);
        if (existing.rowCount) return {assignmentId:existing.rows[0].id,requestId,status:request.status,replayed:true};
      }
      if(request?.status !== 'OFFERING') conflict('REQUEST_ALREADY_ASSIGNED_OR_CLOSED');
      if(!offer || offer.status!=='OPEN' || !offer.unexpired) gone();
      if(!nurse?.verified || nurse.work_status !== 'AVAILABLE' || nurse.availability_intent!=='AVAILABLE') {
        conflict('NURSE_NOT_AVAILABLE');
      }
      const blocked = await c.query(`
        SELECT 1 FROM user_blocks ub
        WHERE ((ub.blocker_user_id = $1 AND ub.blocked_user_id = $2)
           OR (ub.blocker_user_id = $2 AND ub.blocked_user_id = $1))
          AND ub.revoked_at IS NULL
        LIMIT 1
      `, [userId, request.requester_user_id]);
      if (blocked.rowCount) conflict('MUTUALLY_BLOCKED');

      const sched = await c.query(
        `SELECT appointment_at FROM scheduled_visits WHERE request_id = $1`,
        [requestId],
      );
      if (sched.rowCount) {
        const appointmentAt = new Date(sched.rows[0].appointment_at);
        const expectedMin = Number(request.pricing?.expectedMinutes) || 30;
        const conflictRes = await c.query(
          `SELECT nurse_has_schedule_conflict($1, $2::timestamptz, $3::timestamptz, $4) AS conflict`,
          [
            nurseId,
            new Date(appointmentAt.getTime() - 30 * 60 * 1000).toISOString(),
            new Date(appointmentAt.getTime() + (expectedMin + 30) * 60 * 1000).toISOString(),
            requestId,
          ],
        );
        if (conflictRes.rows[0]?.conflict) {
          conflict('NURSE_SCHEDULE_CONFLICT');
        }
      }
      const ready = await c.query(`SELECT 1 FROM nurses n
        JOIN users u ON u.id=n.user_id AND u.status='ACTIVE'
        JOIN care_requests r ON r.id=$2
        LEFT JOIN nurse_locations nl ON nl.nurse_id=n.id
        WHERE n.id=$1
          AND n.last_heartbeat_at > clock_timestamp()-coalesce(r.search_max_heartbeat_seconds,120)*interval '1 second'
          AND NOT EXISTS (SELECT 1 FROM request_assignments a WHERE a.nurse_id=n.id AND a.status='ACTIVE')
          AND (r.search_expires_at IS NULL OR (
            nl.recorded_at > clock_timestamp()-r.search_max_location_seconds*interval '1 second'
            AND nl.accuracy_m <= r.search_max_accuracy_meters
            AND ST_DWithin(nl.location,r.location,r.search_radius_meters)
          ))`,[nurseId,requestId]);
      if (!ready.rowCount) conflict('NURSE_NOT_AVAILABLE');
      if (nightPolicy) {
        const denial = (await c.query(`SELECT guardian_dispatch_denial($1,$2,statement_timestamp()) AS reason`,
          [nurseId,requestId])).rows[0]?.reason;
        if (denial) conflict(denial);
      }
      const qualified=await c.query(`SELECT 1 FROM nurse_skills sk
        WHERE sk.nurse_id=$1 AND sk.service_id=$2 AND sk.approved=true AND EXISTS(
          SELECT 1 FROM nurse_credentials nc WHERE nc.nurse_id=sk.nurse_id
          AND nc.approved=true AND nc.expires_at>clock_timestamp())`,[nurseId,request.service_id]);
      if(!qualified.rowCount) forbidden();
      if((await this.dues.balance(c,nurseId)).blocked) conflict('SETTLEMENT_REQUIRED'); // owes the company more than the allowed limit
      const ins=await c.query(`WITH policy AS (
        SELECT nullif(coalesce((SELECT (value->>'departureReminderSeconds')::integer
          FROM app_settings WHERE key='dispatch'),0),0) AS seconds
      )
      INSERT INTO request_assignments(request_id,nurse_id,accepted_at,departure_due_at)
        SELECT $1,$2,statement_timestamp(),statement_timestamp()+seconds*interval '1 second' FROM policy
        RETURNING id`,[requestId,nurseId]);
      const assignmentId=ins.rows[0].id;
      if (companion) await c.query(`INSERT INTO safety_companion_reservations(assignment_id,companion_id)
        VALUES($1,$2)`, [assignmentId,companion]);
      const updateNurse=await c.query(`UPDATE nurses SET work_status='RESERVED',updated_at=now()
        WHERE id=$1 AND work_status='AVAILABLE'`,[nurseId]);
      if(updateNurse.rowCount!==1) conflict('NURSE_NOT_AVAILABLE');
      const updateRequest=await c.query(`UPDATE care_requests SET status='ASSIGNED',version=version+1,
        closed_at=statement_timestamp(),close_reason='ASSIGNED',updated_at=statement_timestamp()
        WHERE id=$1 AND status='OFFERING'
          AND (search_expires_at IS NULL OR search_expires_at>statement_timestamp())
          AND EXISTS (SELECT 1 FROM request_offers o WHERE o.id=$2 AND o.expires_at>statement_timestamp()
            ${process.env.GUARDIAN_NIGHT_POLICY_ENABLED === 'true'
              ? 'AND guardian_dispatch_denial(o.nurse_id,care_requests.id,statement_timestamp()) IS NULL' : ''})`,[requestId,offerId]);
      if(updateRequest.rowCount!==1) gone();
      // Distance the nurse must cover (straight line x 1.3 road factor) -> automatic travel fee when enabled.
      await c.query(`UPDATE care_requests SET travel_distance_m=(SELECT round(ST_Distance(nl.location,cr.location)*1.3)::int
        FROM nurse_locations nl JOIN care_requests cr ON cr.id=$1 WHERE nl.nurse_id=$2) WHERE id=$1`,[requestId,nurseId]);
      await closeOpenOffers(c, requestId, 'ASSIGNED', offerId);
      await c.query('DELETE FROM dispatch_jobs WHERE request_id=$1',[requestId]);
      await c.query(`INSERT INTO request_events(request_id,actor_user_id,event_type,payload)
        VALUES($1,$2,'request.assigned',$3::jsonb)`,[requestId,userId,JSON.stringify({assignmentId,nurseId})]);
      await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
        VALUES('request.assigned',$1,$2::jsonb)`,[requestId,JSON.stringify({requestId,assignmentId,nurseId,recipientUserId:request.requester_user_id})]);
      return {assignmentId,requestId,status:'ASSIGNED',replayed:false};
    });
  }

  async decline(userId: string, offerId: string) {
    const result=await this.db.query(`UPDATE request_offers o SET status='DECLINED'
      FROM nurses n WHERE o.id=$1 AND n.id=o.nurse_id AND n.user_id=$2 AND o.status='OPEN'
      RETURNING o.id`,[offerId,userId]);
    if (!result.rowCount) missing();
    return {status:'DECLINED'};
  }

  private async estimateDeparture(userId: string, assignmentId: string) {
    if (!this.routes.configured) return null;
    const result = await this.db.query(`SELECT nl.recorded_at::text AS recorded_at,
        ST_Y(nl.location::geometry) AS nurse_lat, ST_X(nl.location::geometry) AS nurse_lng,
        ST_Y(r.location::geometry) AS patient_lat, ST_X(r.location::geometry) AS patient_lng
      FROM request_assignments a
      JOIN care_requests r ON r.id=a.request_id AND r.status='ASSIGNED'
      JOIN nurses n ON n.id=a.nurse_id AND n.user_id=$1
      JOIN nurse_locations nl ON nl.nurse_id=n.id
      WHERE a.id=$2 AND a.status='ACTIVE'
        AND nl.recorded_at>clock_timestamp()-coalesce(r.search_max_location_seconds,120)*interval '1 second'
        AND nl.accuracy_m<=coalesce(r.search_max_accuracy_meters,100)`, [userId, assignmentId]);
    const location = result.rows[0];
    if (!location) return null;
    try {
      const route = await this.routes.compute(
        { lat: Number(location.nurse_lat), lng: Number(location.nurse_lng) },
        { lat: Number(location.patient_lat), lng: Number(location.patient_lng) },
      );
      if (!Number.isSafeInteger(route.durationSeconds) || route.durationSeconds < 1 || route.durationSeconds > 86400) return null;
      return { duration: route.durationSeconds, provider: this.routes.provider, recordedAt: location.recorded_at };
    } catch {
      return null;
    }
  }

  async transition(userId: string, assignmentId: string, action: 'depart'|'arrive'|'start'|'complete') {
    const specs={
      depart:{from:'ASSIGNED',to:'EN_ROUTE',nurse:'EN_ROUTE'},
      arrive:{from:'EN_ROUTE',to:'ARRIVED',nurse:'EN_ROUTE'},
      start:{from:'ARRIVED',to:'IN_SERVICE',nurse:'IN_SERVICE'},
      complete:{from:'IN_SERVICE',to:'COMPLETED',nurse:'AVAILABLE'},
    } as const;
    const target=specs[action];
    const estimate = action === 'depart' ? await this.estimateDeparture(userId, assignmentId) : null;
    return this.db.transaction(async c => {
      const assignmentLookup=await c.query(`SELECT a.request_id,a.nurse_id FROM request_assignments a
        JOIN nurses n ON n.id=a.nurse_id WHERE a.id=$1 AND n.user_id=$2`,[assignmentId,userId]);
      if(!assignmentLookup.rowCount) missing();
      const {request_id:requestId,nurse_id:nurseId}=assignmentLookup.rows[0];
      const rr=await c.query('SELECT id,status,requester_user_id,pricing,promo_snapshot,price_amount,commission_bps,travel_distance_m FROM care_requests WHERE id=$1 FOR UPDATE',[requestId]);
      const request=rr.rows[0];
      await c.query('SELECT id FROM nurses WHERE id=$1 FOR UPDATE',[nurseId]);
      const assignment=await c.query(`SELECT id,status FROM request_assignments WHERE id=$1 FOR UPDATE`,[assignmentId]);
      if(request?.status===target.to && assignment.rowCount) return {requestId,assignmentId,status:target.to,replayed:true};
      if(!assignment.rowCount || assignment.rows[0].status!=='ACTIVE') conflict('ASSIGNMENT_INACTIVE');
      if(request?.status!==target.from) conflict('INVALID_STATE_TRANSITION');
      if (action === 'depart') {
        await c.query(`WITH estimate AS (
          SELECT $2::integer AS duration, $3::text AS provider FROM nurse_locations nl
          JOIN request_assignments a ON a.nurse_id=nl.nurse_id
          JOIN care_requests r ON r.id=a.request_id
          WHERE a.id=$1 AND nl.recorded_at=$4::timestamptz
            AND nl.recorded_at>statement_timestamp()-coalesce(r.search_max_location_seconds,120)*interval '1 second'
            AND nl.accuracy_m<=coalesce(r.search_max_accuracy_meters,100)
        ) UPDATE request_assignments SET departed_at=statement_timestamp(),
          eta_reference_at=statement_timestamp(), eta_version=1,
          eta_duration_seconds=(SELECT duration FROM estimate),
          eta_provider=(SELECT provider FROM estimate),
          expected_arrival_at=statement_timestamp()+(SELECT duration FROM estimate)*interval '1 second',
          eta_status=CASE WHEN EXISTS (SELECT 1 FROM estimate) THEN 'AVAILABLE' ELSE 'ETA_UNAVAILABLE' END
        WHERE id=$1`, [assignmentId, estimate?.duration ?? null, estimate?.provider ?? null, estimate?.recordedAt ?? null]);
      }
      if(action==='arrive') {
        await c.query(`INSERT INTO visits(assignment_id,arrived_at) VALUES($1,now()) ON CONFLICT(assignment_id) DO NOTHING`,[assignmentId]);
      }
      if(action==='start') {
        const r=await c.query(`UPDATE visits SET started_at=now() WHERE assignment_id=$1 AND arrived_at IS NOT NULL AND started_at IS NULL`,[assignmentId]);
        if(r.rowCount!==1) conflict('VISIT_NOT_ARRIVED');
      }
      if(action==='complete') {
        const r=await c.query(`UPDATE visits SET completed_at=now(),outcome='COMPLETED' WHERE assignment_id=$1 AND started_at IS NOT NULL AND completed_at IS NULL`,[assignmentId]);
        if(r.rowCount!==1) conflict('VISIT_NOT_STARTED');
        await c.query(`UPDATE request_assignments SET status='RELEASED',released_at=now(),reason='COMPLETED' WHERE id=$1`,[assignmentId]);
        // Full bill from the real time at the patient, using the pricing snapshot taken when the order was placed.
        const t=await c.query(`SELECT EXTRACT(EPOCH FROM (completed_at-arrived_at)) AS secs,arrived_at FROM visits WHERE assignment_id=$1`,[assignmentId]);
        const pricing=request.pricing&&Object.keys(request.pricing).length?request.pricing:{basePrice:request.price_amount};
        const rep=await this.fees.reputation(c,nurseId);
        const bps=commissionFor(Number(request.commission_bps??2000),await this.fees.tiers(c),rep.reputation,rep.reviews); // top-rated nurses keep more
        const bill=computeBill(ruleFromRow(pricing),Number(t.rows[0]?.secs??0),{promo:request.promo_snapshot,fees:pricing.fees??null,
          arrivedAt:new Date(t.rows[0]?.arrived_at??Date.now()),travelMeters:Number(request.travel_distance_m??0),commissionBps:bps});
        await c.query(`UPDATE care_requests SET service_minutes=$2,gross_amount=$3,discount_amount=$4,surcharge_amount=$5,distance_fee=$6,tax_amount=$7,
          amount_due=$8::numeric,commission_bps_applied=$9,commission_amount=$10,nurse_earning=$11,owed_to_company=$12,
          payment_status=CASE WHEN $8::numeric=0 THEN 'PAID' ELSE 'DUE' END,billed_at=now() WHERE id=$1`,
          [requestId,bill.minutes,bill.gross,bill.discount,bill.surcharge,bill.distanceFee,bill.tax,bill.due,bill.commissionBps,bill.commission,bill.nurseEarning,bill.owedToCompany]);
      }
      await c.query(`UPDATE care_requests SET status=$2,version=version+1,updated_at=now() WHERE id=$1`,[requestId,target.to]);
      if(action==='complete') {
        await c.query(`UPDATE nurses SET work_status=CASE WHEN availability_intent='AVAILABLE'
          AND last_heartbeat_at>now()-interval '120 seconds' THEN 'AVAILABLE'
          WHEN availability_intent='PAUSED' THEN 'PAUSED' ELSE 'OFFLINE' END,updated_at=now() WHERE id=$1`,[nurseId]);
      } else {
        await c.query('UPDATE nurses SET work_status=$2,updated_at=now() WHERE id=$1',[nurseId,target.nurse]);
      }
      await c.query(`INSERT INTO request_events(request_id,actor_user_id,event_type) VALUES($1,$2,$3)`,[requestId,userId,`visit.${action}`]);
      await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES($1,$2,$3::jsonb)`,[
        `visit.${action}`,requestId,JSON.stringify({requestId,recipientUserId:request.requester_user_id})
      ]);
      // (payload carries ids only; the bill is read over REST)
      return {requestId,assignmentId,status:target.to,replayed:false};
    });
  }
}
