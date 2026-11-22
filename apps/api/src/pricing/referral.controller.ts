import { Body, Controller, Get, Post, Request, UseGuards } from '@nestjs/common';
import { IsString, MaxLength, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { PromoService } from './promo.service.js';
import { ReferralService } from './referral.service.js';

class ReferralClaimDto { @IsString() @MinLength(4) @MaxLength(20) code!: string; }

@Controller('v1/referral') @UseGuards(AuthGuard)
export class ReferralController {
  constructor(private readonly db: DbService, private readonly referrals: ReferralService, private readonly promos: PromoService) {}

  /** My personal code, how many friends joined/paid, and what each side gets. */
  @Get('mine') mine(@Request() r: AuthRequest) { requireRole(r.user!, 'PATIENT'); return this.referrals.summary(this.db, r.user!.id); }

  /** A new patient enters a friend's code (before their first order). Wrong guesses count toward the promo rate limit. */
  @Post('claim') async claim(@Request() r: AuthRequest, @Body() dto: ReferralClaimDto) {
    requireRole(r.user!, 'PATIENT');
    await this.promos.guard(r.user!.id);
    return this.db.transaction(async c => {
      try { return await this.referrals.claim(c, r.user!.id, dto.code); }
      catch (e) { await this.promos.log(r.user!.id, false); throw e; }
    });
  }
}
