import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, MaxLength, Min, MinLength } from 'class-validator';
import { financialCurrency, financialModels, type FinancialModel } from './nurse-financial-account.service.js';

class FinancialPolicyDto {
  @IsIn(financialModels) financialModel!: FinancialModel;
  @Matches(/^\d{1,16}(?:\.\d{1,2})?$/) creditLimit!: string;
}
export class InitializeNurseFinancialAccountDto extends FinancialPolicyDto {
  @Matches(financialCurrency) currencyCode!: string;
}
export class UpdateNurseFinancialAccountDto extends FinancialPolicyDto {
  @IsInt() @Min(1) expectedVersion!: number;
  @IsBoolean() administrativelyRestricted!: boolean;
  @IsOptional() @IsString() @MaxLength(200) restrictionReason?: string;
}
export class ReconcileLegacyNurseAccountDto {
  @Matches(financialCurrency) currencyCode!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsString() @MinLength(4) @MaxLength(200) evidenceReference!: string;
  @IsOptional() @IsUUID() proofTransactionId?: string;
}
