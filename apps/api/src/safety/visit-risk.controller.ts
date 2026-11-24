import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from '../auth/auth.guard.js';
import { ConfirmVisitCompanionDto, VisitCompanionDto, VisitRiskDto, VisitRiskService } from './visit-risk.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class VisitRiskController {
  constructor(private readonly service: VisitRiskService) {}

  @Post('admin/safety/requests/:id/risk')
  assess(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string, @Body() dto: VisitRiskDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.assess(req.user!.id,id,dto);
  }

  @Post('admin/safety/requests/:id/companion')
  nominate(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string, @Body() dto: VisitCompanionDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.nominate(req.user!.id,id,dto);
  }

  @Get('nurse/safety/companions')
  pending(@Request() req: AuthRequest) {
    requireRole(req.user!, 'NURSE');
    return this.service.pending(req.user!.id);
  }

  @Post('nurse/safety/companions/:id/confirm')
  confirm(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string, @Body() dto: ConfirmVisitCompanionDto) {
    requireRole(req.user!, 'NURSE');
    return this.service.confirm(req.user!.id,id,dto.nurseId);
  }
}
