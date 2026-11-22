import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { conflict, forbidden, gone, missing } from '../common/errors.js';
import { commissionFor, computeBill, ruleFromRow } from '../pricing/pricing.js';
import { DuesService, FeesService } from '../pricing/fees.service.js';

@Injectable()
export class DispatchService {
  constructor(private readonly db: DbService, private readonly fees: FeesService = new FeesService(), private readonly dues: DuesService = new DuesService()) {}

  async offersForUser(userId: string) {
    const results = await this.db.query(`SELECT o.id,o.request_id,o.expires_at,o.wave_no,
      s.title_ar,s.code AS service_code,s.expected_minutes,
      round(ST_Distance(nl.location,cr.location))::integer AS distance_m,
      cr.price_amount,cr.currency_code,cr.commission_bps,
      round(cr.price_amount * (10000 - cr.commission_bps) / 10000)::integer AS nurse_share,
      coalesce(nullif(split_part(split_part(cr.address_text,' • ',1),' - ',1),''),'دمشق وريفها') AS area
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
      const nr=await c.query('SELECT * FROM nurses WHERE id=$1 FOR UPDATE',[nurseId]);
      const nurse=nr.rows[0];
      const ar=await c.query(`SELECT id,status FROM request_assignments WHERE request_id=$1 AND nurse_id=$2 AND status='ACTIVE'`,[requestId,nurseId]);
      if(request?.status === 'ASSIGNED' && ar.rowCount) return {assignmentId:ar.rows[0].id,requestId,status:'ASSIGNED',replayed:true};
      if(request?.status !== 'OFFERING') conflict('REQUEST_ALREADY_ASSIGNED_OR_CLOSED');
      const oo=await c.query('SELECT * FROM request_offers WHERE id=$1 FOR UPDATE',[offerId]);
      const offer=oo.rows[0];
      if(!offer || offer.status!=='OPEN' || new Date(offer.expires_at).getTime()<=Date.now()) gone();
      if(!nurse?.verified || nurse.work_status !== 'AVAILABLE' || nurse.availability_intent!=='AVAILABLE'
        || !nurse.last_heartbeat_at || Date.now()-new Date(nurse.last_heartbeat_at).getTime()>=60000) conflict('NURSE_NOT_AVAILABLE');
      const qualified=await c.query(`SELECT 1 FROM nurse_skills sk
        WHERE sk.nurse_id=$1 AND sk.service_id=$2 AND sk.approved=true AND EXISTS(
          SELECT 1 FROM nurse_credentials nc WHERE nc.nurse_id=sk.nurse_id
          AND nc.approved=true AND nc.expires_at>now())`,[nurseId,request.service_id]);
      if(!qualified.rowCount) forbidden();
      if((await this.dues.balance(c,nurseId)).blocked) conflict('SETTLEMENT_REQUIRED'); // owes the company more than the allowed limit
      const ins=await c.query(`INSERT INTO request_assignments(request_id,nurse_id)
        VALUES($1,$2) RETURNING id`,[requestId,nurseId]);
      const assignmentId=ins.rows[0].id;
      const updateNurse=await c.query(`UPDATE nurses SET work_status='RESERVED',updated_at=now()
        WHERE id=$1 AND work_status='AVAILABLE'`,[nurseId]);
      if(updateNurse.rowCount!==1) conflict('NURSE_NOT_AVAILABLE');
      const updateRequest=await c.query(`UPDATE care_requests SET status='ASSIGNED',version=version+1,updated_at=now()
        WHERE id=$1 AND status='OFFERING'`,[requestId]);
      if(updateRequest.rowCount!==1) conflict('REQUEST_ALREADY_ASSIGNED');
      // Distance the nurse must cover (straight line x 1.3 road factor) -> automatic travel fee when enabled.
      await c.query(`UPDATE care_requests SET travel_distance_m=(SELECT round(ST_Distance(nl.location,cr.location)*1.3)::int
        FROM nurse_locations nl JOIN care_requests cr ON cr.id=$1 WHERE nl.nurse_id=$2) WHERE id=$1`,[requestId,nurseId]);
      await c.query(`UPDATE request_offers SET status=CASE WHEN id=$2 THEN 'ACCEPTED' ELSE 'CLOSED' END
        WHERE request_id=$1 AND status='OPEN'`,[requestId,offerId]);
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

  async transition(userId: string, assignmentId: string, action: 'depart'|'arrive'|'start'|'complete') {
    const specs={
      depart:{from:'ASSIGNED',to:'EN_ROUTE',nurse:'EN_ROUTE'},
      arrive:{from:'EN_ROUTE',to:'ARRIVED',nurse:'EN_ROUTE'},
      start:{from:'ARRIVED',to:'IN_SERVICE',nurse:'IN_SERVICE'},
      complete:{from:'IN_SERVICE',to:'COMPLETED',nurse:'AVAILABLE'},
    } as const;
    const target=specs[action];
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
          AND last_heartbeat_at>now()-interval '60 seconds' THEN 'AVAILABLE'
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
