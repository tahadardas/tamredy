import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Put, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { SafetyShiftDto } from './shifts.dto.js';
import { ShiftsService } from './shifts.service.js';

@Controller('v1/admin/safety/shifts')
@UseGuards(AuthGuard)
export class ShiftsController {
  constructor(private readonly shifts: ShiftsService) {}

  @Get() list(@Request() req: AuthRequest) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.shifts.list(req.user!.id);
  }

  @Post() create(@Request() req: AuthRequest, @Body() dto: SafetyShiftDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.shifts.save(req.user!.id,dto);
  }

  @Put(':id') edit(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string, @Body() dto: SafetyShiftDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.shifts.save(req.user!.id,dto,id);
  }

  @Delete(':id') cancel(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.shifts.cancel(req.user!.id,id);
  }

  @Post(':id/checkin') checkin(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.shifts.presence(req.user!.id,id,'checkin');
  }

  @Post(':id/heartbeat') heartbeat(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.shifts.presence(req.user!.id,id,'heartbeat');
  }

  @Post(':id/checkout') checkout(@Request() req: AuthRequest, @Param('id',ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.shifts.presence(req.user!.id,id,'checkout');
  }
}
