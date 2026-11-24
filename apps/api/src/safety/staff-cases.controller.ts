import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { SafetyCaseActionDto } from './staff-cases.dto.js';
import { StaffCasesService } from './staff-cases.service.js';

@Controller('v1/admin/safety')
@UseGuards(AuthGuard)
export class StaffCasesController {
  constructor(private readonly service: StaffCasesService) {}

  @Get('dashboard') dashboard(@Request() request: AuthRequest) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.dashboard(request.user!.id);
  }

  @Get('events') list(@Request() request: AuthRequest) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.list(request.user!.id);
  }

  @Get('events/:id') detail(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.detail(request.user!.id, id);
  }

  @Post('events/:id/acknowledge')
  acknowledge(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyCaseActionDto) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.act(request.user!.id, id, 'ACKNOWLEDGED', dto);
  }

  @Post('events/:id/escalate')
  escalate(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyCaseActionDto) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.act(request.user!.id, id, 'ESCALATED', dto);
  }

  @Post('events/:id/resolve')
  resolve(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyCaseActionDto) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.act(request.user!.id, id, 'RESOLVED', dto);
  }
}
