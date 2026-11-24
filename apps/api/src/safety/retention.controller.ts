import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { LegalHoldDto, ReleaseHoldDto, RetentionPolicyDto, RetentionService } from './retention.js';

@Controller('v1/admin/safety')
@UseGuards(AuthGuard)
export class RetentionController {
  constructor(private readonly retention: RetentionService) {}

  @Get('retention-policy') status(@Request() req: AuthRequest) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.retention.status(req.user!.id);
  }

  @Post('retention-policy') configure(@Request() req: AuthRequest, @Body() dto: RetentionPolicyDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.retention.configure(req.user!.id,dto);
  }

  @Get('events/:id/legal-holds') holds(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.retention.holds(req.user!.id,id);
  }

  @Post('events/:id/legal-holds') hold(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string, @Body() dto: LegalHoldDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.retention.hold(req.user!.id,id,dto);
  }

  @Post('events/:id/legal-holds/:holdId/release')
  release(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string,
    @Param('holdId',ParseUUIDPipe) holdId: string, @Body() dto: ReleaseHoldDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.retention.release(req.user!.id,id,holdId,dto);
  }
}
