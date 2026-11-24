import { Body, Controller, Get, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { ProposalsService } from './proposals.service.js';
import { AssignmentService } from './assignment.service.js';
import { AcceptProposalDto } from './marketplace.dto.js';

@Controller('v1/requests')
@UseGuards(AuthGuard)
export class ProposalsController {
  constructor(
    private readonly proposals: ProposalsService,
    private readonly assignment: AssignmentService,
  ) {}

  /**
   * Patient lists all readiness proposals received for their open request.
   */
  @Get(':id/proposals')
  async listProposals(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.proposals.listRequestProposals(r.user!.id, requestId);
  }

  /**
   * Patient accepts a readiness proposal, assigning the request atomically.
   */
  @Post(':id/proposals/:proposalId/accept')
  @HttpCode(200)
  async acceptProposal(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
    @Param('proposalId') proposalId: string,
    @Body() dto?: AcceptProposalDto,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.assignment.acceptProposal(r.user!.id, requestId, proposalId, dto);
  }

  /**
   * Patient declines a proposal.
   */
  @Post(':id/proposals/:proposalId/decline')
  @HttpCode(200)
  async declineProposal(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
    @Param('proposalId') proposalId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.proposals.declineProposal(r.user!.id, requestId, proposalId);
  }
}
