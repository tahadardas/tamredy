import { Body, Controller, Get, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { IsDateString, IsIn, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { CarePlansService } from './care-plans.service.js';

class CreateCarePlanInputDto {
  @IsUUID()
  beneficiaryId!: string;

  @IsUUID()
  primaryServiceId!: string;

  @IsIn(['DAILY', 'EVERY_OTHER_DAY', 'THREE_TIMES_A_WEEK', 'SPECIFIC_DAYS'])
  frequencyType!: 'DAILY' | 'EVERY_OTHER_DAY' | 'THREE_TIMES_A_WEEK' | 'SPECIFIC_DAYS';

  @IsOptional()
  frequencyMeta?: { weekdays?: number[] };

  @IsString()
  preferredTimeOfDay!: string; // 'HH:MM'

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(100)
  totalVisitsPlanned?: number;

  @IsDateString()
  startDate!: string;

  @IsOptional()
  @IsDateString()
  endDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;

  @IsString()
  @MaxLength(400)
  addressText!: string;

  @IsLatitude()
  latitude!: number;

  @IsLongitude()
  longitude!: number;

  @IsOptional()
  @IsString()
  locationSource?: string;
}

@Controller('v1/care-plans')
@UseGuards(AuthGuard)
export class CarePlansController {
  constructor(private readonly carePlans: CarePlansService) {}

  @Post()
  @HttpCode(201)
  async create(
    @Request() r: AuthRequest,
    @Body() body: CreateCarePlanInputDto,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.carePlans.createCarePlan(r.user!.id, body);
  }

  @Get()
  async list(@Request() r: AuthRequest) {
    requireRole(r.user!, 'PATIENT');
    return this.carePlans.listCarePlans(r.user!.id);
  }

  @Get(':id')
  async getOne(
    @Request() r: AuthRequest,
    @Param('id') planId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.carePlans.getCarePlan(r.user!.id, planId);
  }

  @Post(':id/pause')
  @HttpCode(200)
  async pause(
    @Request() r: AuthRequest,
    @Param('id') planId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.carePlans.pauseCarePlan(r.user!.id, planId);
  }

  @Post(':id/resume')
  @HttpCode(200)
  async resume(
    @Request() r: AuthRequest,
    @Param('id') planId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.carePlans.resumeCarePlan(r.user!.id, planId);
  }

  @Post(':id/cancel')
  @HttpCode(200)
  async cancel(
    @Request() r: AuthRequest,
    @Param('id') planId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.carePlans.cancelCarePlan(r.user!.id, planId);
  }
}
