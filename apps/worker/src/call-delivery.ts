import type { Db } from './push.js';

const uuid = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

/** Recheck delayed delivery against current call state, independent of the claim lease. */
export async function callIsRinging(db: Db, callId: unknown, recipientId: unknown, version: unknown): Promise<boolean> {
  if (typeof callId !== 'string' || !uuid.test(callId) ||
      typeof recipientId !== 'string' || !uuid.test(recipientId) ||
      (typeof version !== 'number' && typeof version !== 'string') ||
      !Number.isSafeInteger(Number(version)) || Number(version) < 1) return false;
  const row = await db.query(`SELECT 1 FROM voice_call_sessions
    WHERE id=$1 AND receiver_user_id=$2 AND session_version=$3 AND call_status='RINGING'
      AND ring_expires_at>statement_timestamp()`, [callId, recipientId, Number(version)]);
  return Boolean(row.rowCount);
}
