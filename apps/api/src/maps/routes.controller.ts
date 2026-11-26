import { Controller, Get, Param, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';
import { RoutesService } from './routes.service.js';

/** Driving route + ETA for the live map. Authorisation mirrors tracking:
 *  the patient only sees the nurse while EN_ROUTE; the nurse only routes to a patient after being assigned. */
@Controller('v1') @UseGuards(AuthGuard)
export class RoutesController {
  constructor(private readonly db: DbService, private readonly routes: RoutesService) {}

  @Get('requests/:id/route') async patient(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'PATIENT');
    const q = await this.db.query(`SELECT cr.status,ST_Y(cr.location::geometry) AS plat,ST_X(cr.location::geometry) AS plng,
        ST_Y(nl.location::geometry) AS nlat,ST_X(nl.location::geometry) AS nlng,nl.recorded_at>now()-interval '120 seconds' AS fresh
      FROM care_requests cr LEFT JOIN request_assignments a ON a.request_id=cr.id AND a.status='ACTIVE'
      LEFT JOIN nurse_locations nl ON nl.nurse_id=a.nurse_id WHERE cr.id=$1 AND cr.requester_user_id=$2`, [id, r.user!.id]);
    if (!q.rowCount) missing();
    const row = q.rows[0];
    if (row.status !== 'EN_ROUTE' || !row.fresh) conflict('ROUTE_NOT_AVAILABLE');
    return this.routes.compute({ lat: +row.nlat, lng: +row.nlng }, { lat: +row.plat, lng: +row.plng });
  }

  @Get('nurse/assignments/:id/route') async nurse(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'NURSE');
    const q = await this.db.query(`SELECT ST_Y(cr.location::geometry) AS plat,ST_X(cr.location::geometry) AS plng,
        ST_Y(nl.location::geometry) AS nlat,ST_X(nl.location::geometry) AS nlng
      FROM request_assignments a JOIN nurses n ON n.id=a.nurse_id JOIN care_requests cr ON cr.id=a.request_id
      LEFT JOIN nurse_locations nl ON nl.nurse_id=n.id
      WHERE a.id=$1 AND n.user_id=$2 AND a.status='ACTIVE'
        AND cr.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE')`, [id, r.user!.id]);
    if (!q.rowCount) missing();
    const row = q.rows[0];
    if (row.nlat == null) conflict('NURSE_LOCATION_UNKNOWN');
    return this.routes.compute({ lat: +row.nlat, lng: +row.nlng }, { lat: +row.plat, lng: +row.plng });
  }
}
