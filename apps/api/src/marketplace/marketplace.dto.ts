import { IsArray, IsBoolean, IsIn, IsISO8601, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';

export class SubmitProposalDto {
  @IsOptional()
  @IsISO8601({ strict: true })
  proposedArrivalAt?: string;

  @IsOptional()
  @IsNumber()
  @Min(5)
  @Max(1440)
  arrivalMinutes?: number;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;
}

export class UpdateProposalDto {
  @IsOptional()
  @IsISO8601({ strict: true })
  proposedArrivalAt?: string;

  @IsOptional()
  @IsNumber()
  @Min(5)
  @Max(1440)
  arrivalMinutes?: number;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;
}

export class WithdrawProposalDto {
  @IsOptional()
  @IsString()
  @MaxLength(300)
  reason?: string;
}

export class AcceptProposalDto {
  @IsOptional()
  @IsNumber()
  proposalVersion?: number;

  @IsOptional()
  @IsNumber()
  requestVersion?: number;
}

export class SwitchBookingModeDto {
  @IsIn(['OPEN', 'SCHEDULED', 'INSTANT'])
  bookingMode!: 'OPEN' | 'SCHEDULED' | 'INSTANT';

  @IsOptional()
  @IsNumber()
  @Min(15)
  @Max(1440)
  openDurationMinutes?: number;

  @IsOptional()
  @IsISO8601({ strict: true })
  latestAcceptableArrivalAt?: string;

  @IsOptional()
  @IsISO8601({ strict: true })
  scheduledAt?: string;
}

export class ExtendOpenRequestDto {
  @IsNumber()
  @Min(15)
  @Max(720)
  additionalMinutes!: number;
}

export class MarketplaceQueryDto {
  @IsOptional()
  @IsIn(['nearest', 'newest', 'oldest', 'highest_earning', 'arrival_time'])
  sortBy?: 'nearest' | 'newest' | 'oldest' | 'highest_earning' | 'arrival_time';

  @IsOptional()
  @IsUUID()
  serviceId?: string;

  @IsOptional()
  @IsUUID()
  regionId?: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(100)
  maxDistanceKm?: number;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(100)
  limit?: number;

  @IsOptional()
  @IsString()
  cursor?: string;
}
