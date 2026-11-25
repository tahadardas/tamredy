import type { PoolClient } from 'pg';
import { conflict, forbidden, missing } from '../common/errors.js';

export async function lockAccountAdministration(c: PoolClient, actor: string) {
  await c.query("SELECT pg_advisory_xact_lock(hashtext('tamreedy.account_administration')::bigint)");
  if (!(await c.query("SELECT 1 FROM users WHERE id=$1 AND role='ADMIN' AND status='ACTIVE'", [actor])).rowCount) forbidden();
}

export async function removeAccount(c: PoolClient, actor: string, id: string, roles?: string[]) {
  if (actor === id) conflict('CANNOT_DELETE_SELF');
  await lockAccountAdministration(c, actor);
  const nurse = (await c.query('SELECT id,work_status FROM nurses WHERE user_id=$1 FOR UPDATE', [id])).rows[0];
  const user = (await c.query('SELECT role,status FROM users WHERE id=$1 FOR UPDATE', [id])).rows[0];
  if (!user || (roles && !roles.includes(user.role))) missing();
  if (user.status === 'DELETED') return { id, deleted: true };
  if (user.role === 'ADMIN' && user.status === 'ACTIVE') {
    const other = await c.query("SELECT 1 FROM users WHERE id<>$1 AND role='ADMIN' AND status='ACTIVE' LIMIT 1", [id]);
    if (!other.rowCount) conflict('LAST_ADMIN');
  }
  const active = await c.query(`SELECT 1 FROM care_requests r WHERE
    (r.requester_user_id=$1 OR EXISTS (SELECT 1 FROM request_assignments a
      WHERE a.request_id=r.id AND a.nurse_id=$2 AND a.status='ACTIVE'))
    AND r.status NOT IN ('COMPLETED','CANCELLED','UNFULFILLED','EXPIRED','ESCALATED') LIMIT 1`, [id, nurse?.id ?? null]);
  if (active.rowCount || (nurse && ['RESERVED','EN_ROUTE','IN_SERVICE'].includes(nurse.work_status))) {
    conflict(nurse ? 'NURSE_ON_ACTIVE_VISIT' : 'ACCOUNT_HAS_ACTIVE_REQUESTS');
  }
  await c.query(`UPDATE users SET status='DELETED',phone_e164='deleted-'||id::text,
    auth_version=gen_random_uuid() WHERE id=$1`, [id]);
  await c.query('UPDATE refresh_tokens SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [id]);
  await c.query('UPDATE device_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [id]);
  await c.query('DELETE FROM device_tokens WHERE user_id=$1', [id]);
  if (nurse) await c.query(`UPDATE nurses SET availability_intent='OFFLINE',work_status='OFFLINE',updated_at=now() WHERE id=$1`, [nurse.id]);
  if (user.role === 'PATIENT') {
    await c.query(`UPDATE care_plans SET status='CANCELLED',updated_at=now()
      WHERE patient_user_id=$1 AND status IN ('ACTIVE','PAUSED')`, [id]);
    await c.query(`UPDATE care_plan_occurrences SET status='CANCELLED' WHERE status='PENDING'
      AND care_plan_id IN (SELECT id FROM care_plans WHERE patient_user_id=$1 AND status='CANCELLED')`, [id]);
  }
  const action = nurse ? 'nurse.deleted' : user.role === 'PATIENT' ? 'user.deleted' : 'staff.deleted';
  await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail)
    VALUES($1,$2,$3,$4,jsonb_build_object('role',$5::text))`, [actor,action,nurse ? 'nurse' : 'user',nurse?.id ?? id,user.role]);
  return { id, deleted: true };
}
