import { Transform } from 'class-transformer';
import { IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from 'class-validator';

export class SafetyCaseActionDto {
  @IsUUID() clientActionId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}
