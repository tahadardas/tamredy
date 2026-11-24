import { Body, Controller, Get, Post, Put, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from '../auth/auth.guard.js';
import { NightPolicyDto, NightPolicyService, NightPreferenceDto } from './night-policy.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class NightPolicyController {
  constructor(private readonly service: NightPolicyService) {}

  @Get('admin/safety/night-policy') rules(@Request() req: AuthRequest) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.rules(req.user!.id);
  }

  @Post('admin/safety/night-policy') publish(@Request() req: AuthRequest, @Body() dto: NightPolicyDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.publish(req.user!.id,dto);
  }

  @Get('nurse/safety/night-preference') preference(@Request() req: AuthRequest) {
    requireRole(req.user!, 'NURSE');
    return this.service.preference(req.user!.id);
  }

  @Put('nurse/safety/night-preference') update(@Request() req: AuthRequest, @Body() dto: NightPreferenceDto) {
    requireRole(req.user!, 'NURSE');
    return this.service.preferenceUpdate(req.user!.id,dto);
  }
}
