import { Body, Controller, Get, Put, Request, UseGuards } from '@nestjs/common';
import { IsBoolean } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from './auth.guard.js';
import { DbService } from '../db/db.service.js';

class ConsentDto { @IsBoolean() optIn!: boolean; }

/** Patients choose whether to receive offers and marketing notifications (default: no). */
@Controller('v1/me') @UseGuards(AuthGuard)
export class MeController {
  constructor(private readonly db: DbService) {}
  @Get('marketing-consent') async get(@Request() r: AuthRequest) {
    requireRole(r.user!, 'PATIENT');
    return { optIn: (await this.db.query('SELECT marketing_opt_in FROM users WHERE id=$1', [r.user!.id])).rows[0].marketing_opt_in };
  }
  @Put('marketing-consent') async set(@Request() r: AuthRequest, @Body() d: ConsentDto) {
    requireRole(r.user!, 'PATIENT');
    await this.db.query('UPDATE users SET marketing_opt_in=$2 WHERE id=$1', [r.user!.id, d.optIn]);
    return { optIn: d.optIn };
  }
  @Get('active-request') async activeRequest(@Request() r: AuthRequest) {
    requireRole(r.user!, 'PATIENT');
    const q = await this.db.query(`
      SELECT cr.id, cr.status, cr.price_amount, cr.currency_code, cr.created_at, cr.address_text,
        ST_Y(cr.location::geometry) AS patient_lat, ST_X(cr.location::geometry) AS patient_lng,
        s.id AS service_id, s.title_ar AS service_title, s.code AS service_code, s.requires_prescription,
        b.id AS beneficiary_id, b.display_name AS beneficiary_name,
        a.id AS assignment_id, a.nurse_id,
        u.display_name AS nurse_name, u.phone_e164 AS nurse_phone,
        CASE WHEN cr.status = 'EN_ROUTE' AND nl.recorded_at > now() - interval '120 seconds' THEN ST_Y(nl.location::geometry) END AS nurse_lat,
        CASE WHEN cr.status = 'EN_ROUTE' AND nl.recorded_at > now() - interval '120 seconds' THEN ST_X(nl.location::geometry) END AS nurse_lng
      FROM care_requests cr
      JOIN services s ON s.id = cr.service_id
      JOIN beneficiaries b ON b.id = cr.beneficiary_id
      LEFT JOIN request_assignments a ON a.request_id = cr.id AND a.status = 'ACTIVE'
      LEFT JOIN nurses n ON n.id = a.nurse_id
      LEFT JOIN users u ON u.id = n.user_id
      LEFT JOIN nurse_locations nl ON nl.nurse_id = a.nurse_id
      WHERE cr.requester_user_id = $1
        AND cr.status IN ('REQUESTED', 'OFFERING', 'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE')
      ORDER BY cr.created_at DESC LIMIT 1
    `, [r.user!.id]);

    if (!q.rowCount) {
      return { hasActive: false, request: null };
    }
    return { hasActive: true, request: q.rows[0] };
  }
}
