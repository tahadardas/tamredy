import { Controller, Get, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { NurseFinancialService } from './nurse-financial.service.js';

@Controller('v1/nurse/financial')
@UseGuards(AuthGuard)
export class NurseFinancialController {
  constructor(private readonly financial: NurseFinancialService) {}

  @Get('summary')
  async getSummary(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    return this.financial.getFinancialSummary(r.user!.id);
  }

  @Get('ledger')
  async getLedger(@Request() r: AuthRequest, @Query('limit') limit?: string) {
    requireRole(r.user!, 'NURSE');
    const numLimit = limit ? parseInt(limit, 10) : 50;
    return this.financial.getLedgerHistory(r.user!.id, numLimit);
  }
}
