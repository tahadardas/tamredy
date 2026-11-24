import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { SafetyCaseActionDto } from './staff-cases.dto.js';
import { StaffCasesService } from './staff-cases.service.js';

@Controller('v1/admin/safety/events')
@UseGuards(AuthGuard)
export class StaffCasesController {
  constructor(private readonly service: StaffCasesService) {}

  @Get() list(@Request() request: AuthRequest) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.list(request.user!.id);
  }

  @Get(':id') detail(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.detail(request.user!.id, id);
  }

  @Post(':id/acknowledge')
  acknowledge(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyCaseActionDto) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.act(request.user!.id, id, 'ACKNOWLEDGED', dto);
  }

  @Post(':id/escalate')
  escalate(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyCaseActionDto) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.act(request.user!.id, id, 'ESCALATED', dto);
  }

  @Post(':id/resolve')
  resolve(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyCaseActionDto) {
    requireAnyRole(request.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    return this.service.act(request.user!.id, id, 'RESOLVED', dto);
  }
}
