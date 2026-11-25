import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';

export class ClinicalDecisionDto {
  @IsIn(['APPROVE','REJECT']) decision!: 'APPROVE'|'REJECT';
  @IsString() @MinLength(3) @MaxLength(2000) note!: string;
}

export class ClinicalEvidenceDto {
  @IsIn(['PRESCRIPTION','CLINICAL_REPORT','REFERRAL','OTHER'])
  evidenceType!: 'PRESCRIPTION'|'CLINICAL_REPORT'|'REFERRAL'|'OTHER';
}
