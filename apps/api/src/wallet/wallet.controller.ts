import { Controller, Get, Post, UseGuards, Request, NotImplementedException } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';

@Controller('v1/wallet')
@UseGuards(AuthGuard)
export class WalletController {
  constructor(private readonly db: DbService) {}

  @Get('status')
  status(@Request() req: AuthRequest) {
    requireRole(req.user!, 'PATIENT');
    return {
      mode: 'DISABLED',
      providerConnected: false,
      reason: 'LICENSED_PAYMENT_PROVIDER_REQUIRED',
    };
  }

  @Get('patient-summary')
  async patientSummary(@Request() req: AuthRequest) {
    requireRole(req.user!, 'PATIENT');
    const userId = req.user!.id;

    // Load wallet compartments
    const walletRes = await this.db.query(
      `SELECT promotional_credit, refund_credit, cash_balance FROM patient_wallets WHERE patient_user_id = $1`,
      [userId],
    );
    const wallet = walletRes.rows[0] ?? {
      promotional_credit: 0,
      refund_credit: 0,
      cash_balance: 0,
    };

    // Load active packages
    const pkgs = await this.db.query(`
      SELECT g.id, g.remaining_visits, g.total_visits, g.expires_at,
             p.title_ar AS package_title, p.code AS package_code
      FROM user_package_grants g
      JOIN care_packages p ON p.id = g.package_id
      WHERE g.user_id = $1 AND g.status = 'ACTIVE' AND g.remaining_visits > 0 AND g.expires_at > now()
    `, [userId]);

    // Load claimed promo codes
    const promos = await this.db.query(`
      SELECT pc.code, pc.description, pc.type, pc.value, pc.max_discount, pc.valid_to
      FROM promo_claims c
      JOIN promo_codes pc ON pc.id = c.promo_id
      WHERE c.user_id = $1 AND pc.active = true AND (pc.valid_to IS NULL OR pc.valid_to > now())
    `, [userId]);

    return {
      currencyCode: 'SYP_NEW',
      activePaymentMethod: 'CASH_ON_DELIVERY',
      compartments: {
        promotionalCredit: Number(wallet.promotional_credit),
        refundCredit: Number(wallet.refund_credit),
        cashBalance: Number(wallet.cash_balance),
      },
      packages: pkgs.rows,
      activePromos: promos.rows,
      isRealTopupEnabled: false,
    };
  }

  @Post('topups')
  topup(@Request() req: AuthRequest) {
    requireRole(req.user!, 'PATIENT');
    throw new NotImplementedException({
      code: 'WALLET_NOT_ENABLED',
      message: 'Connect a legally licensed provider before accepting money',
    });
  }
}
