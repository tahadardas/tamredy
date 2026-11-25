import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { ExtendOpenRequestDto, SwitchBookingModeDto } from './marketplace.dto.js';
import { saveSchedule, validateAppointment, verifyScheduledSafety } from '../scheduling/scheduling.js';

@Injectable()
export class BookingModeService {
  constructor(private readonly db: DbService) {}

  /**
   * Switches booking mode for an unassigned request (e.g. Instant -> Open Marketplace or Instant -> Scheduled).
   * Atomically cancels previous search channel, updates mode, logs transition audit, and activates new channel.
   */
  async switchBookingMode(patientUserId: string, requestId: string, dto: SwitchBookingModeDto) {
    return this.db.transaction(async client => {
      // 1. Lock request
      const reqRes = await client.query(
        `SELECT id, requester_user_id, status, booking_mode, version, booking_mode_version,
                price_amount, currency_code, commission_bps, location
         FROM care_requests
         WHERE id = $1
         FOR UPDATE`,
        [requestId],
      );
      if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
      const request = reqRes.rows[0];

      if (request.requester_user_id !== patientUserId) {
        throw new ForbiddenException({ code: 'FORBIDDEN_NOT_REQUEST_OWNER' });
      }

      // Prohibit mode conversion on assigned or active visits
      if (['ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED', 'ESCALATED'].includes(request.status)) {
        throw new ConflictException({
          code: 'CANNOT_CONVERT_ASSIGNED_REQUEST',
          message: 'لا يمكن تحويل نوع الحجز لطلب مسند بالفعل',
        });
      }

      const fromMode = request.booking_mode;
      const toMode = dto.bookingMode;
      const fromStatus = request.status;
      let toStatus = fromStatus;

      // 2. Transition to OPEN MARKETPLACE
      if (toMode === 'OPEN') {
        toStatus = 'OPEN_FOR_PROPOSALS';
        const now = new Date();
        const durationMins = dto.openDurationMinutes ?? 120;
        const openExpiresAt = new Date(now.getTime() + durationMins * 60000);
        const latestArrivalAt = dto.latestAcceptableArrivalAt
          ? new Date(dto.latestAcceptableArrivalAt)
          : new Date(openExpiresAt.getTime() + 60 * 60000);

        // Close pending instant offers and cancel dispatch jobs
        await client.query(
          `UPDATE request_offers SET status = 'EXPIRED' WHERE request_id = $1 AND status = 'OPEN'`,
          [requestId],
        );
        await client.query(`DELETE FROM dispatch_jobs WHERE request_id = $1`, [requestId]);

        // Update care request to OPEN
        await client.query(
          `UPDATE care_requests
           SET booking_mode = 'OPEN',
               status = 'OPEN_FOR_PROPOSALS',
               marketplace_status = 'OPEN_FOR_PROPOSALS',
               published_at = now(),
               open_expires_at = $2,
               latest_acceptable_arrival_at = $3,
               booking_mode_version = booking_mode_version + 1,
               version = version + 1,
               last_mode_change_at = now(),
               updated_at = now()
           WHERE id = $1`,
          [requestId, openExpiresAt.toISOString(), latestArrivalAt.toISOString()],
        );

        // Audit log transition
        await client.query(
          `INSERT INTO request_booking_transitions(
             request_id, from_mode, to_mode, from_status, to_status,
             triggered_by_user_id, transition_reason, transition_metadata
           )
           VALUES($1, $2, $3, $4, $5, $6, 'PATIENT_REQUESTED_OPEN_MARKETPLACE', $7::jsonb)`,
          [
            requestId,
            fromMode,
            toMode,
            fromStatus,
            toStatus,
            patientUserId,
            JSON.stringify({ openDurationMinutes: durationMins, openExpiresAt, latestArrivalAt }),
          ],
        );

        // Emit outbox events
        await client.query(
          `INSERT INTO outbox_events(event_type, aggregate_id, payload)
           VALUES('marketplace.request.published', $1, $2::jsonb)`,
          [requestId, JSON.stringify({ requestId, recipientUserId: patientUserId, openExpiresAt })],
        );

        return {
          requestId,
          bookingMode: 'OPEN',
          status: 'OPEN_FOR_PROPOSALS',
          openExpiresAt,
          latestAcceptableArrivalAt: latestArrivalAt,
        };
      }

      // 3. Transition to SCHEDULED
      if (toMode === 'SCHEDULED') {
        toStatus = 'SCHEDULED';
        const appointment = validateAppointment(dto.scheduledAt);
        if (!appointment) {
          throw new BadRequestException({ code: 'VALID_SCHEDULED_TIME_REQUIRED' });
        }

        // Verify safety window
        const services = (await client.query(
          `SELECT service_id FROM care_request_items WHERE request_id = $1`,
          [requestId],
        )).rows;
        for (const s of services) {
          await verifyScheduledSafety(client, s.service_id, appointment);
        }

        // Close pending instant offers and cancel dispatch jobs
        await client.query(
          `UPDATE request_offers SET status = 'EXPIRED' WHERE request_id = $1 AND status = 'OPEN'`,
          [requestId],
        );
        await client.query(`DELETE FROM dispatch_jobs WHERE request_id = $1`, [requestId]);

        await client.query(
          `UPDATE care_requests
           SET booking_mode = 'SCHEDULED',
               status = 'SCHEDULED',
               marketplace_status = 'SCHEDULED',
               booking_mode_version = booking_mode_version + 1,
               version = version + 1,
               last_mode_change_at = now(),
               updated_at = now()
           WHERE id = $1`,
          [requestId],
        );

        await saveSchedule(client, requestId, appointment);

        await client.query(
          `INSERT INTO request_booking_transitions(
             request_id, from_mode, to_mode, from_status, to_status,
             triggered_by_user_id, transition_reason, transition_metadata
           )
           VALUES($1, $2, $3, $4, $5, $6, 'PATIENT_REQUESTED_SCHEDULED', $7::jsonb)`,
          [
            requestId,
            fromMode,
            toMode,
            fromStatus,
            toStatus,
            patientUserId,
            JSON.stringify({ scheduledAt: appointment.toISOString() }),
          ],
        );

        return {
          requestId,
          bookingMode: 'SCHEDULED',
          status: 'SCHEDULED',
          scheduledAt: appointment.toISOString(),
        };
      }

      // 4. Transition to INSTANT
      if (toMode === 'INSTANT') {
        return this.retryInstantDispatchInternal(client, patientUserId, requestId, request);
      }

      throw new BadRequestException({ code: 'UNSUPPORTED_BOOKING_MODE' });
    });
  }

  /**
   * Retries instant dispatch search round for an unfulfilled or recovery-choice request.
   */
  async retryInstantDispatch(patientUserId: string, requestId: string) {
    return this.db.transaction(async client => {
      const reqRes = await client.query(
        `SELECT id, requester_user_id, status, booking_mode, version, booking_mode_version
         FROM care_requests
         WHERE id = $1
         FOR UPDATE`,
        [requestId],
      );
      if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
      const request = reqRes.rows[0];

      if (request.requester_user_id !== patientUserId) {
        throw new ForbiddenException({ code: 'FORBIDDEN_NOT_REQUEST_OWNER' });
      }

      return this.retryInstantDispatchInternal(client, patientUserId, requestId, request);
    });
  }

  private async retryInstantDispatchInternal(
    client: any,
    patientUserId: string,
    requestId: string,
    request: any,
  ) {
    const policy = (await client.query("SELECT value FROM app_settings WHERE key='dispatch'")).rows[0]?.value;

    await client.query(
      `UPDATE care_requests
       SET booking_mode = 'INSTANT',
           status = 'OFFERING',
           marketplace_status = 'SEARCHING',
           search_started_at = statement_timestamp(),
           search_expires_at = statement_timestamp() + $2::integer * interval '1 second',
           search_radius_meters = $3,
           version = version + 1,
           last_mode_change_at = now(),
           updated_at = now()
       WHERE id = $1`,
      [requestId, policy?.offerDurationSeconds ?? 60, policy?.radiusMeters ?? 10000],
    );

    await client.query(
      `INSERT INTO dispatch_jobs(request_id, attempts, next_run_at, updated_at)
       VALUES($1, 0, statement_timestamp(), statement_timestamp())
       ON CONFLICT (request_id) DO UPDATE
       SET attempts = 0, next_run_at = statement_timestamp(), updated_at = statement_timestamp()`,
      [requestId],
    );

    await client.query(
      `INSERT INTO request_booking_transitions(
         request_id, from_mode, to_mode, from_status, to_status,
         triggered_by_user_id, transition_reason
       )
       VALUES($1, $2, 'INSTANT', $3, 'OFFERING', $4, 'PATIENT_RETRY_INSTANT')`,
      [requestId, request.booking_mode, request.status, patientUserId],
    );

    await client.query(
      `INSERT INTO outbox_events(event_type, aggregate_id, payload)
       VALUES('request.created', $1, $2::jsonb)`,
      [requestId, JSON.stringify({ recipientUserId: patientUserId, requestId })],
    );

    return {
      requestId,
      bookingMode: 'INSTANT',
      status: 'OFFERING',
      retried: true,
    };
  }

  /**
   * Patient extends the waiting duration of an open request.
   */
  async extendOpenRequest(patientUserId: string, requestId: string, dto: ExtendOpenRequestDto) {
    return this.db.transaction(async client => {
      const reqRes = await client.query(
        `SELECT id, requester_user_id, status, open_expires_at, latest_acceptable_arrival_at
         FROM care_requests
         WHERE id = $1
         FOR UPDATE`,
        [requestId],
      );
      if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
      const req = reqRes.rows[0];

      if (req.requester_user_id !== patientUserId) {
        throw new ForbiddenException({ code: 'FORBIDDEN_NOT_REQUEST_OWNER' });
      }

      if (req.status !== 'OPEN_FOR_PROPOSALS') {
        throw new ConflictException({
          code: 'REQUEST_NOT_OPEN',
          message: 'الطلب ليس في حالة انتظار مفتوحة',
        });
      }

      const currentExpiry = req.open_expires_at ? new Date(req.open_expires_at) : new Date();
      const newExpiry = new Date(currentExpiry.getTime() + dto.additionalMinutes * 60000);

      let newLatestArrival = req.latest_acceptable_arrival_at
        ? new Date(req.latest_acceptable_arrival_at)
        : new Date(newExpiry.getTime() + 60 * 60000);
      if (newLatestArrival < newExpiry) {
        newLatestArrival = new Date(newExpiry.getTime() + 60 * 60000);
      }

      await client.query(
        `UPDATE care_requests
         SET open_expires_at = $2,
             latest_acceptable_arrival_at = $3,
             version = version + 1,
             updated_at = now()
         WHERE id = $1`,
        [requestId, newExpiry.toISOString(), newLatestArrival.toISOString()],
      );

      await client.query(
        `INSERT INTO outbox_events(event_type, aggregate_id, payload)
         VALUES('marketplace.request.updated', $1, $2::jsonb)`,
        [requestId, JSON.stringify({ requestId, openExpiresAt: newExpiry, extendedMinutes: dto.additionalMinutes })],
      );

      return {
        requestId,
        extended: true,
        openExpiresAt: newExpiry,
        latestAcceptableArrivalAt: newLatestArrival,
      };
    });
  }
}
