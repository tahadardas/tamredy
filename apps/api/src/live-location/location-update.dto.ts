import {
  IsISO8601,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from 'class-validator';

export class LiveLocationUpdateDto {
  @IsLatitude() latitude!: number;
  @IsLongitude() longitude!: number;
  @IsNumber() @Min(0) @Max(1000) accuracyMeters!: number;
  @IsISO8601({ strict: true }) capturedAt!: string;
  @IsInt() @Min(1) @Max(2_147_483_647) sequenceNumber!: number;
  @IsUUID() sessionId!: string;
  @IsOptional() @IsNumber() @Min(0) @Max(150) speedMetersPerSecond?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(360) heading?: number;
  @IsIn(['GPS', 'NETWORK', 'PASSIVE', 'LAST_KNOWN']) locationSource!:
    | 'GPS'
    | 'NETWORK'
    | 'PASSIVE'
    | 'LAST_KNOWN';
  @IsOptional() @IsUUID() assignmentId?: string;
}

