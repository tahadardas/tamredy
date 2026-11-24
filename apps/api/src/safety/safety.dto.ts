import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsInt, IsISO8601, IsNumber, IsUUID, Matches, Max, Min, ValidateIf, ValidateNested } from 'class-validator';

export class StartSafetySessionDto {
  @IsUUID() assignmentId!: string;
}

export class SafetyPointDto {
  @IsInt() @Min(0) @Max(2147483647) sequence!: number;
  @IsNumber() @Min(-90) @Max(90) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
  @IsNumber() @Min(0) @Max(10000) accuracy!: number;
  @IsISO8601({ strict: true }) @Matches(/(?:Z|[+-]\d{2}:\d{2})$/i) capturedAt!: string;
}

export class SafetyLocationBatchDto {
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(100)
  @ValidateNested({ each: true }) @Type(() => SafetyPointDto)
  points!: SafetyPointDto[];
}

export class ReportSosDto {
  @IsUUID() clientEventId!: string;
  @ValidateIf((_, value) => value !== undefined) @IsUUID() sessionId?: string;
  @IsBoolean() silent!: boolean;
  @ValidateIf((_, value) => value !== undefined) @IsUUID() expectedReporterId?: string;
  @ValidateIf((_, value) => value !== undefined)
  @IsISO8601({ strict: true }) @Matches(/(?:Z|[+-]\d{2}:\d{2})$/i) triggeredAt?: string;
}

export const checkinResponses = ['OK','MORE_TIME','HELP','SAFE_EXIT'] as const;

export class SafetyCheckinResponseDto {
  @IsUUID() checkinId!: string;
  @IsUUID() clientResponseId!: string;
  @IsIn(checkinResponses) response!: (typeof checkinResponses)[number];
}
