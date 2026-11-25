import { Controller, Get, Header, Param, ParseUUIDPipe, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { RequestRecordService } from './request-record.service.js';

@Controller('v1/admin/requests')
@UseGuards(AuthGuard)
export class RequestRecordController {
  constructor(private readonly records: RequestRecordService) {}

  @Get(':id/visit-record')
  @Header('Cache-Control','private, no-store')
  get(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) request: string) {
    requireRole(req.user!, 'ADMIN');
    return this.records.get(req.user!.id,request);
  }
}
