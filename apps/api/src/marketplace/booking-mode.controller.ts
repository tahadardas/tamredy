import { Body, Controller, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { BookingModeService } from './booking-mode.service.js';
import { ExtendOpenRequestDto, SwitchBookingModeDto } from './marketplace.dto.js';

@Controller('v1/requests')
@UseGuards(AuthGuard)
export class BookingModeController {
  constructor(private readonly bookingMode: BookingModeService) {}

  /**
   * Patient converts request booking mode (e.g. Instant -> Open Marketplace or Instant -> Scheduled).
   */
  @Post(':id/booking-mode')
  @HttpCode(200)
  async switchBookingMode(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
    @Body() dto: SwitchBookingModeDto,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.bookingMode.switchBookingMode(r.user!.id, requestId, dto);
  }

  /**
   * Patient restarts Instant Search round after search timeout.
   */
  @Post(':id/retry-dispatch')
  @HttpCode(200)
  async retryDispatch(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.bookingMode.retryInstantDispatch(r.user!.id, requestId);
  }

  /**
   * Patient extends the waiting window of an open request.
   */
  @Post(':id/open/extend')
  @HttpCode(200)
  async extendOpen(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
    @Body() dto: ExtendOpenRequestDto,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.bookingMode.extendOpenRequest(r.user!.id, requestId, dto);
  }
}
