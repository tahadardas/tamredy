import { Injectable, BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

export interface CalendarBlockInput {
  startTime: string;
  endTime: string;
  reason?: string;
}

@Injectable()
export class NurseCalendarService {
  constructor(private readonly db: DbService) {}

  private async getNurseId(userId: string): Promise<string> {
    const res = await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [userId]);
    if (!res.rowCount) throw new NotFoundException({ code: 'NURSE_RECORD_NOT_FOUND' });
    return res.rows[0].id;
  }

  /** Gets complete nurse schedule: confirmed visits + unavailable blocks */
  async getSchedule(nurseUserId: string, fromIso: string, toIso: string) {
    const nurseId = await this.getNurseId(nurseUserId);

    // 1. Confirmed visits in range
    const visits = await this.db.query(`
      SELECT cr.id AS request_id, cr.status, cr.price_amount, cr.currency_code,
             cr.address_text, s.title_ar AS service_title, s.code AS service_code,
             coalesce((cr.pricing->>'expectedMinutes')::int, 30) AS expected_minutes,
             sv.appointment_at, ra.accepted_at,
             b.display_name AS beneficiary_name
      FROM request_assignments ra
      JOIN care_requests cr ON cr.id = ra.request_id
      JOIN services s ON s.id = cr.service_id
      JOIN beneficiaries b ON b.id = cr.beneficiary_id
      LEFT JOIN scheduled_visits sv ON sv.request_id = cr.id
      WHERE ra.nurse_id = $1
        AND ra.status IN ('RESERVED','ACTIVE')
        AND cr.status IN ('SCHEDULED', 'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED')
        AND coalesce(sv.appointment_at, ra.accepted_at) >= $2::timestamptz
        AND coalesce(sv.appointment_at, ra.accepted_at) <= $3::timestamptz
      ORDER BY coalesce(sv.appointment_at, ra.accepted_at) ASC
    `, [nurseId, fromIso, toIso]);

    // 2. Off-duty blocks
    const blocks = await this.db.query(`
      SELECT id, start_time, end_time, reason, created_at
      FROM nurse_calendar_blocks
      WHERE nurse_id = $1
        AND end_time >= $2::timestamptz
        AND start_time <= $3::timestamptz
      ORDER BY start_time ASC
    `, [nurseId, fromIso, toIso]);

    return {
      visits: visits.rows,
      blocks: blocks.rows,
      timeZone: 'Asia/Damascus',
    };
  }

  /** Adds off-duty or unavailable time block */
  async addBlock(nurseUserId: string, input: CalendarBlockInput) {
    const nurseId = await this.getNurseId(nurseUserId);
    const start = new Date(input.startTime);
    const end = new Date(input.endTime);

    if (isNaN(start.getTime()) || isNaN(end.getTime()) || end <= start) {
      throw new BadRequestException({ code: 'INVALID_TIME_RANGE' });
    }

    return this.db.transaction(async client => {
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [nurseId]);
      // Check if nurse already has a confirmed visit during this block
      const conflict = await client.query(`
        SELECT nurse_has_schedule_conflict($1,$2::timestamptz,$3::timestamptz,NULL) AS conflict
      `, [nurseId, start.toISOString(), end.toISOString()]);

      if (conflict.rows[0]?.conflict) {
        throw new ConflictException({ code: 'CONFIRMED_VISIT_CONFLICTS_WITH_BLOCK' });
      }

      const res = await client.query(
        `INSERT INTO nurse_calendar_blocks(nurse_id, start_time, end_time, reason)
         VALUES($1, $2, $3, coalesce($4, 'OFF_DUTY'))
         RETURNING *`,
        [nurseId, start.toISOString(), end.toISOString(), input.reason ?? 'OFF_DUTY'],
      );

      return res.rows[0];
    });
  }

  /** Removes an off-duty block */
  async removeBlock(nurseUserId: string, blockId: string) {
    const nurseId = await this.getNurseId(nurseUserId);
    const res = await this.db.query(
      `DELETE FROM nurse_calendar_blocks WHERE id = $1 AND nurse_id = $2 RETURNING id`,
      [blockId, nurseId],
    );
    if (!res.rowCount) throw new NotFoundException({ code: 'BLOCK_NOT_FOUND' });
    return { ok: true };
  }

  /** Checks whether assigning a visit creates a schedule conflict for the nurse */
  async checkConflict(
    client: { query: (s: string, p?: unknown[]) => Promise<any> },
    nurseId: string,
    appointmentTime: Date,
    expectedMinutes: number,
    excludeRequestId?: string,
  ): Promise<boolean> {
    const startWindow = new Date(appointmentTime.getTime() - 30 * 60 * 1000); // 30m buffer before
    const endWindow = new Date(appointmentTime.getTime() + (expectedMinutes + 30) * 60 * 1000); // 30m buffer after

    const res = await client.query(`
      SELECT nurse_has_schedule_conflict($1, $2, $3, $4) AS conflict
    `, [nurseId, startWindow.toISOString(), endWindow.toISOString(), excludeRequestId ?? null]);

    return Boolean(res.rows[0]?.conflict);
  }
}
