import { Injectable, BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

export interface CreateCarePlanDto {
  beneficiaryId: string;
  primaryServiceId: string;
  frequencyType: 'DAILY' | 'EVERY_OTHER_DAY' | 'THREE_TIMES_A_WEEK' | 'SPECIFIC_DAYS';
  frequencyMeta?: { weekdays?: number[] }; // 1=Mon .. 7=Sun
  preferredTimeOfDay: string; // 'HH:MM:SS' or 'HH:MM'
  totalVisitsPlanned?: number;
  startDate: string; // 'YYYY-MM-DD'
  endDate?: string;
  notes?: string;
  addressText: string;
  latitude: number;
  longitude: number;
  locationSource?: string;
}

@Injectable()
export class CarePlansService {
  constructor(private readonly db: DbService) {}

  /** Calculates occurrence dates within the generation horizon */
  calculateOccurrenceDates(
    startDateStr: string,
    preferredTime: string,
    frequencyType: string,
    meta?: { weekdays?: number[] },
    maxOccurrences = 14,
    endDateStr?: string,
  ): Date[] {
    const dates: Date[] = [];
    const [hours = 10, minutes = 0] = preferredTime.split(':').map(Number);
    const cursor = new Date(startDateStr);
    cursor.setHours(hours, minutes, 0, 0);

    const maxHorizonDate = new Date();
    maxHorizonDate.setDate(maxHorizonDate.getDate() + 30); // 30-day horizon

    const endDate = endDateStr ? new Date(endDateStr) : maxHorizonDate;
    endDate.setHours(23, 59, 59, 999);

    let count = 0;
    while (cursor <= endDate && cursor <= maxHorizonDate && count < maxOccurrences) {
      let isMatch = false;
      const dayOfWeek = cursor.getDay() === 0 ? 7 : cursor.getDay(); // 1=Mon .. 7=Sun

      if (frequencyType === 'DAILY') {
        isMatch = true;
      } else if (frequencyType === 'EVERY_OTHER_DAY') {
        isMatch = count === 0 || (cursor.getTime() - dates[dates.length - 1]!.getTime()) >= 48 * 3600 * 1000 - 3600 * 1000;
      } else if (frequencyType === 'THREE_TIMES_A_WEEK') {
        // Default: Mon (1), Wed (3), Sat (6)
        const allowed = meta?.weekdays ?? [1, 3, 6];
        isMatch = allowed.includes(dayOfWeek);
      } else if (frequencyType === 'SPECIFIC_DAYS') {
        const allowed = meta?.weekdays ?? [1, 3, 5];
        isMatch = allowed.includes(dayOfWeek);
      }

      if (isMatch) {
        dates.push(new Date(cursor));
        count++;
      }

      cursor.setDate(cursor.getDate() + 1);
    }

    return dates;
  }

  /** Creates a new recurring care plan */
  async createCarePlan(patientUserId: string, dto: CreateCarePlanDto) {
    // Verify beneficiary belongs to patient
    const ben = await this.db.query(
      `SELECT id FROM beneficiaries WHERE id = $1 AND owner_user_id = $2 AND consent_status = 'GRANTED'`,
      [dto.beneficiaryId, patientUserId],
    );
    if (!ben.rowCount) throw new ForbiddenException({ code: 'BENEFICIARY_ACCESS_DENIED' });

    // Verify service
    const srv = await this.db.query(
      `SELECT id, title_ar, recurring_visits_allowed FROM services WHERE id = $1 AND active = true AND dispatch_approved = true`,
      [dto.primaryServiceId],
    );
    if (!srv.rowCount) throw new BadRequestException({ code: 'SERVICE_NOT_FOUND' });
    if (!srv.rows[0].recurring_visits_allowed) {
      throw new BadRequestException({ code: 'SERVICE_RECURRING_NOT_ALLOWED' });
    }

    const preferredTime = dto.preferredTimeOfDay.length === 5 ? `${dto.preferredTimeOfDay}:00` : dto.preferredTimeOfDay;
    const initialDates = this.calculateOccurrenceDates(
      dto.startDate,
      preferredTime,
      dto.frequencyType,
      dto.frequencyMeta,
      dto.totalVisitsPlanned ?? 14,
      dto.endDate,
    );

    if (initialDates.length === 0) {
      throw new BadRequestException({ code: 'NO_VALID_DATES_IN_RANGE' });
    }

    return this.db.transaction(async client => {
      const owner = await client.query("SELECT id FROM users WHERE id=$1 AND status='ACTIVE' FOR SHARE", [patientUserId]);
      if (!owner.rowCount) throw new ForbiddenException({ code: 'ACCOUNT_INACTIVE' });
      const planRes = await client.query(
        `INSERT INTO care_plans(
           patient_user_id, beneficiary_id, primary_service_id, frequency_type,
           frequency_meta, preferred_time_of_day, total_visits_planned,
           start_date, end_date, notes, address_text, location, location_source, status
         )
         VALUES(
           $1, $2, $3, $4, coalesce($5, '{}')::jsonb, $6, $7,
           $8, $9, $10, $11, ST_SetSRID(ST_MakePoint($12, $13), 4326)::geography, $14, 'ACTIVE'
         )
         RETURNING *`,
        [
          patientUserId,
          dto.beneficiaryId,
          dto.primaryServiceId,
          dto.frequencyType,
          dto.frequencyMeta ? JSON.stringify(dto.frequencyMeta) : null,
          preferredTime,
          dto.totalVisitsPlanned ?? initialDates.length,
          dto.startDate,
          dto.endDate ?? null,
          dto.notes ?? null,
          dto.addressText,
          dto.longitude,
          dto.latitude,
          dto.locationSource ?? 'GPS_CONFIRMED',
        ],
      );

      const plan = planRes.rows[0];

      // Pre-create occurrences
      let occNum = 1;
      for (const d of initialDates) {
        await client.query(
          `INSERT INTO care_plan_occurrences(care_plan_id, occurrence_number, scheduled_for, status)
           VALUES($1, $2, $3, 'PENDING')`,
          [plan.id, occNum++, d.toISOString()],
        );
      }

      return {
        ...plan,
        occurrencesCount: initialDates.length,
        nextScheduledFor: initialDates[0]?.toISOString(),
      };
    });
  }

  /** Lists care plans for a patient or all care plans for admin */
  async listCarePlans(patientUserId: string, role?: string) {
    if (role === 'ADMIN') {
      const res = await this.db.query(`
        SELECT cp.*, s.title_ar AS service_title, s.code AS service_code,
               b.display_name AS beneficiary_name,
               u.display_name AS patient_name, u.phone_e164 AS patient_phone,
               (SELECT count(*)::int FROM care_plan_occurrences o WHERE o.care_plan_id = cp.id AND o.status = 'COMPLETED') AS completed_occurrences,
               (SELECT count(*)::int FROM care_plan_occurrences o WHERE o.care_plan_id = cp.id) AS total_occurrences,
               (SELECT scheduled_for FROM care_plan_occurrences o WHERE o.care_plan_id = cp.id AND o.status = 'PENDING' ORDER BY scheduled_for ASC LIMIT 1) AS next_visit_at
        FROM care_plans cp
        JOIN services s ON s.id = cp.primary_service_id
        JOIN beneficiaries b ON b.id = cp.beneficiary_id
        JOIN users u ON u.id = cp.patient_user_id
        ORDER BY cp.created_at DESC
      `);
      return { plans: res.rows };
    }

    const res = await this.db.query(`
      SELECT cp.*, s.title_ar AS service_title, s.code AS service_code,
             b.display_name AS beneficiary_name,
             (SELECT count(*)::int FROM care_plan_occurrences o WHERE o.care_plan_id = cp.id AND o.status = 'COMPLETED') AS completed_occurrences,
             (SELECT count(*)::int FROM care_plan_occurrences o WHERE o.care_plan_id = cp.id) AS total_occurrences,
             (SELECT scheduled_for FROM care_plan_occurrences o WHERE o.care_plan_id = cp.id AND o.status = 'PENDING' ORDER BY scheduled_for ASC LIMIT 1) AS next_visit_at
      FROM care_plans cp
      JOIN services s ON s.id = cp.primary_service_id
      JOIN beneficiaries b ON b.id = cp.beneficiary_id
      WHERE cp.patient_user_id = $1
      ORDER BY cp.created_at DESC
    `, [patientUserId]);

    return { plans: res.rows };
  }

  /** Gets detailed care plan with occurrences */
  async getCarePlan(patientUserId: string, planId: string, role?: string) {
    const isSpecialAdmin = role === 'ADMIN';
    const whereClause = isSpecialAdmin ? 'cp.id = $1' : 'cp.id = $1 AND cp.patient_user_id = $2';
    const params = isSpecialAdmin ? [planId] : [planId, patientUserId];
    const planRes = await this.db.query(`
      SELECT cp.*, s.title_ar AS service_title, s.code AS service_code, s.price_amount,
             b.display_name AS beneficiary_name,
             u.display_name AS patient_name, u.phone_e164 AS patient_phone
      FROM care_plans cp
      JOIN services s ON s.id = cp.primary_service_id
      JOIN beneficiaries b ON b.id = cp.beneficiary_id
      JOIN users u ON u.id = cp.patient_user_id
      WHERE ${whereClause}
    `, params);

    if (!planRes.rowCount) throw new NotFoundException({ code: 'CARE_PLAN_NOT_FOUND' });

    const occurrences = await this.db.query(`
      SELECT o.id, o.occurrence_number, o.scheduled_for, o.status, o.request_id,
             cr.status AS request_status
      FROM care_plan_occurrences o
      LEFT JOIN care_requests cr ON cr.id = o.request_id
      WHERE o.care_plan_id = $1
      ORDER BY o.occurrence_number ASC
    `, [planId]);

    return {
      ...planRes.rows[0],
      occurrences: occurrences.rows,
    };
  }

  /** Pauses care plan */
  async pauseCarePlan(patientUserId: string, planId: string) {
    const res = await this.db.query(
      `UPDATE care_plans SET status = 'PAUSED', updated_at = now()
       WHERE id = $1 AND patient_user_id = $2 AND status = 'ACTIVE'
       RETURNING id`,
      [planId, patientUserId],
    );
    if (!res.rowCount) throw new NotFoundException({ code: 'ACTIVE_PLAN_NOT_FOUND' });
    return { ok: true, status: 'PAUSED' };
  }

  /** Resumes care plan */
  async resumeCarePlan(patientUserId: string, planId: string) {
    const res = await this.db.query(
      `UPDATE care_plans SET status = 'ACTIVE', updated_at = now()
       WHERE id = $1 AND patient_user_id = $2 AND status = 'PAUSED'
       RETURNING id`,
      [planId, patientUserId],
    );
    if (!res.rowCount) throw new NotFoundException({ code: 'PAUSED_PLAN_NOT_FOUND' });
    return { ok: true, status: 'ACTIVE' };
  }

  /** Cancels care plan and ungenerated future occurrences */
  async cancelCarePlan(patientUserId: string, planId: string) {
    return this.db.transaction(async client => {
      const res = await client.query(
        `UPDATE care_plans SET status = 'CANCELLED', updated_at = now()
         WHERE id = $1 AND patient_user_id = $2 AND status IN ('ACTIVE', 'PAUSED')
         RETURNING id`,
        [planId, patientUserId],
      );
      if (!res.rowCount) throw new NotFoundException({ code: 'CARE_PLAN_NOT_FOUND' });

      // Cancel ungenerated occurrences
      await client.query(
        `UPDATE care_plan_occurrences SET status = 'CANCELLED'
         WHERE care_plan_id = $1 AND status = 'PENDING' AND request_id IS NULL`,
        [planId],
      );

      return { ok: true, status: 'CANCELLED' };
    });
  }
}
