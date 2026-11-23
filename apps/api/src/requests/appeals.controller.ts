import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from '../auth/auth.guard.js';
import { ReviewAppealDto, SubmitAppealDto } from './appeals.dto.js';
import { AppealsService } from './appeals.service.js';

@Controller('v1') @UseGuards(AuthGuard)
export class AppealsController {
  constructor(private readonly appeals: AppealsService) {}

  @Post('cancellations/:id/appeals')
  submit(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SubmitAppealDto) {
    const user = request.user!;
    requireAnyRole(user, ['PATIENT','NURSE']);
    return this.appeals.submit(user.id, user.role === 'PATIENT' ? 'PATIENT' : 'NURSE', id, dto.description);
  }

  @Get('me/cancellation-appeals')
  own(@Request() request: AuthRequest) {
    requireAnyRole(request.user!, ['PATIENT','NURSE']);
    return this.appeals.own(request.user!.id);
  }

  @Get('admin/cancellation-appeals')
  queue(@Request() request: AuthRequest) {
    requireRole(request.user!, 'ADMIN');
    return this.appeals.queue();
  }

  @Post('admin/cancellation-appeals/:id/review')
  review(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReviewAppealDto) {
    requireRole(request.user!, 'ADMIN');
    return this.appeals.review(request.user!.id,id,dto);
  }
}
