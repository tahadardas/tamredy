import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { TrustService } from './trust.service.js';

class BlockUserDto {
  @IsUUID()
  targetUserId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  reasonCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  privateNote?: string;
}

class CreateReportDto {
  @IsOptional()
  @IsUUID()
  reportedUserId?: string;

  @IsOptional()
  @IsUUID()
  requestId?: string;

  @IsIn(['TECHNICAL_SUPPORT', 'FINANCIAL_DISPUTE', 'CLINICAL_COMPLAINT', 'SAFETY_INCIDENT', 'COMMITMENT_APPEAL'])
  reportType!: 'TECHNICAL_SUPPORT' | 'FINANCIAL_DISPUTE' | 'CLINICAL_COMPLAINT' | 'SAFETY_INCIDENT' | 'COMMITMENT_APPEAL';

  @IsOptional()
  @IsIn(['LOW', 'STANDARD', 'URGENT', 'CRITICAL_SAFETY'])
  severity?: 'LOW' | 'STANDARD' | 'URGENT' | 'CRITICAL_SAFETY';

  @IsString()
  @MaxLength(200)
  title!: string;

  @IsString()
  @MaxLength(3000)
  description!: string;
}

@Controller('v1')
@UseGuards(AuthGuard)
export class TrustController {
  constructor(private readonly trust: TrustService) {}

  @Post('blocks')
  @HttpCode(201)
  async block(@Request() r: AuthRequest, @Body() body: BlockUserDto) {
    return this.trust.blockUser(r.user!.id, body);
  }

  @Get('blocks')
  async listBlocks(@Request() r: AuthRequest) {
    return this.trust.listBlockedUsers(r.user!.id);
  }

  @Delete('blocks/:targetUserId')
  @HttpCode(200)
  async unblock(@Request() r: AuthRequest, @Param('targetUserId') targetUserId: string) {
    return this.trust.unblockUser(r.user!.id, targetUserId);
  }

  @Post('reports')
  @HttpCode(201)
  async submitReport(@Request() r: AuthRequest, @Body() body: CreateReportDto) {
    return this.trust.createReport(r.user!.id, body);
  }

  @Get('admin/support-reports')
  async listReports(
    @Request() r: AuthRequest,
    @Query('status') status?: string,
    @Query('type') type?: string,
  ) {
    requireRole(r.user!, 'ADMIN');
    return this.trust.listReports({ status, type });
  }

  @Post('trust/reports/:id/triage')
  @HttpCode(200)
  async triageReport(
    @Request() r: AuthRequest,
    @Param('id') reportId: string,
    @Body() body: { status: string; resolutionNote?: string },
  ) {
    requireRole(r.user!, 'ADMIN');
    return this.trust.triageReport(reportId, r.user!.id, body.status, body.resolutionNote);
  }
}
