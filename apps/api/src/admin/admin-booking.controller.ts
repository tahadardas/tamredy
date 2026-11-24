import { Body, Controller, Get, Patch, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { AdminBookingService } from './admin-booking.service.js';

@Controller('v1/admin/booking')
@UseGuards(AuthGuard)
export class AdminBookingController {
  constructor(private readonly booking: AdminBookingService) {}

  @Get('policies')
  async getPolicies(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return this.booking.getPolicies();
  }

  @Patch('policies')
  async updatePolicies(
    @Request() r: AuthRequest,
    @Body() body: Record<string, unknown>,
  ) {
    requireRole(r.user!, 'ADMIN');
    return this.booking.updatePolicies(r.user!.id, body);
  }

  @Get('requests')
  async listRequests(
    @Request() r: AuthRequest,
    @Query('bookingMode') bookingMode?: string,
    @Query('status') status?: string,
    @Query('limit') limit?: string,
  ) {
    requireRole(r.user!, 'ADMIN');
    return this.booking.listRequests({
      bookingMode,
      status,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Get('proposals')
  async listProposals(
    @Request() r: AuthRequest,
    @Query('status') status?: string,
    @Query('requestId') requestId?: string,
    @Query('nurseId') nurseId?: string,
  ) {
    requireRole(r.user!, 'ADMIN');
    return this.booking.listProposals({ status, requestId, nurseId });
  }

  @Get('analytics')
  async getAnalytics(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    return this.booking.getAnalytics();
  }
}
