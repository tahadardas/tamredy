import { Injectable, BadRequestException, NotFoundException, ConflictException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

@Injectable()
export class PackagesService {
  constructor(private readonly db: DbService) {}

  /** Lists active packages */
  async listPackages() {
    const res = await this.db.query(`
      SELECT id, code, title_ar, title_en, description_ar, visit_count,
             price_amount, currency_code, validity_days
      FROM care_packages
      WHERE active = true
      ORDER BY visit_count ASC
    `);
    return res.rows;
  }

  /** Lists user's active/past package grants */
  async getUserPackages(userId: string) {
    const res = await this.db.query(`
      SELECT g.id, g.package_id, g.total_visits, g.remaining_visits,
             g.purchased_at, g.expires_at, g.status,
             p.code AS package_code, p.title_ar AS package_title, p.price_amount, p.currency_code
      FROM user_package_grants g
      JOIN care_packages p ON p.id = g.package_id
      WHERE g.user_id = $1
      ORDER BY g.purchased_at DESC
    `, [userId]);
    return res.rows;
  }

  /** Purchases/grants package to user */
  async purchasePackage(userId: string, packageId: string, paymentRef = 'CASH_CONFIRMED') {
    const pkg = (await this.db.query(`SELECT * FROM care_packages WHERE id = $1 AND active = true`, [packageId])).rows[0];
    if (!pkg) throw new NotFoundException({ code: 'PACKAGE_NOT_FOUND' });

    const expiresAt = new Date(Date.now() + pkg.validity_days * 24 * 3600 * 1000).toISOString();

    const res = await this.db.query(`
      INSERT INTO user_package_grants(user_id, package_id, total_visits, remaining_visits, expires_at, status, payment_reference)
      VALUES($1, $2, $3, $3, $4, 'ACTIVE', $5)
      RETURNING *
    `, [userId, pkg.id, pkg.visit_count, expiresAt, paymentRef]);

    return res.rows[0];
  }

  /** Redeems one visit from package for a care request without double redemption */
  async redeemPackageVisit(userId: string, grantId: string, requestId: string) {
    return this.db.transaction(async client => {
      // 1. Check grant ownership and validity
      const grant = (await client.query(`
        SELECT id, remaining_visits, expires_at, status
        FROM user_package_grants
        WHERE id = $1 AND user_id = $2
        FOR UPDATE
      `, [grantId, userId])).rows[0];

      if (!grant) throw new NotFoundException({ code: 'PACKAGE_GRANT_NOT_FOUND' });
      if (grant.status !== 'ACTIVE' || grant.remaining_visits <= 0) {
        throw new BadRequestException({ code: 'PACKAGE_EXHAUSTED' });
      }
      if (new Date(grant.expires_at) <= new Date()) {
        await client.query(`UPDATE user_package_grants SET status = 'EXPIRED' WHERE id = $1`, [grantId]);
        throw new BadRequestException({ code: 'PACKAGE_EXPIRED' });
      }

      // 2. Prevent request from redeeming twice
      const existing = await client.query(`SELECT id FROM package_redemptions WHERE request_id = $1`, [requestId]);
      if (existing.rowCount) throw new ConflictException({ code: 'REQUEST_ALREADY_REDEEMED_PACKAGE' });

      // 3. Decrement
      const newRemaining = grant.remaining_visits - 1;
      const nextStatus = newRemaining === 0 ? 'EXHAUSTED' : 'ACTIVE';

      await client.query(`
        UPDATE user_package_grants
        SET remaining_visits = $2, status = $3
        WHERE id = $1
      `, [grantId, newRemaining, nextStatus]);

      // 4. Record redemption
      await client.query(`
        INSERT INTO package_redemptions(grant_id, request_id)
        VALUES($1, $2)
      `, [grantId, requestId]);

      return {
        redeemed: true,
        remainingVisits: newRemaining,
        status: nextStatus,
      };
    });
  }
}
