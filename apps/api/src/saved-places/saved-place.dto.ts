import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, Length, Max, MaxLength, Min } from 'class-validator';

export const placeTypes = ['HOME', 'WORK', 'PARENTS', 'CUSTOM'] as const;

export class SavedPlaceDto {
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsString() @Length(1, 80) label!: string;
  @IsIn(placeTypes) placeType!: (typeof placeTypes)[number];
  @IsNumber() @Min(-90) @Max(90) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
  @IsNumber() @Min(0) @Max(100000) accuracy!: number;
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsString() @Length(1, 300) formattedAddress!: string;
  @IsOptional() @IsString() @MaxLength(40) floor?: string;
  @IsOptional() @IsString() @MaxLength(80) building?: string;
  @IsOptional() @IsString() @MaxLength(150) landmark?: string;
  @IsOptional() @IsString() @MaxLength(300) notes?: string;
  @IsBoolean() isDefault!: boolean;
}
