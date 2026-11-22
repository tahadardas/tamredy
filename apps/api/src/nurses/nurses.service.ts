import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { AvailabilityDto, LocationDto } from '../common/dto.js';
import { conflict, missing } from '../common/errors.js';
import { PageArgs, makePage } from '../common/pagination.js';
import { DuesService } from '../pricing/fees.service.js';
@Injectable()
export class NursesService {
  constructor(private readonly db: DbService, private readonly dues: DuesService = new DuesService()) {}
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
  async location(userId:string,dto:LocationDto) {
    const nurse=await this.db.query(`SELECT id,work_status,availability_intent FROM nurses WHERE user_id=$1`,[userId]);
    if(!nurse.rowCount) missing();
    const n=nurse.rows[0];
    if((n.availability_intent==='OFFLINE' && !['RESERVED','EN_ROUTE','IN_SERVICE'].includes(n.work_status)) || n.work_status==='SUSPENDED') conflict('LOCATION_UPDATES_NOT_ALLOWED_OFFLINE');
    await this.db.query(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m)
       VALUES($1,ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,$4)
       ON CONFLICT(nurse_id) DO UPDATE SET location=EXCLUDED.location,accuracy_m=EXCLUDED.accuracy_m,recorded_at=now()`,[n.id,dto.longitude,dto.latitude,dto.accuracyMeters]);
    await this.db.query(`UPDATE nurses SET last_heartbeat_at=now(),updated_at=now() WHERE id=$1`,[n.id]);
    return {updated:true};
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
    const result=await this.db.query(`SELECT a.id AS assignment_id,cr.id AS request_id,cr.status,cr.address_text,
      ST_Y(cr.location::geometry) AS latitude,ST_X(cr.location::geometry) AS longitude,
      cr.price_amount,cr.currency_code,s.title_ar AS service_title
      FROM request_assignments a JOIN nurses n ON n.id=a.nurse_id
      JOIN care_requests cr ON cr.id=a.request_id JOIN services s ON s.id=cr.service_id
      WHERE a.id=$1 AND n.user_id=$2 AND a.status='ACTIVE'`,[assignmentId,userId]);
    if(!result.rowCount) missing();
    return result.rows[0];
  }

}
