import { Body, Controller, Get, Put, Request, UseGuards } from '@nestjs/common';
import { IsBoolean } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from './auth.guard.js';
import { DbService } from '../db/db.service.js';
import { RequestRecoveryService } from '../requests/request-recovery.service.js';

class ConsentDto { @IsBoolean() optIn!: boolean; }

/** Patients choose whether to receive offers and marketing notifications (default: no). */
@Controller('v1/me') @UseGuards(AuthGuard)
export class MeController {
  constructor(private readonly db: DbService, private readonly recovery: RequestRecoveryService) {}
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
    return this.recovery.patientState(r.user!.id);
  }
}
