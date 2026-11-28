import { ConflictException } from '@nestjs/common';

/** The existing cash pricing engine and DTOs operate in whole SYP_NEW units. */
export const CASH_CURRENCY_CODE = 'SYP_NEW';

export function assertCashCurrency(currencyCode: string): void {
  if (currencyCode !== CASH_CURRENCY_CODE) {
    throw new ConflictException({ code: 'UNSUPPORTED_OPERATIONAL_CURRENCY' });
  }
}
