import { Controller, Get, Param, ParseUUIDPipe, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { CommitmentService } from './commitment.service.js';

@Controller('v1') @UseGuards(AuthGuard)
export class CommitmentController {
  constructor(private readonly commitment: CommitmentService) {}

  @Get('me/commitment')
  mine(@Request() request: AuthRequest) {
    requireRole(request.user!, 'PATIENT');
    return this.commitment.ownHistory(request.user!.id);
  }

  @Get('nurse/offers/:id/commitment')
  offer(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireRole(request.user!, 'NURSE');
    return this.commitment.forActiveOffer(request.user!.id,id);
  }
}
