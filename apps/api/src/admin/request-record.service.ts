import { Injectable } from '@nestjs/common';
import { missing } from '../common/errors.js';
import { DbService } from '../db/db.service.js';

@Injectable()
export class RequestRecordService {
  constructor(private readonly db: DbService) {}

  get(actor: string, request: string) {
    return this.db.transaction(async client => {
      const record = (await client.query(`SELECT r.id,r.status,r.created_at,r.updated_at,r.address_text,r.location_source,
        ST_Y(r.location::geometry) AS latitude,ST_X(r.location::geometry) AS longitude,
        r.currency_code,r.amount_due,r.payment_status,r.paid_at,
        a.id AS assignment_id,a.accepted_at,a.departed_at,a.released_at,
        v.arrived_at,v.started_at AS service_started_at,v.completed_at,v.outcome,
        CASE WHEN v.completed_at>=v.arrived_at THEN floor(extract(epoch FROM(v.completed_at-v.arrived_at)))::int END AS visit_seconds,
        CASE WHEN v.completed_at>=v.started_at THEN floor(extract(epoch FROM(v.completed_at-v.started_at)))::int END AS service_seconds,
        cash.collected_amount,cash.last_collected_at
        FROM care_requests r
        LEFT JOIN LATERAL (SELECT * FROM request_assignments WHERE request_id=r.id
          ORDER BY EXISTS (SELECT 1 FROM visits av WHERE av.assignment_id=request_assignments.id AND av.arrived_at IS NOT NULL) DESC,
          accepted_at DESC,id DESC LIMIT 1) a ON true
        LEFT JOIN visits v ON v.assignment_id=a.id
        LEFT JOIN LATERAL (SELECT sum(amount) AS collected_amount,max(created_at) AS last_collected_at
          FROM cash_collections WHERE visit_id=v.id) cash ON true
        WHERE r.id=$1`,[request])).rows[0];
      if (!record) missing();
      const assignments = (await client.query(`SELECT a.id,n.id AS nurse_id,u.display_name AS nurse_name,
        a.status,a.accepted_at,a.departed_at,a.released_at,v.arrived_at,v.started_at,v.completed_at
        FROM request_assignments a JOIN nurses n ON n.id=a.nurse_id JOIN users u ON u.id=n.user_id
        LEFT JOIN visits v ON v.assignment_id=a.id WHERE a.request_id=$1
        ORDER BY a.accepted_at,a.id`,[request])).rows;
      const events = (await client.query(`SELECT id::text,event_type,occurred_at FROM request_events
        WHERE request_id=$1 AND event_type IN ('request.created','request.assigned','request.cancelled',
          'request.unfulfilled','request.schedule_released','visit.depart','visit.arrive','visit.start',
          'visit.complete','visit.interrupted','payment.partial','payment.paid')
        ORDER BY request_events.id DESC LIMIT 100`,[request])).rows.reverse();
      await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
        VALUES($1,'request.visit_record_viewed','care_request',$2)`,[actor,request]);
      return {...record,events,assignments};
    });
  }
}
