import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsString, Length, Matches, Max, Min } from 'class-validator';

const trim = ({ value }: { value: unknown }) => typeof value === 'string' ? value.trim() : value;

export class TrustedContactDto {
  @Transform(trim) @IsString() @Length(1,80) name!: string;
  @Matches(/^\+[1-9]\d{7,14}$/) phone!: string;
  @Transform(trim) @IsString() @Length(1,60) relationship!: string;
  @IsInt() @Min(1) @Max(3) priority!: number;
  @IsIn(['CALL','SMS']) communication!: 'CALL' | 'SMS';
  @IsBoolean() requestLocation!: boolean;
}

export class ContactConsentDto {
  @IsIn(['ACCEPTED','DECLINED','REVOKED']) decision!: 'ACCEPTED' | 'DECLINED' | 'REVOKED';
  @IsBoolean() allowsLocation!: boolean;
  @Transform(trim) @IsString() @Length(1,100) verificationReference!: string;
  @Matches(/^\+[1-9]\d{7,14}$/) verifiedPhone!: string;
}
