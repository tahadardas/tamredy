import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';

const trim = ({ value }: { value: unknown }) => typeof value === 'string' ? value.trim() : value;

export class DirectoryEntryDto {
  @Transform(trim) @IsString() @Length(1,100) name!: string;
  @IsIn(['POLICE','AMBULANCE','CIVIL_DEFENCE','SAFETY_TEAM','APPROVED_SUPPORT']) category!: string;
  @Transform(trim) @IsOptional() @IsString() @Length(1,80) governorate?: string;
  @Transform(trim) @IsOptional() @IsString() @Length(1,80) area?: string;
  @Matches(/^[+]?[0-9]{2,15}$/) dialNumber!: string;
  @Transform(trim) @IsOptional() @IsString() @MaxLength(120) hours?: string;
  @Transform(trim) @IsString() @Length(1,500) officialSource!: string;
  @IsBoolean() publishVerified!: boolean;
}
