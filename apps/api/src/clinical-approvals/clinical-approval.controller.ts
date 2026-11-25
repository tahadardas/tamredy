import { Body, Controller, Get, Header, Param, ParseUUIDPipe, Post, Request, StreamableFile, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { AuthGuard, type AuthRequest } from '../auth/auth.guard.js';
import { MAX_FILE_BYTES } from '../admin/doc-store.js';
import { ClinicalApprovalService } from './clinical-approval.service.js';
import { ClinicalDecisionDto, ClinicalEvidenceDto } from './clinical-approval.dto.js';
import { requirePermission } from '../auth/permissions.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class ClinicalApprovalController {
  constructor(private readonly service: ClinicalApprovalService) {}

  @Post('requests/:id/clinical-evidence')
  @UseInterceptors(FileInterceptor('file',{limits:{fileSize:MAX_FILE_BYTES,files:1}}))
  upload(@Request() request:AuthRequest,@Param('id',ParseUUIDPipe) id:string,@Body() dto:ClinicalEvidenceDto,
    @UploadedFile() file:{buffer:Buffer;originalname:string}) {
    requirePermission(request.user!,'health_record.write_own');
    return this.service.upload(request.user!.id,id,dto,file);
  }

  @Get('clinical-reviews/pending')
  pending(@Request() request:AuthRequest) {
    requirePermission(request.user!,'clinical_review.queue');
    return this.service.listPending(request.user!.id);
  }

  @Get('clinical-reviews/evidence/:id')
  @Header('Cache-Control','no-store')
  async evidence(@Request() request:AuthRequest,@Param('id',ParseUUIDPipe) id:string) {
    requirePermission(request.user!,'clinical_review.evidence');
    const evidence=await this.service.readEvidence(request.user!.id,id);
    return new StreamableFile(evidence.bytes,{type:evidence.row.mime_type,
      disposition:`attachment; filename*=UTF-8''${encodeURIComponent(evidence.row.original_filename)}`});
  }

  @Get('clinical-reviews/:id/evidence')
  listEvidence(@Request() request:AuthRequest,@Param('id',ParseUUIDPipe) id:string) {
    requirePermission(request.user!,'clinical_review.evidence');
    return this.service.listEvidence(request.user!.id,id);
  }

  @Post('clinical-reviews/:id/decision')
  decide(@Request() request:AuthRequest,@Param('id',ParseUUIDPipe) id:string,@Body() dto:ClinicalDecisionDto) {
    requirePermission(request.user!,'clinical_review.decide');
    return this.service.decide(request.user!.id,id,dto);
  }
}
