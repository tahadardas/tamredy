import { IsArray, IsBoolean, IsISO8601, Matches, IsIn, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class LocationDto {
  @IsLatitude() latitude!: number;
  @IsLongitude() longitude!: number;
  @IsNumber() @Min(0) @Max(1000) accuracyMeters!: number;
}

export class RequestItemInputDto {
  @IsUUID() serviceId!: string;
  @IsOptional() @IsNumber() @Min(1) @Max(10) quantity?: number;
}

export class CreateRequestDto extends LocationDto {
  @IsOptional() @IsISO8601({ strict: true }) @Matches(/(?:Z|[+-]\d{2}:\d{2})$/i) scheduledAt?: string;
  @IsUUID() beneficiaryId!: string;
  @IsOptional() @IsUUID() serviceId?: string;
  @IsOptional() @IsArray() serviceIds?: string[];
  @IsOptional() @IsArray() @ValidateNested({ each: true }) @Type(() => RequestItemInputDto) items?: RequestItemInputDto[];
  @IsIn(['GPS_CONFIRMED','MANUAL_PIN']) locationSource!: string;
  @IsString() @MaxLength(400) addressText!: string;
  @IsBoolean() nonEmergencyConfirmed!: boolean;
  @IsOptional() @IsBoolean() prescriptionConfirmed?: boolean;
  @IsOptional() @IsString() @MaxLength(40) promoCode?: string;
}
export class AvailabilityDto {
  @IsIn(['AVAILABLE','OFFLINE','PAUSED']) availability!: 'AVAILABLE'|'OFFLINE'|'PAUSED';
}
export class ReviewDto {
  @IsNumber() @Min(1) @Max(5) stars!: number;
  @IsOptional() @IsString() @MaxLength(1200) comment?: string;
  @IsOptional() @IsNumber() @Min(1) @Max(5) punctualityStars?: number;
  @IsOptional() @IsNumber() @Min(1) @Max(5) conductStars?: number;
  @IsOptional() @IsNumber() @Min(1) @Max(5) clinicalStars?: number;
  @IsOptional() @IsNumber() @Min(1) @Max(5) hygieneStars?: number;
  @IsOptional() @IsNumber() @Min(1) @Max(5) overallStars?: number;
}
export class NurseReportDto {
  @IsIn(['NORMAL','ADDRESS_INCORRECT','NO_SHOW','SAFETY_CONCERN','PAYMENT_DISPUTE']) category!: string;
  @IsOptional() @IsString() @MaxLength(1200) note?: string;
  /** The nurse rates the patient too (1-5). */
  @IsOptional() @IsNumber() @Min(1) @Max(5) stars?: number;
}
