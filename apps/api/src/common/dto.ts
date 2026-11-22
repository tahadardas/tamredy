import { IsBoolean, IsIn, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
export class LocationDto {
  @IsLatitude() latitude!: number;
  @IsLongitude() longitude!: number;
  @IsNumber() @Min(0) @Max(1000) accuracyMeters!: number;
}
export class CreateRequestDto extends LocationDto {
  @IsUUID() beneficiaryId!: string;
  @IsUUID() serviceId!: string;
  @IsIn(['GPS_CONFIRMED','MANUAL_PIN']) locationSource!: string;
  @IsString() @MaxLength(400) addressText!: string;
  @IsBoolean() nonEmergencyConfirmed!: boolean;
  @IsOptional() @IsString() @MaxLength(40) promoCode?: string;
}
export class AvailabilityDto {
  @IsIn(['AVAILABLE','OFFLINE','PAUSED']) availability!: 'AVAILABLE'|'OFFLINE'|'PAUSED';
}
export class ReviewDto {
  @IsNumber() @Min(1) @Max(5) stars!: number;
  @IsOptional() @IsString() @MaxLength(1200) comment?: string;
}
export class NurseReportDto {
  @IsIn(['NORMAL','ADDRESS_INCORRECT','NO_SHOW','SAFETY_CONCERN','PAYMENT_DISPUTE']) category!: string;
  @IsOptional() @IsString() @MaxLength(1200) note?: string;
  /** The nurse rates the patient too (1-5). */
  @IsOptional() @IsNumber() @Min(1) @Max(5) stars?: number;
}
