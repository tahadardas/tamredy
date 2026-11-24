import type { PoolClient } from 'pg';
import { generatePassword, hashPassword } from './auth.service.js';

export async function issueManualRecoveryPassword(
  db: PoolClient,
  userId: string,
): Promise<string> {
  const password = generatePassword(20);
  await db.query(
    `UPDATE users SET password_hash=$2, must_change_password=true, failed_logins=0,
      locked_until=NULL, auth_version=gen_random_uuid(), temporary_password_expires_at=now()+interval '30 minutes' WHERE id=$1`,
    [userId, hashPassword(password)],
  );
  await db.query(
    'UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1',
    [userId],
  );
  await db.query(
    'UPDATE device_sessions SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1',
    [userId],
  );
  return password;
}
