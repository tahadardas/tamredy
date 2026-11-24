import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { ReportSosDto, SafetyLocationBatchDto, StartSafetySessionDto } from './safety.dto.js';
import { SafetyService } from './safety.service.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class SafetyController {
  constructor(private readonly safety: SafetyService) {}

  @Get('safety/me/status') status(@Request() req: AuthRequest) {
    requireRole(req.user!, 'NURSE');
    return this.safety.status(req.user!.id);
  }

  @Post('nurse/safety/sessions/start') start(@Request() req: AuthRequest, @Body() dto: StartSafetySessionDto) {
    requireRole(req.user!, 'NURSE');
    return this.safety.start(req.user!.id, dto.assignmentId);
  }

  @Post('nurse/safety/sessions/:id/locations/batch')
  locations(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyLocationBatchDto) {
    requireRole(req.user!, 'NURSE');
    return this.safety.upload(req.user!.id, id, dto);
  }

  @Post('nurse/safety/sessions/:id/checkout')
  checkout(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireRole(req.user!, 'NURSE');
    return this.safety.checkout(req.user!.id, id);
  }

  @Post('safety/sos') sos(@Request() req: AuthRequest, @Body() dto: ReportSosDto) {
    requireRole(req.user!, 'NURSE');
    return this.safety.sos(req.user!.id, dto);
  }

  @Get('safety/events/:id') event(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireRole(req.user!, 'NURSE');
    return this.safety.event(req.user!.id, id);
  }
}
