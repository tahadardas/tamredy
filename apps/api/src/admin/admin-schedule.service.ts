import { Injectable } from '@nestjs/common';
import { conflict, missing } from '../common/errors.js';
import { DbService } from '../db/db.service.js';

@Injectable()
export class AdminScheduleService {
  constructor(private readonly db: DbService) {}

  async list(removed: boolean, page: number) {
    const visits = await this.db.query(`SELECT r.id,r.status,r.address_text,s.appointment_at,
        b.display_name AS beneficiary_name,svc.title_ar AS service_title,
        assigned.display_name AS assigned_nurse, performed.display_name AS arrived_nurse,
        performed.arrived_at
      FROM scheduled_visits s JOIN care_requests r ON r.id=s.request_id
      JOIN beneficiaries b ON b.id=r.beneficiary_id JOIN services svc ON svc.id=r.service_id
      LEFT JOIN LATERAL (
        SELECT u.display_name FROM request_assignments a JOIN nurses n ON n.id=a.nurse_id
        JOIN users u ON u.id=n.user_id WHERE a.request_id=r.id AND a.status='ACTIVE' LIMIT 1
      ) assigned ON true
      LEFT JOIN LATERAL (
        SELECT u.display_name,v.arrived_at FROM request_assignments a JOIN visits v ON v.assignment_id=a.id
        JOIN nurses n ON n.id=a.nurse_id JOIN users u ON u.id=n.user_id
        WHERE a.request_id=r.id AND v.arrived_at IS NOT NULL ORDER BY v.arrived_at DESC,a.id DESC LIMIT 1
      ) performed ON true
      WHERE (s.admin_removed_at IS NOT NULL)=$1
      ORDER BY s.appointment_at DESC,r.id DESC LIMIT 51 OFFSET $2`, [removed, (page - 1) * 50]);
    return { items: visits.rows.slice(0, 50), hasMore: visits.rows.length > 50 };
  }

  async plans(page: number) {
    const plans = await this.db.query(`SELECT p.id,b.display_name AS beneficiary_name,s.title_ar AS service_title,
        p.status,p.frequency_type,p.total_visits_planned,
        stats.completed,stats.next_visit
      FROM care_plans p JOIN beneficiaries b ON b.id=p.beneficiary_id JOIN services s ON s.id=p.primary_service_id
      LEFT JOIN LATERAL (
        SELECT count(*) FILTER (WHERE coalesce(r.status,o.status)='COMPLETED')::int AS completed,
          min(o.scheduled_for) FILTER (WHERE o.scheduled_for>=now() AND o.status IN ('PENDING','GENERATED')
            AND (r.id IS NULL OR r.status NOT IN ('CANCELLED','UNFULFILLED','EXPIRED','COMPLETED','ESCALATED'))) AS next_visit
        FROM care_plan_occurrences o LEFT JOIN care_requests r ON r.id=o.request_id WHERE o.care_plan_id=p.id
      ) stats ON true
      ORDER BY p.created_at DESC,p.id DESC LIMIT 51 OFFSET $1`, [(page - 1) * 50]);
    return { items: plans.rows.slice(0, 50), hasMore: plans.rows.length > 50 };
  }

  remove(actor: string, id: string) {
    return this.db.transaction(async c => {
      const visit = (await c.query(`SELECT r.status,r.requester_user_id
        FROM care_requests r JOIN scheduled_visits s ON s.request_id=r.id WHERE r.id=$1 FOR UPDATE OF r`, [id])).rows[0];
      if (!visit) missing();
      const {rows} = await c.query('SELECT admin_removed_at FROM scheduled_visits WHERE request_id=$1', [id]);
      if (rows[0]?.admin_removed_at) return { id, removed: true };
      if (visit.status === 'SCHEDULED') {
        const assigned = await c.query('SELECT 1 FROM request_assignments WHERE request_id=$1 AND status=\'ACTIVE\'', [id]);
        if (assigned.rowCount) conflict('SCHEDULE_VISIT_IN_PROGRESS');
        await c.query(`UPDATE care_requests SET status='CANCELLED',version=version+1,updated_at=now(),
          closed_at=now(),close_reason='CANCELLED',marketplace_status='CANCELLED' WHERE id=$1`, [id]);
        await c.query(`UPDATE care_plan_occurrences SET status='CANCELLED' WHERE request_id=$1 AND status='GENERATED'`, [id]);
        await c.query(`INSERT INTO request_events(request_id,actor_user_id,event_type)
          VALUES($1,$2,'request.cancelled')`, [id,actor]);
        await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
          VALUES('request.cancelled',$1,jsonb_build_object('requestId',$1::uuid,'recipientUserIds',ARRAY[$2::uuid]))`, [id,visit.requester_user_id]);
      } else if (!['COMPLETED','CANCELLED','UNFULFILLED','EXPIRED','ESCALATED'].includes(visit.status)) {
        conflict('SCHEDULE_VISIT_IN_PROGRESS');
      }
      await c.query('UPDATE scheduled_visits SET admin_removed_at=now() WHERE request_id=$1', [id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail)
        VALUES($1,'request.schedule_removed','care_request',$2,jsonb_build_object('previousStatus',$3::text))`, [actor,id,visit.status]);
      return { id, removed: true };
    });
  }
}
