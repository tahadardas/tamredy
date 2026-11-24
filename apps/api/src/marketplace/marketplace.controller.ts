import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { MarketplaceService } from './marketplace.service.js';
import { ProposalsService } from './proposals.service.js';
import { MarketplaceQueryDto, SubmitProposalDto, WithdrawProposalDto } from './marketplace.dto.js';

@Controller('v1/marketplace')
@UseGuards(AuthGuard)
export class MarketplaceController {
  constructor(
    private readonly marketplace: MarketplaceService,
    private readonly proposals: ProposalsService,
  ) {}

  /**
   * Nurse browses available open requests in authorized regions.
   */
  @Get('requests')
  async listRequests(
    @Request() r: AuthRequest,
    @Query() query: MarketplaceQueryDto,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.marketplace.listOpenRequests(r.user!.id, query);
  }

  /**
   * Nurse views detailed medical requirements and earnings for an open request.
   */
  @Get('requests/:id')
  async getRequestDetails(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.marketplace.getRequestDetails(r.user!.id, requestId);
  }

  /**
   * Nurse submits a readiness proposal for an open request.
   */
  @Post('requests/:id/proposals')
  @HttpCode(201)
  async submitProposal(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
    @Body() dto: SubmitProposalDto,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.proposals.submitProposal(r.user!.id, requestId, dto);
  }

  /**
   * Nurse bookmarks a request.
   */
  @Post('requests/:id/save')
  @HttpCode(200)
  async saveRequest(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.marketplace.saveRequest(r.user!.id, requestId);
  }

  /**
   * Nurse removes a bookmark.
   */
  @Delete('requests/:id/save')
  @HttpCode(200)
  async unsaveRequest(
    @Request() r: AuthRequest,
    @Param('id') requestId: string,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.marketplace.unsaveRequest(r.user!.id, requestId);
  }

  /**
   * Nurse lists all submitted proposals (active, accepted, expired, withdrawn).
   */
  @Get('proposals/mine')
  async listMyProposals(
    @Request() r: AuthRequest,
    @Query('status') status?: string,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.proposals.listNurseProposals(r.user!.id, status);
  }

  /**
   * Nurse withdraws a pending proposal.
   */
  @Post('proposals/:id/withdraw')
  @HttpCode(200)
  async withdrawProposal(
    @Request() r: AuthRequest,
    @Param('id') proposalId: string,
    @Body() dto?: WithdrawProposalDto,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.proposals.withdrawProposal(r.user!.id, proposalId, dto);
  }
}
