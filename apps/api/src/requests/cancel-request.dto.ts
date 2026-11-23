import { IsBoolean, IsIn, IsInt, IsOptional, IsString, MaxLength, Min } from 'class-validator';

export const cancellationReasons = [
  'NO_LONGER_NEEDED', 'CREATED_BY_MISTAKE', 'FOUND_ANOTHER_NURSE', 'TIME_NOT_SUITABLE',
  'CHANGE_SERVICE_OR_LOCATION', 'WAITED_TOO_LONG', 'HEALTH_CIRCUMSTANCE_CHANGED', 'OTHER',
  'SYSTEM_OR_LOCATION_ERROR',
] as const;

export class CancelRequestDto {
  @IsOptional() @IsIn(cancellationReasons) reasonCode?: typeof cancellationReasons[number];
  @IsOptional() @IsString() @MaxLength(500) reasonNote?: string;
  @IsOptional() @IsString() @MaxLength(128) idempotencyKey?: string;
  @IsOptional() @IsInt() @Min(1) expectedVersion?: number;
  @IsOptional() @IsBoolean() policyAcknowledged?: boolean;
}
