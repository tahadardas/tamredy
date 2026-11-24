import type { PoolClient } from 'pg';
import { invalid } from '../common/errors.js';

export const schedulePolicy = {
  leadMinutes: 15,
  minimumAdvanceMinutes: 30,
  maximumAdvanceDays: 30,
};

export function schedulingEnabled() {
  return process.env.SCHEDULED_VISITS_ENABLED === 'true';
}

export function validateAppointment(input?: string): Date | null {
  if (input === undefined) return null;
  if (!schedulingEnabled()) invalid('Scheduled visits are disabled');
  const time = Date.parse(input);
  const advance = time - Date.now();
  if (!Number.isFinite(time) || advance < schedulePolicy.minimumAdvanceMinutes * 60_000 ||
      advance > schedulePolicy.maximumAdvanceDays * 86_400_000) {
    invalid('Appointment must be 30 minutes to 30 days in the future');
  }
  return new Date(time);
}

export async function saveSchedule(client: PoolClient, requestId: string, appointment: Date) {
  await client.query(`INSERT INTO scheduled_visits(request_id,appointment_at,release_at)
    VALUES($1,$2,$2::timestamptz-$3::integer*interval '1 minute')`,
  [requestId, appointment, schedulePolicy.leadMinutes]);
}
