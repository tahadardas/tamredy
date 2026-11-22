import { BadRequestException, Body, Controller, Get, NotFoundException, Param, Patch, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { makePage } from '../common/pagination.js';
import { validatedPage } from '../common/page-query.js';
import { ReferenceCacheService } from '../cache/reference-cache.service.js';
import { IsBoolean, IsOptional } from 'class-validator';
class UpdateServiceVisibilityDto { @IsOptional() @IsBoolean() active?:boolean; }
@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminController {
  constructor(private readonly db:DbService,private readonly cache:ReferenceCacheService) {}
  @Patch('services/:id/visibility') async updateVisibility(@Request() r:AuthRequest,@Param('id') id:string,@Body() body:UpdateServiceVisibilityDto) {
    requireRole(r.user!,'ADMIN');
    if(typeof body.active!=='boolean') throw new BadRequestException({code:'ACTIVE_REQUIRED'});
    // The transaction writes an outbox event so cache eviction remains retryable.
    const result=await this.db.transaction(async c=>{
      const rows=await c.query('UPDATE services SET active=$2 WHERE id=$1 RETURNING id,active',[id,body.active]);
      if(!rows.rowCount)throw new NotFoundException({code:'NOT_FOUND'});
      await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
        VALUES('cache.invalidate', $1, $2::jsonb)`,[id,JSON.stringify({namespace:'services:public'})]);
      return rows.rows[0];
    });
    await this.cache.invalidate('services:public');
    return result;
  }
  @Get('dashboard') async dashboard(@Request() r:AuthRequest) {
    requireRole(r.user!,'ADMIN');
    const counts=await this.db.query(`SELECT
      (SELECT count(*)::integer FROM nurses WHERE work_status='AVAILABLE' AND last_heartbeat_at>now()-interval '60 seconds') AS available_nurses,
      (SELECT count(*)::integer FROM nurses WHERE work_status='AVAILABLE' AND last_heartbeat_at>now()-interval '60 seconds' AND EXISTS(SELECT 1 FROM request_assignments a WHERE a.nurse_id=nurses.id AND a.status='ACTIVE')) AS busy_nurses,
      (SELECT count(*)::integer FROM care_requests WHERE status='OFFERING') AS searching_requests,
      (SELECT count(*)::integer FROM care_requests WHERE status IN ('ASSIGNED', 'EN_ROUTE')) AS en_route,
      (SELECT count(*)::integer FROM care_requests WHERE status IN ('ARRIVED', 'IN_SERVICE')) AS in_service,
      (SELECT count(*)::integer FROM care_requests WHERE status='COMPLETED' AND updated_at>=date_trunc('day',now())) AS completed_today,
      (SELECT count(*)::integer FROM care_requests WHERE status='CANCELLED' AND updated_at>=date_trunc('day',now())) AS cancelled_today,
      (SELECT count(*)::integer FROM care_requests WHERE status='ESCALATED') AS escalated_requests,
      (SELECT coalesce(sum(price_amount),0)::bigint FROM care_requests WHERE status='COMPLETED' AND updated_at>=date_trunc('day',now())) AS revenue_today,
      (SELECT coalesce(sum(price_amount*commission_bps/10000),0)::bigint FROM care_requests WHERE status='COMPLETED' AND updated_at>=date_trunc('day',now())) AS commission_today,
      (SELECT coalesce(sum(balance),0)::bigint FROM (SELECT nurse_id, coalesce(sum(amount),0) AS balance FROM settlement_ledgers GROUP BY nurse_id) bl WHERE balance > 0) AS dues_pending`);
    return counts.rows[0];
  }
  @Get('requests') async requests(@Request() r:AuthRequest,@Query('limit') limit?:string,@Query('cursor') cursor?:string,@Query('status') status?:string) {
    requireRole(r.user!,'ADMIN');
    if (status && !['OFFERING','ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE','COMPLETED','CANCELLED','UNFULFILLED','ESCALATED'].includes(status))
      throw new BadRequestException({code:'INVALID_STATUS'});
    const scope=`admin:requests:${status??'all'}`;
    const page=validatedPage(limit,cursor,scope);
    // Joined read: no per-request SELECT for service, beneficiary or assigned nurse.
    const statusClause=status?'cr.status=$1 AND ':'';
    const cursorParam=status?2:1;
    const result=await this.db.query(`SELECT cr.id,cr.status,cr.created_at,cr.version,
       to_char(cr.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_created_at,
       s.title_ar AS service_title,b.display_name AS beneficiary_name,a.nurse_id AS assigned_nurse_id
       FROM care_requests cr
       JOIN services s ON s.id=cr.service_id
       JOIN beneficiaries b ON b.id=cr.beneficiary_id
       LEFT JOIN request_assignments a ON a.request_id=cr.id AND a.status='ACTIVE'
       WHERE ${statusClause}($${cursorParam}::timestamptz IS NULL OR
          (cr.created_at,cr.id)<($${cursorParam}::timestamptz,$${cursorParam+1}::uuid))
       ORDER BY cr.created_at DESC,cr.id DESC LIMIT $${cursorParam+2}`,
       status?[status,page.cursor?.at??null,page.cursor?.id??null,page.limit+1]
         :[page.cursor?.at??null,page.cursor?.id??null,page.limit+1]);
    return makePage(result.rows,page.limit,scope);
  }
  @Get('nurses') async nurses(@Request() r:AuthRequest,@Query('limit') limit?:string,@Query('cursor') cursor?:string) {
    requireRole(r.user!,'ADMIN');
    const page=validatedPage(limit,cursor,'admin:nurses');
    const result=await this.db.query(`SELECT n.id,n.verified,n.work_status,n.availability_intent,
      n.last_heartbeat_at,u.phone_e164,u.status AS account_status,u.created_at,u.id AS cursor_id,
      to_char(u.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_created_at
      FROM nurses n JOIN users u ON u.id=n.user_id
      WHERE ($1::timestamptz IS NULL OR (u.created_at,u.id)<($1::timestamptz,$2::uuid))
      ORDER BY u.created_at DESC,u.id DESC LIMIT $3`,
      [page.cursor?.at??null,page.cursor?.id??null,page.limit+1]);
    return makePage(result.rows,page.limit,'admin:nurses');
  }
}
