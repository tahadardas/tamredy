# Tamreedy Security & Privacy Review

## Executive summary

The P2 review found and repaired high-impact authorization, medical privacy, session-binding, predictable temporary-password, and contact-data exposure defects. The API remains bearer-token based; classic cookie CSRF does not apply. Runtime verification is intentionally deferred to P4 per the requested execution order.

## Remediated findings

### SEC-001 — High — Commercial administrators could read medical records

- Location: `apps/api/src/health-records/health-records.service.ts:38-95`
- Evidence: `ADMIN` and `CLINICAL_REVIEWER` were treated as an unconditional medical-record bypass.
- Impact: a commercial administrator could retrieve a beneficiary's full medical profile without a care relationship or scoped review.
- Fix: removed the admin bypass; owners retain access, nurses require an active assignment plus explicit request context, and clinical reviewers require a pending review for that exact request. Consent is checked for non-owner access.
- Defense in depth: the explicit permission matrix is in `apps/api/src/auth/permissions.ts:1-25` and snapshotted by migration 057.

### SEC-002 — High — Sensitive access auditing failed open

- Location: `apps/api/src/health-records/health-records.service.ts:88-95`
- Evidence: insertion into `health_record_access_audit` ended with `.catch(() => {})`.
- Impact: medical reads could succeed without an audit record.
- Fix: audit failure now aborts the operation. Migration 057 makes security/clinical audit tables immutable.

### SEC-003 — High — Clinical form IDOR/BOLA

- Location: `apps/api/src/health-records/health-records.service.ts:269-282`
- Evidence: `getNurseFormConfig` loaded a request by ID without joining the authenticated nurse's active assignment.
- Impact: a nurse could enumerate request IDs and retrieve another visit's clinical form context.
- Fix: the query now requires the authenticated nurse, an active assignment, and a valid visit state.

### SEC-004 — High — Device sessions were optional in production

- Locations: `apps/api/src/auth/auth.guard.ts:43-55`, `apps/api/src/auth/auth.service.ts:181-190`
- Evidence: access tokens without `dsi` were accepted and bound refresh tokens could be rotated without presenting their device ID.
- Impact: a stolen bearer/refresh token had weaker revocation binding.
- Fix: production access requires a bound device session, refresh requires the matching device ID, and the admin client now supplies a per-tab opaque device identifier. Legacy refresh tokens may bind once; legacy access-token bypass is disabled by production configuration.

### SEC-005 — High — Predictable staff temporary passwords

- Locations: `apps/api/src/admin/admin-users.controller.ts`, `apps/api/src/admin/admin-nurses.controller.ts`, `apps/api/src/auth/applications.controller.ts`
- Evidence: account provisioning could fall back to a shared configurable default such as `123456`.
- Impact: newly provisioned accounts were guessable before first use.
- Fix: provisioning now generates a 20-character random one-time password, forces change, and expires it after 30 minutes.

### SEC-006 — Medium — Medical/contact phone leakage

- Locations: `apps/api/src/chat/chat.service.ts:108-118`, `apps/api/src/voice/voice.service.ts:260-266`, `apps/api/src/requests/request-recovery.service.ts`
- Evidence: chat participants, voice session details, and recovered visits returned real phone numbers.
- Impact: users could bypass platform communication controls and retain contact data beyond operational need.
- Fix: chat and voice return display identities only; recovery no longer returns real numbers; operational admin lists expose masked numbers where a contact hint remains necessary.

### SEC-007 — Medium — Reviewer dashboard role conflict

- Locations: `apps/admin_web/src/session.ts:45-64`, `apps/admin_web/src/main.tsx:250-400`
- Evidence: application logic supported `CLINICAL_REVIEWER`, but login/refresh rejected every non-ADMIN role.
- Impact: reviewers either could not work or would be tempted to use overprivileged admin accounts.
- Fix: reviewer sessions are accepted, their navigation is restricted, and a dedicated clinical-review queue/evidence/decision page was added. Server-side permissions remain authoritative.

### SEC-008 — Medium — Permissive production origin and document-key fallback

- Locations: `apps/api/src/main.ts:6-23`, `apps/api/src/admin/doc-store.ts:31-44`
- Evidence: missing `ALLOWED_ORIGINS` enabled all origins and encrypted documents could reuse the JWT secret.
- Impact: weaker browser boundary configuration and coupled secret rotation for medical documents.
- Fix: production now fails closed without an origin allowlist and an independent `DOCS_ENC_KEY`; path containment uses `path.relative` rather than a prefix comparison. The admin reverse proxy now sends CSP, anti-framing, referrer, and permissions headers.

### SEC-009 — Medium — SOS alert lacked explicit recipients

- Location: `apps/api/src/safety/safety.repository.ts:84-94`
- Evidence: the outbox payload contained an event ID but no users for realtime/push delivery.
- Impact: the case existed in the database, but active safety staff might not receive immediate notification.
- Fix: the transactional SOS outbox event now includes all active, granted safety staff while preserving the idempotent client event receipt.

## Residual risks requiring operational decisions

1. **High — Staff MFA is not yet available.** OTP explicitly excludes staff roles and password login remains the staff mechanism. Deploying staff MFA requires a licensed verification provider and recovery policy.
2. **Medium — Browser refresh tokens use `sessionStorage`.** CSP and short access tokens reduce exposure, but an XSS can still read the refresh token. A same-origin BFF with an HttpOnly cookie is a future architectural option and would require CSRF controls.
3. **Medium — Uploaded clinical files are magic-byte validated and encrypted but not malware-scanned.** Add a quarantined scanning service before permitting broader document formats or external distribution.
4. **Medium — Consent is beneficiary-level.** Field-level, purpose-bound consent and expiring share grants remain necessary before external institutions receive medical records.
5. **Low — Emergency escalation is internal.** The application correctly records and alerts internal Guardian staff; it must not claim automatic dispatch to public emergency agencies until a licensed integration exists.

## Verification status

Static inspection and patch consistency checks were performed during P2. Build, type checking, database migration rehearsal, and security scenario tests are deferred to P4 by explicit instruction.
