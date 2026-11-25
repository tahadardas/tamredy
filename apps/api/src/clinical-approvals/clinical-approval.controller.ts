import { Body, Controller, Get, Param, Post, Request, StreamableFile, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { AuthGuard, type AuthRequest, requireRole } from '../auth/auth.guard.js';
import { MAX_FILE_BYTES } from '../admin/doc-store.js';
import { ClinicalApprovalService } from './clinical-approval.service.js';
import { ClinicalDecisionDto, ClinicalEvidenceDto } from './clinical-approval.dto.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class ClinicalApprovalController {
  constructor(private readonly service: ClinicalApprovalService) {}

  @Post('requests/:id/clinical-evidence')
  @UseInterceptors(FileInterceptor('file',{limits:{fileSize:MAX_FILE_BYTES,files:1}}))
  upload(@Request() request:AuthRequest,@Param('id') id:string,@Body() dto:ClinicalEvidenceDto,
    @UploadedFile() file:{buffer:Buffer;originalname:string}) {
    requireRole(request.user!,'PATIENT');
    return this.service.upload(request.user!.id,id,dto,file);
  }

  @Get('clinical-reviews/pending')
  pending(@Request() request:AuthRequest) {
    requireRole(request.user!,'CLINICAL_REVIEWER');
    return this.service.listPending(request.user!.id);
  }

  @Get('clinical-reviews/evidence/:id')
  async evidence(@Request() request:AuthRequest,@Param('id') id:string) {
    requireRole(request.user!,'CLINICAL_REVIEWER');
    const evidence=await this.service.readEvidence(request.user!.id,id);
    return new StreamableFile(evidence.bytes,{type:evidence.row.mime_type,
      disposition:`attachment; filename*=UTF-8''${encodeURIComponent(evidence.row.original_filename)}`});
  }

  @Post('clinical-reviews/:id/decision')
  decide(@Request() request:AuthRequest,@Param('id') id:string,@Body() dto:ClinicalDecisionDto) {
    requireRole(request.user!,'CLINICAL_REVIEWER');
    return this.service.decide(request.user!.id,id,dto);
  }
}
