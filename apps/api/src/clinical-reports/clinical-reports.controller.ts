import { Controller, Get, Header, Param, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest } from '../auth/auth.guard.js';
import { ClinicalReportsService } from './clinical-reports.service.js';

@Controller('v1')
export class ClinicalReportsController {
  constructor(private readonly reports: ClinicalReportsService) {}

  @Get('visits/:requestId/clinical-report')
  @UseGuards(AuthGuard)
  async getReport(
    @Request() r: AuthRequest,
    @Param('requestId') requestId: string,
  ) {
    return this.reports.generateReport(r.user!.id, requestId);
  }

  @Get('visits/:requestId/clinical-report/html')
  @UseGuards(AuthGuard)
  @Header('Content-Type', 'text/html; charset=utf-8')
  async getReportHtml(
    @Request() r: AuthRequest,
    @Param('requestId') requestId: string,
  ) {
    return this.reports.renderReportHtml(r.user!.id, requestId);
  }

  @Get('clinical-reports/verify/:token')
  async verifyReport(@Param('token') token: string) {
    return this.reports.verifyReportToken(token);
  }
}
