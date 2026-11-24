import { Injectable, BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

export interface CreateBlockDto {
  targetUserId: string;
  reasonCode?: string;
  privateNote?: string;
}

export interface CreateReportDto {
  reportedUserId?: string;
  requestId?: string;
  reportType: 'TECHNICAL_SUPPORT' | 'FINANCIAL_DISPUTE' | 'CLINICAL_COMPLAINT' | 'SAFETY_INCIDENT' | 'COMMITMENT_APPEAL';
  severity?: 'LOW' | 'STANDARD' | 'URGENT' | 'CRITICAL_SAFETY';
  title: string;
  description: string;
}

@Injectable()
export class TrustService {
  constructor(private readonly db: DbService) {}

  /** Blocks another user from future interactions */
  async blockUser(blockerUserId: string, dto: CreateBlockDto) {
    if (blockerUserId === dto.targetUserId) {
      throw new BadRequestException({ code: 'CANNOT_BLOCK_SELF' });
    }

    return this.db.transaction(async client => {
      // Check existing active block
      const existing = await client.query(
        `SELECT id FROM user_blocks WHERE blocker_user_id = $1 AND blocked_user_id = $2 AND revoked_at IS NULL`,
        [blockerUserId, dto.targetUserId],
      );
      if (existing.rowCount) {
        throw new ConflictException({ code: 'ALREADY_BLOCKED' });
      }

      const res = await client.query(
        `INSERT INTO user_blocks(blocker_user_id, blocked_user_id, reason_code, private_note)
         VALUES($1, $2, coalesce($3, 'GENERAL_PREFERENCE'), $4)
         RETURNING id, blocker_user_id, blocked_user_id, reason_code, created_at`,
        [blockerUserId, dto.targetUserId, dto.reasonCode, dto.privateNote ?? null],
      );

      return res.rows[0];
    });
  }

  /** Unblocks a previously blocked user */
  async unblockUser(blockerUserId: string, targetUserId: string) {
    const res = await this.db.query(
      `UPDATE user_blocks SET revoked_at = now()
       WHERE blocker_user_id = $1 AND blocked_user_id = $2 AND revoked_at IS NULL
       RETURNING id`,
      [blockerUserId, targetUserId],
    );
    if (!res.rowCount) {
      throw new NotFoundException({ code: 'BLOCK_NOT_FOUND' });
    }
    return { ok: true };
  }

  /** Lists blocked users for the authenticated user */
  async listBlockedUsers(userId: string) {
    const res = await this.db.query(
      `SELECT ub.id, ub.blocked_user_id, ub.reason_code, ub.created_at, u.role
       FROM user_blocks ub
       JOIN users u ON u.id = ub.blocked_user_id
       WHERE ub.blocker_user_id = $1 AND ub.revoked_at IS NULL
       ORDER BY ub.created_at DESC`,
      [userId],
    );
    return res.rows;
  }

  /** Checks if there is an active mutual block between two users */
  async isMutuallyBlocked(userA: string, userB: string): Promise<boolean> {
    const res = await this.db.query(
      `SELECT 1 FROM user_blocks
       WHERE ((blocker_user_id = $1 AND blocked_user_id = $2)
          OR (blocker_user_id = $2 AND blocked_user_id = $1))
         AND revoked_at IS NULL
       LIMIT 1`,
      [userA, userB],
    );
    return (res.rowCount ?? 0) > 0;
  }

  /** Submits an auditable complaint or support report */
  async createReport(reporterUserId: string, dto: CreateReportDto) {
    return this.db.transaction(async client => {
      const isSafetyIncident = dto.reportType === 'SAFETY_INCIDENT' || dto.severity === 'CRITICAL_SAFETY';
      const initialStatus = isSafetyIncident ? 'ESCALATED_TO_GUARDIAN' : 'OPEN';

      const res = await client.query(
        `INSERT INTO user_reports(
           reporter_user_id, reported_user_id, request_id,
           report_type, severity, title, description, status
         )
         VALUES($1, $2, $3, $4, coalesce($5, 'STANDARD'), $6, $7, $8)
         RETURNING *`,
        [
          reporterUserId,
          dto.reportedUserId ?? null,
          dto.requestId ?? null,
          dto.reportType,
          dto.severity ?? 'STANDARD',
          dto.title,
          dto.description,
          initialStatus,
        ],
      );

      const report = res.rows[0];

      // If escalated to Guardian, record an audit event
      if (isSafetyIncident) {
        await client.query(
          `INSERT INTO outbox_events(event_type, aggregate_id, payload)
           VALUES('safety.incident.escalated', $1, $2::jsonb)`,
          [
            report.id,
            JSON.stringify({
              reportId: report.id,
              reporterUserId,
              reportedUserId: dto.reportedUserId,
              requestId: dto.requestId,
              severity: report.severity,
            }),
          ],
        );
      }

      return report;
    });
  }

  /** Admin / Supervisor report listing */
  async listReports(filter?: { status?: string; type?: string }) {
    let query = `
      SELECT r.*, u.phone_e164 AS reporter_phone, u.role AS reporter_role
      FROM user_reports r
      JOIN users u ON u.id = r.reporter_user_id
      WHERE 1=1
    `;
    const params: unknown[] = [];
    if (filter?.status) {
      params.push(filter.status);
      query += ` AND r.status = $${params.length}`;
    }
    if (filter?.type) {
      params.push(filter.type);
      query += ` AND r.report_type = $${params.length}`;
    }
    query += ` ORDER BY r.created_at DESC LIMIT 100`;

    const res = await this.db.query(query, params);
    return res.rows;
  }

  /** Admin resolution / triage update */
  async triageReport(reportId: string, adminUserId: string, status: string, resolutionNote?: string) {
    const res = await this.db.query(
      `UPDATE user_reports
       SET status = $1,
           resolution_note = $2,
           resolved_by_user_id = $3,
           resolved_at = CASE WHEN $1 IN ('RESOLVED', 'REJECTED') THEN now() ELSE resolved_at END,
           updated_at = now()
       WHERE id = $4
       RETURNING *`,
      [status, resolutionNote ?? null, adminUserId, reportId],
    );
    return res.rows[0];
  }
}
