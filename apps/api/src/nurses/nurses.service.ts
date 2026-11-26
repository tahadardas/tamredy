import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { AvailabilityDto } from '../common/dto.js';
import { conflict, missing } from '../common/errors.js';
import { PageArgs, makePage } from '../common/pagination.js';
import { DuesService } from '../pricing/fees.service.js';
import { LiveLocationService } from '../live-location/live-location.service.js';
import { LiveLocationUpdateDto } from '../live-location/location-update.dto.js';
import { AssignmentLocationAuthorizationService } from '../requests/assignment-location-authorization.service.js';
@Injectable()
export class NursesService {
  constructor(
    private readonly db: DbService,
    private readonly liveLocation: LiveLocationService,
    private readonly dues: DuesService = new DuesService(),
    private readonly locationAuth: AssignmentLocationAuthorizationService = new AssignmentLocationAuthorizationService(),
  ) {}
  async availability(userId: string, dto: AvailabilityDto) {
    return this.db.transaction(async c => {
      const r=await c.query(`SELECT * FROM nurses WHERE user_id=$1 FOR UPDATE`,[userId]);
      const n=r.rows[0];
      if(!n) missing();
      if(dto.availability==='AVAILABLE') {
        if(!n.verified) conflict('NURSE_NOT_VERIFIED');
        if((await this.dues.balance(c,n.id)).blocked) conflict('SETTLEMENT_REQUIRED'); // settle cash dues with the company first
        const valid=await c.query(`SELECT 1 FROM nurse_credentials WHERE nurse_id=$1 AND approved=true AND expires_at>now()`,[n.id]);
        if(!valid.rowCount) conflict('LICENSE_NOT_VERIFIED');
      }
      const busy=['RESERVED','EN_ROUTE','IN_SERVICE'].includes(n.work_status);
      const next=busy?n.work_status:dto.availability;
      await c.query(`UPDATE nurses SET availability_intent=$2, work_status=$3,updated_at=now(),
        last_heartbeat_at=CASE WHEN $2='AVAILABLE' THEN now() ELSE last_heartbeat_at END WHERE id=$1`,[n.id,dto.availability,next]);
      return {availabilityIntent:dto.availability,workStatus:next};
    });
  }
  async location(userId:string,deviceSessionId:string|undefined,dto:LiveLocationUpdateDto) {
    return this.liveLocation.ingest(userId,deviceSessionId,dto);
  }
  async heartbeat(userId:string) {
    const result=await this.db.query(`UPDATE nurses SET last_heartbeat_at=now(),updated_at=now()
      WHERE user_id=$1 AND availability_intent <> 'OFFLINE' RETURNING work_status`,[userId]);
    if(!result.rowCount) conflict('NURSE_OFFLINE');
    return {ok:true,workStatus:result.rows[0].work_status};
  }
  async history(userId:string,page:PageArgs) {
    const result=await this.db.query(`SELECT a.id, a.accepted_at AS created_at,
      to_char(a.accepted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_created_at,
      a.status AS assignment_status,
      cr.status AS request_status,cr.currency_code,cr.price_amount,s.title_ar AS service_title
      FROM nurses n JOIN request_assignments a ON a.nurse_id=n.id
      JOIN care_requests cr ON cr.id=a.request_id
      JOIN services s ON s.id=cr.service_id
      WHERE n.user_id=$1
        AND ($2::timestamptz IS NULL OR (a.accepted_at,a.id)<($2::timestamptz,$3::uuid))
      ORDER BY a.accepted_at DESC,a.id DESC LIMIT $4`,
      [userId,page.cursor?.at??null,page.cursor?.id??null,page.limit+1]);
    return makePage(result.rows,page.limit,`nurse:${userId}`);
  }
  async assignmentDetails(userId:string,assignmentId:string) {
    const result=await this.db.query(`SELECT a.id AS assignment_id,a.status AS assignment_status,
      a.departed_at,a.expected_arrival_at,a.eta_status,a.planned_start_at,
      cr.id AS request_id,cr.status,cr.status AS request_status,cr.address_text,cr.version,cr.booking_mode,
      ST_Y(cr.location::geometry) AS latitude,ST_X(cr.location::geometry) AS longitude,
      coalesce(ar.name_ar,'ضمن نطاق الخدمة') AS area_name,
      cr.price_amount,cr.currency_code,cr.commission_bps,s.title_ar AS service_title,
      b.display_name AS beneficiary_name,
      CASE WHEN cr.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE') THEN u.display_name END AS patient_name,
      sv.appointment_at AS scheduled_at,
      (a.status='ACTIVE' OR (
        a.status='RESERVED' AND cr.status='ASSIGNED'
        AND a.planned_start_at - a.travel_buffer_before_minutes*interval '1 minute' <= statement_timestamp()
      )) AS departure_window_open
      FROM request_assignments a JOIN nurses n ON n.id=a.nurse_id
      JOIN care_requests cr ON cr.id=a.request_id JOIN services s ON s.id=cr.service_id
      JOIN beneficiaries b ON b.id=cr.beneficiary_id
      JOIN users u ON u.id=cr.requester_user_id
      LEFT JOIN areas ar ON ar.id=cr.area_id
      LEFT JOIN scheduled_visits sv ON sv.request_id=cr.id
      WHERE a.id=$1 AND n.user_id=$2 AND a.status IN ('ACTIVE','RESERVED','RELEASED')`,[assignmentId,userId]);
    if(!result.rowCount) missing();
    const items = await this.db.query(`SELECT cri.id,cri.service_id,cri.quantity,cri.expected_minutes,
      cri.item_status,cri.performed_quantity,cri.actual_minutes,cri.completion_note,cri.status_reason,s.title_ar AS service_title
      FROM care_request_items cri JOIN services s ON s.id=cri.service_id
      WHERE cri.request_id=$1 ORDER BY cri.created_at,cri.id`, [result.rows[0].request_id]);
    const sanitized = this.locationAuth.sanitizeLocationFields(result.rows[0], result.rows[0].area_name);
    return { ...sanitized, items: items.rows };
  }

}
