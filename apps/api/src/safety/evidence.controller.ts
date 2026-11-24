import { Body, Controller, Get, Header, Param, ParseUUIDPipe, Post, Request, StreamableFile, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { EvidenceApprovalDto, EvidenceExportDto } from './evidence.dto.js';
import { EvidenceService } from './evidence.service.js';

@Controller('v1/admin/safety')
@UseGuards(AuthGuard)
export class EvidenceController {
  constructor(private readonly evidence: EvidenceService) {}

  @Post('events/:id/export-approvals')
  approve(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: EvidenceApprovalDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.evidence.approve(req.user!.id,id,dto);
  }

  @Post('events/:id/export')
  generate(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: EvidenceExportDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.evidence.generate(req.user!.id,id,dto.approvalId);
  }

  @Get('exports/:id')
  @Header('Cache-Control','no-store')
  async download(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return new StreamableFile(await this.evidence.download(req.user!.id,id), {
      type:'application/json',disposition:`attachment; filename="guardian-evidence-${id}.json"`,
    });
  }
}
