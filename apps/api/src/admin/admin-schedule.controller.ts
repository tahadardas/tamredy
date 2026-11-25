import { BadRequestException, Controller, Delete, Get, Header, Param, ParseUUIDPipe, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { AdminScheduleService } from './admin-schedule.service.js';

function pageNumber(value = '1') {
  const page = Number(value);
  if (!Number.isSafeInteger(page) || page < 1 || page > 1000000) throw new BadRequestException({ code: 'INVALID_PAGINATION' });
  return page;
}

@Controller('v1/admin/schedule')
@UseGuards(AuthGuard)
export class AdminScheduleController {
  constructor(private readonly schedule: AdminScheduleService) {}

  @Get('visits')
  @Header('Cache-Control', 'private, no-store')
  visits(@Request() r: AuthRequest, @Query('removed') removed?: string, @Query('page') page?: string) {
    requireRole(r.user!, 'ADMIN');
    return this.schedule.list(removed === 'true', pageNumber(page));
  }

  @Get('care-plans')
  @Header('Cache-Control', 'private, no-store')
  plans(@Request() r: AuthRequest, @Query('page') page?: string) {
    requireRole(r.user!, 'ADMIN');
    return this.schedule.plans(pageNumber(page));
  }

  @Delete('visits/:id')
  remove(@Request() r: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireRole(r.user!, 'ADMIN');
    return this.schedule.remove(r.user!.id, id);
  }
}
