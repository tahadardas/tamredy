import { Body, Controller, Get, HttpCode, Param, Post, Put, Query, Request, UseGuards } from '@nestjs/common';
import { ArrayMaxSize, IsArray, IsBoolean, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { HealthRecordsService, ObservationInputDto, UpdateBeneficiaryProfileDto, VisitNoteInputDto } from './health-records.service.js';

class SingleObservationDto implements ObservationInputDto {
  @IsString()
  observationType!: string;

  @IsNumber()
  numericValue!: number;

  @IsOptional()
  @IsString()
  measuredAt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;

  @IsOptional() @IsString() @MaxLength(100) textValue?: string;
  @IsOptional() @IsString() @MaxLength(30) unit?: string;

  @IsOptional()
  @IsIn(['NURSE_VISIT', 'PATIENT_SELF_REPORT', 'CLINICAL_VERIFIED'])
  source?: 'NURSE_VISIT' | 'PATIENT_SELF_REPORT' | 'CLINICAL_VERIFIED';
}

class RecordObservationsDto {
  @IsArray()
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => SingleObservationDto)
  observations!: SingleObservationDto[];

  @IsOptional()
  @IsUUID()
  requestId?: string;
}

class SaveVisitNoteDto implements VisitNoteInputDto {
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  servicesPerformed?: Array<{ serviceId: string; titleAr: string; status: 'COMPLETED' | 'SKIPPED'; skipReason?: string }>;

  @IsString()
  @MaxLength(4000)
  clinicalNotes!: string;

  @IsOptional()
  @IsArray()
  materialsUsed?: Array<{ name: string; quantity: number }>;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  patientResponse?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  followupRecommendations?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  amendmentReason?: string;

  @IsOptional()
  @IsBoolean()
  isDraft?: boolean;
}

class CompatibilityObservationsDto extends RecordObservationsDto {
  @IsUUID() requestId!: string;
  @IsOptional() @IsUUID() beneficiaryId?: string;
}

class CompatibilityVisitNoteDto extends SaveVisitNoteDto {
  @IsUUID() requestId!: string;
}

@Controller('v1')
@UseGuards(AuthGuard)
export class HealthRecordsController {
  constructor(private readonly health: HealthRecordsService) {}

  @Get('beneficiaries/:id/health-record')
  async getProfile(
    @Request() r: AuthRequest,
    @Param('id') beneficiaryId: string,
    @Query('requestId') requestId?: string,
  ) {
    return this.health.getBeneficiaryProfile(r.user!.id, beneficiaryId, requestId);
  }

  @Put('beneficiaries/:id/health-record')
  async updateProfile(
    @Request() r: AuthRequest,
    @Param('id') beneficiaryId: string,
    @Body() body: UpdateBeneficiaryProfileDto,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.health.updateBeneficiaryProfile(r.user!.id, beneficiaryId, body);
  }

  @Get('beneficiaries/:id/observations')
  async getObservations(
    @Request() r: AuthRequest,
    @Param('id') beneficiaryId: string,
    @Query('type') observationType?: string,
    @Query('limit') limit?: string,
    @Query('requestId') requestId?: string,
  ) {
    const numLimit = limit ? parseInt(limit, 10) : 50;
    return this.health.getObservationTimeline(r.user!.id, beneficiaryId, observationType, numLimit, requestId);
  }

  @Post('beneficiaries/:id/observations')
  @HttpCode(201)
  async recordObservations(
    @Request() r: AuthRequest,
    @Param('id') beneficiaryId: string,
    @Body() body: RecordObservationsDto,
  ) {
    return this.health.recordObservations(r.user!.id, beneficiaryId, body.requestId, body.observations);
  }

  @Get('visits/:requestId/form-config')
  async getFormConfig(
    @Request() r: AuthRequest,
    @Param('requestId') requestId: string,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.health.getNurseFormConfig(requestId, r.user!.id);
  }

  @Post('visits/:requestId/clinical-notes')
  @HttpCode(201)
  async saveVisitNotes(
    @Request() r: AuthRequest,
    @Param('requestId') requestId: string,
    @Body() body: SaveVisitNoteDto,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.health.saveVisitNote(r.user!.id, requestId, body, body.isDraft);
  }

  @Get('visits/:requestId/clinical-notes')
  async getVisitNotes(
    @Request() r: AuthRequest,
    @Param('requestId') requestId: string,
  ) {
    return this.health.getVisitNote(r.user!.id, requestId);
  }

  @Post('health-records/observations')
  @HttpCode(201)
  async postHealthObservations(
    @Request() r: AuthRequest,
    @Body() body: CompatibilityObservationsDto,
  ) {
    return this.health.recordObservations(r.user!.id, body.beneficiaryId, body.requestId, body.observations);
  }

  @Post('health-records/notes')
  @HttpCode(201)
  async postHealthNotes(
    @Request() r: AuthRequest,
    @Body() body: CompatibilityVisitNoteDto,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.health.saveVisitNote(r.user!.id, body.requestId, body, body.isDraft);
  }

  @Get('health-records/profiles')
  async getHealthProfiles(
    @Request() r: AuthRequest,
    @Query('beneficiaryId') beneficiaryId?: string,
  ) {
    if (beneficiaryId) {
      return this.health.getBeneficiaryProfile(r.user!.id, beneficiaryId);
    }
    return this.health.listBeneficiaries(r.user!.id);
  }
}
