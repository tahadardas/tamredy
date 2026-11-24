import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { ReportSosDto, SafeAbortDto, SafetyCheckinResponseDto, SafetyLocationBatchDto, StartSafetySessionDto } from './safety.dto.js';
import { CheckinsService } from './checkins.service.js';
import { SafeAbortService } from './safe-abort.service.js';
import { SafetyService } from './safety.service.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class SafetyController {
  constructor(private readonly safety: SafetyService, private readonly checkins: CheckinsService, private readonly safeAbort: SafeAbortService) {}

  @Get('safety/me/status') async status(@Request() req: AuthRequest) {
    requireRole(req.user!, 'NURSE');
    return { session: await this.safety.status(req.user!.id) };
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

  @Get('nurse/safety/sessions/:id/checkin')
  pendingCheckin(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireRole(req.user!, 'NURSE');
    return this.checkins.pending(req.user!.id, id);
  }

  @Post('nurse/safety/sessions/:id/checkin')
  respondCheckin(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafetyCheckinResponseDto) {
    requireRole(req.user!, 'NURSE');
    return this.checkins.respond(req.user!.id, id, dto);
  }

  @Post('nurse/safety/assignments/:id/abort')
  abort(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SafeAbortDto) {
    requireRole(req.user!, 'NURSE');
    return this.safeAbort.abort(req.user!.id, id, dto);
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
