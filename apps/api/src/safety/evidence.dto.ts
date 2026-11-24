import { Transform } from 'class-transformer';
import { IsOptional, IsString, IsUUID, Length } from 'class-validator';

const trim = ({value}: {value: unknown}) => typeof value === 'string' ? value.trim() : value;
export class EvidenceApprovalDto {
  @IsUUID() exporterId!: string;
  @Transform(trim) @IsString() @Length(1,240) purpose!: string;
  @Transform(trim) @IsString() @Length(1,160) recipient!: string;
  @Transform(trim) @IsOptional() @IsString() @Length(1,120) caseReference?: string;
}
export class EvidenceExportDto {
  @IsUUID() approvalId!: string;
}
