-- Migration 051: Ensure every ADMIN has active SAFETY_SUPERVISOR and evidence export grants

INSERT INTO safety_staff_grants (user_id, permission, granted_by, granted_at)
SELECT id, 'SAFETY_SUPERVISOR', id, now()
FROM users
WHERE role = 'ADMIN'
ON CONFLICT (user_id) DO UPDATE
SET permission = 'SAFETY_SUPERVISOR', revoked_at = NULL;

INSERT INTO safety_evidence_export_grants (user_id, granted_by, granted_at)
SELECT id, id, now()
FROM users
WHERE role = 'ADMIN'
ON CONFLICT (user_id) DO UPDATE
SET revoked_at = NULL;
