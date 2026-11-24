import { IsIn, IsISO8601, IsOptional, IsUUID, Matches } from 'class-validator';

export class SafetyShiftDto {
  @IsOptional() @IsUUID() governorateId?: string;
  @IsIn(['DAY','NIGHT']) shiftKind!: 'DAY' | 'NIGHT';
  @IsUUID() primaryUserId!: string;
  @IsUUID() backupUserId!: string;
  @IsISO8601({ strict: true }) @Matches(/(?:Z|[+-]\d{2}:\d{2})$/i) startsAt!: string;
  @IsISO8601({ strict: true }) @Matches(/(?:Z|[+-]\d{2}:\d{2})$/i) endsAt!: string;
}
