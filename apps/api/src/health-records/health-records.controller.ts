import { Body, Controller, Get, HttpCode, Param, Post, Put, Query, Request, UseGuards } from '@nestjs/common';
import { IsArray, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, ValidateNested } from 'class-validator';
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

  @IsOptional()
  @IsIn(['NURSE_VISIT', 'PATIENT_SELF_REPORT', 'CLINICAL_VERIFIED'])
  source?: 'NURSE_VISIT' | 'PATIENT_SELF_REPORT' | 'CLINICAL_VERIFIED';
}

class RecordObservationsDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SingleObservationDto)
  observations!: SingleObservationDto[];

  @IsOptional()
  @IsUUID()
  requestId?: string;
}

class SaveVisitNoteDto implements VisitNoteInputDto {
  @IsArray()
  servicesPerformed!: Array<{ serviceId: string; titleAr: string; status: 'COMPLETED' | 'SKIPPED'; skipReason?: string }>;

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
  isDraft?: boolean;
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
  ) {
    const numLimit = limit ? parseInt(limit, 10) : 50;
    return this.health.getObservationTimeline(r.user!.id, beneficiaryId, observationType, numLimit);
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
}
