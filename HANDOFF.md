# TAMREEDY HANDOFF — Medical Aero Premium & Core Engineering

**Status:** ACTIVE_PROGRESS  
**Branch:** feature/aero-signature  
**Last Verified Commit:** `0683927`  
**Last Update:** 2026-11-23  
**Current Phase:** Phase 6, 7, 8 & 9 Complete (Aero Design, Syrian Phone, Patient & Nurse Redesign, Admin Aero Control Panel, Full Database Indexing Audit)  
**Overall Status:** Green (All Tests Passing, 0 Redundant Indexes, Database Audited)

---

## 1. PROJECT STATUS
- **Project Name:** Tamreedy (تمريضي) — On-demand home healthcare platform
- **Active Branch:** `feature/aero-signature`
- **Target Apps:**
  - `apps/patient_app` (Flutter)
  - `apps/nurse_app` (Flutter)
  - `packages/flutter_core` (Shared Flutter Design & Auth)
  - `apps/api` (NestJS Authentication & Session Persistence)
- **All Monorepo Test Suites:** PASS
  - Backend Auth Tests: 8/8 PASS
  - Backend Domain Tests: 5/5 PASS
  - Backend Worker Tests: 4/4 PASS
  - Flutter Syrian Phone Normalizer Tests: 8/8 PASS
  - Flutter Patient App Tests: 6/6 PASS
  - Flutter Nurse App Tests: 5/5 PASS
  - Flutter Analyzer (`flutter analyze`): 0 issues across all 3 Flutter targets!

---

## 2. ORIGINAL REQUIREMENTS & ARCHITECTURAL DECISIONS
1. **Medical Aero Premium & Aero Signature:**
   - Light Mode canvas with delicate, clinical frosted glass (`#F5FAFD`, `#DFF4F2`).
   - Primary Navy `#074577`, Accent Teal `#079D90`, Text `#163B52`.
   - Multi-layer diffuse elevation shadows (`AeroShadows`), illuminated borders, 20-26px radii (`AeroRadii`).
   - Flutter implicit motion tokens (`AeroMotionTokens` with spring curves and responsive micro-interactions).
2. **Persistent Trusted Device Authentication (P0):**
   - User signs in once on a trusted device; session survives for months without accidental logout.
   - Sliding session expiry (180 days); server-side device session tracking in `device_sessions`.
   - Single-flight refresh token rotation with family revocation on replay.
   - `AuthGate` refactored into distinct states (`initializing`, `authenticated`, `offlineWithSavedSession`, `reauthenticationRequired`, `signedOut`, `accountSuspended`).
   - Transient network loss or 5xx never wipes local credentials or triggers `logout()`.
3. **Syrian Phone Number Standard (P0):**
   - Fixed visual prefix `+963` in dedicated capsule (`AeroSyrianPhoneField`).
   - User types standard 10-digit local format: `09XXXXXXXX` (e.g. `0987080330`).
   - Unified sanitization and normalization to E.164: `+963987080330` (strips leading 0, prepends +963).
   - Applied across `login_screen.dart`, `register_screen.dart`, and `nurse_apply_screen.dart`.
4. **Nurse Full-Screen Deep Navy Offer (`#102F49`):**
   - Full-screen immersion `#102F49` with teal pulsing glowing aura (`AeroColors.accentTeal`).
   - Insistent ringtone + alarm haptics (`OfferAlarm`), one-tap mute button.
   - Large bold countdown circle clamped to `expires_at`.
   - Clear service, area, distance, and earnings breakdown.
   - Large glowing teal accept button (`c.accept`) with atomic first-accept lock and ghost decline button (`c.decline`).
5. **Floating Aero Dock & Smart CTA:**
   - Shared floating curved dock navigation pill for both apps (`AeroFloatingDock` / `TamBottomNav`).
   - Smart CTA for patient (`AeroSmartCta`: Option C hero button + floating button when hero scrolls out of view).
6. **Zero Breaking Changes:**
   - Preserved all existing API routes, medical pricing, and dispatch mechanics.

---

## 3. COMPLETED WORK
- **Phase 1:** Baseline verification and sequential handoff ledger initialized.
- **Phase 2 (Persistent Authentication):**
  - Created migration `infra/db/migrations/019_device_sessions_and_persistent_auth.sql`.
  - Updated `apps/api/src/auth/auth.service.ts`, `auth.controller.ts`, `account.controller.ts`, `auth.guard.ts`.
  - Added hardware-anchored device ID, sliding 180-day refresh, session revocation, single-flight refresh in `flutter_core/api.dart`.
  - Rewrote `AuthGate` with resilient `AuthGateStatus.offlineWithSavedSession`.
  - 8/8 backend auth tests passing.
- **Phase 3 (Syrian Phone Numbers):**
  - Created `SyrianPhoneNormalizer` with complete unit test suite (8/8 PASS).
  - Created `AeroSyrianPhoneField` with fixed `+963` capsule, Arabic digit translation, and paste normalization.
  - Integrated into `login_screen.dart`, `register_screen.dart`, and `nurse_apply_screen.dart`.
- **Phase 4 & 5 (Aero Tokens & Shared Widgets):**
  - Created `AeroColors`, `AeroRadii`, `AeroShadows`, `AeroTypography`, `AeroMotionTokens`.
  - Created `AeroScaffold`, `AeroGlassCard`, `AeroButton`, `AeroFloatingDock`, `AeroSmartCta`, `AeroGlassSheet`.
  - Exported through `packages/flutter_core/lib/src/design/aero_design.dart` and `tamreedy_core.dart`.
  - Upgraded `TamCard`, `HeroCard`, `PrimaryButton`, and `TamBottomNav` to Medical Aero styling.
- **Phase 6 & 7 (Patient & Nurse App Redesign):**
  - Integrated Floating Aero Dock navigation across both apps.
  - Implemented Full-Screen Deep Navy Offer (`#102F49`) with glowing teal halo, countdown timer, sound mute, and accept/decline in `apps/nurse_app/lib/screens/visit.dart`.
  - All unit/flow tests pass in both apps (6/6 patient, 5/5 nurse).
- **Phase 8 (Admin Web Aero Control Panel Redesign):**
  - Implemented `AeroHero` with deep navy gradient (`#102F49` to `#074577`), illuminated borders, dual ambient glow orbs, live pulsating indicator dot, and operational status pills in `apps/admin_web/src/ui.tsx`.
  - Upgraded `Dashboard` (`apps/admin_web/src/pages.tsx`) and `DispatchMonitor` (`apps/admin_web/src/pages_dispatch.tsx`) with `AeroHero` and live operational telemetry.
  - Upgraded CSS tokens, frosted glass cards (`.stat`, `.panel`, `.card`), illuminated borders, and diffuse shadows in `apps/admin_web/src/style.css`.
  - Upgraded weekly booking bar chart with teal-to-navy gradient and hover scaling.
  - Upgraded `login-card` with frosted glass and illuminated border.
  - Built production bundle with `npm run build` in `apps/admin_web` (0 errors).
  - Updated server deployment archives: `deploy/tamreedy-server.tar.gz` and `deploy/tamreedy-server.zip`.
- **Phase 9 (Database Audit & Index Optimization):**
  - Full relational schema and indexing audit against ISO/IEC 9075, ANSI SQL, and PostgreSQL standards.
  - Identified and eliminated 7 duplicate/prefix-redundant indexes causing write amplification and memory bloat.
  - Created migration `infra/db/migrations/020_database_audit_and_index_optimization.sql`:
    - Dropped duplicates on `dispatch_jobs`, `visit_reviews`, `refresh_tokens`, `device_sessions`, `incidents`, `request_assignments`, `users`.
    - Added missing critical foreign key indexes on `promo_claims`, `nurse_documents`, `nurses(area_id)`, `nurse_applications`, `nurse_credentials`, `audit_log`, `broadcasts`, `nurse_settlements`, `nurse_rewards`, `pack_grants`, `users(created_by)`.
    - Added GiST spatial index on `care_requests(location)` for geographic queries and analytics.
  - 100% verified: all 45 tables have primary keys, all money columns use exact `numeric(18,2)`, all timestamps use `timestamptz`.

---

## 4. CURRENT TASK
- Final check of release bundle commands and deployment scripts for Plesk server.
- Ready to commit and push changes on branch `feature/aero-signature`.

---

## 5. TEST VERIFICATION
- `node --test apps/api/tests/auth.test.mjs`: PASS (8/8)
- `node --test apps/api/tests/domain.test.mjs`: PASS (5/5)
- `node --test apps/api/tests/dispatch_diagnostics.test.mjs apps/worker/tests/dispatch.test.mjs`: PASS (4/4)
- `packages/flutter_core/test/syrian_phone_normalizer_test.dart`: PASS (8/8)
- `apps/patient_app test`: PASS (6/6)
- `apps/nurse_app test`: PASS (5/5)
- `flutter analyze` across all 3 Flutter packages: CLEAN (0 issues)

---

## 6. NEXT MODEL INSTRUCTIONS
If resuming:
1. Verify HEAD on `feature/aero-signature`.
2. Inspect `HANDOFF.md` and `handoff/checkpoint.json`.
3. All code is clean, fully tested, and passing all monorepo checks.

---

## Open Dispatch implementation checkpoint

- CURRENT_BRANCH: codex/open-dispatch
- LAST_COMMIT: cb0066ea6a925aeac16e85852c18897ab5691b34 (verified baseline; origin/feature/aero-signature matched)
- COMPLETED: Phase 1 baseline and targeted audit. Phase 2 additive database foundation and invariant tests. Existing worker uses waves, automatic departure remains in the nurse app, cancellation has no evidence ledger, and push currently performs network I/O inside its outbox transaction.
- IN_PROGRESS: Staging verification and remaining workflows. Local implementation and build/test gates were run.
- NEXT_EXACT_ACTION: In an authorized disposable PostgreSQL/PostGIS environment, apply 021–024, run concurrency.integration.mjs with TEST_DATABASE_URL, then run real-device FCM and EXPLAIN checks before reviewing rollout.
- PENDING: Staging concurrency, representative PostGIS load and real-device FCM; nurse appeal submission UI, protected evidence attachments, distinct arrived/early-termination incident workflows, and detailed open-search exclusion reporting. The opt-in worker and admin setting are implemented and tested off production.
- FILES_CHANGED: HANDOFF.md, handoff/checkpoint.json, migration 021, docs/MIGRATION_021.md and apps/api/tests/open_dispatch_foundation.test.mjs. Existing dirty apps/nurse_app/lib/screens/home.dart belongs to the workspace baseline.
- TEST_RESULTS: API build passed. Focused baseline tests 10 passed, 1 skipped. Migration 021 passed a pre-existing-data and integrity test (PGlite).
- KNOWN_ISSUES: PGlite tests substitute geometry; they cannot establish PostGIS query plans or concurrent multi-connection behavior.
- DECISIONS: Preserve legacy in-flight records and keep open dispatch disabled until a separately authorized rollout. Preserve billing and historical records.
- MIGRATIONS: 021 adds search/closure, ETA, cancellations, appeals and audit invariants; 022 adds snapshot thresholds and durable eligibility wake-ups; 023 adds outbox claim/lease columns without backfill; 024 adds opt-in delayed departure reminders.
- BLOCKERS: No disposable PostgreSQL/PostGIS connection in TEST_DATABASE_URL; no Docker or psql detected.

- Phase 3 evidence: 100 recipients matched initially on eligibility change, a 101st joined under the same deadline, no duplicates on reconciliation, and no new offer after expiry. Legacy waves still passed. Admin build and policy validation passed. Corrected the admin test fixture to include baseline migration 019.

- Phase 4 evidence: expired offer rejected, winning acceptance replay after departure returns the original assignment, ETA computed outside the transaction and persisted once. Billing/routes regression suite 23/23 and nurse Flutter 5/5 passed. PostGIS and multi-connection acceptance/cancellation remain to verify.

- Phase 5 evidence: cancel locks request → nurse → assignment, evaluates server time, requires acknowledgement for counted cases, writes one record and one event, and replays the previous result. Health reasons and notes are excluded from outbox payloads. Added the patient-owned cancellation-policy preview endpoint. Existing clients with no cancellation DTO receive no negative commitment impact. The post-travel pause is a disabled-by-default setting.

- Phase 6 evidence: authenticated patient history, active-offer-only nurse summaries, configurable 90-day window and minimum five assigned visits. Test confirms a closed offer cannot fetch a summary, small samples redact counts, and open patient appeals suppress impact.

- Phase 7 evidence: ownership, deadline, legal transitions, duplicate protection, private notes and audited review. Integrated test covers open appeal suppression, approval history, and replay retaining the original cancellation decision. Protected evidence attachments are still pending. Concurrent workspace commit 61fb950 was preserved.

- Phase 8 evidence: verified Flutter patient 6/6, nurse 5/5, route audit 3/3 and admin build. Added Aero cancellation sheet with preview, retry key and server acknowledgement, patient commitment and appeal screens, nurse offer summary, and admin appeal queue.

- Phase 9 evidence: 22 notification/worker/performance tests passed, nurse Flutter 5/5, patient Flutter 6/6. Recovered an expired claim after a simulated worker crash, verified independent channel claims and dedup of recorded deliveries. Firebase acceptance remains distinct from device receipt; live FCM, independent PostGIS sessions, and delivery across device restarts remain unverified.

- Phase 10 evidence: pnpm -r build green; Node API and worker 119 passed / 2 skipped (live PostgreSQL missing); Flutter patient 6, nurse 5, and shared 12 passed. Added the genuine multi-connection test for ten acceptors and cancellation racing acceptance. Delayed reminders tested once without creating a penalty. Declared Android real device unavailable. No deploy or push. See docs/OPEN_DISPATCH_DELIVERY_AR.md.

## Guardian Safety and Aero Map-First

Phase 0 recorded on 2026-11-24. Branch: codex/guardian-safety.
Local baseline: 827b02370035ed0c3006d481037e799979d4328c (Open Dispatch).
Remote reference: feature/aero-signature at cb0066ea6a925aeac16e85852c18897ab5691b34.
API, Worker and Admin Web built successfully. Baseline Node command exited 0.
Scope and evidence are tracked in docs/IMPLEMENTATION_MATRIX.md.
Next: enforce HTTPS and verify owner-bound session revocation across HTTP and Socket.IO, then audit the recovery workflow.
Production deployment is deferred. No schema or endpoint changes in phase 0.

### Guardian phase 1 — in progress

- HTTP auth and new Socket.IO connections verify device-session ownership and revocation.
- Refresh preserves the existing device binding. Logout revokes the family and bound session using the refresh credential.
- Flutter release URLs require HTTPS. Android allows cleartext only through debug resources. Default URL is https://tamredy.dardus.com.sy.
- API rebuild passed and both device-session regression tests passed. Android build, signing and physical tests remain pending.
- Public hostname lookup failed from the workstation. Restore public DNS and trusted TLS before distributing production builds.
- Existing open Socket.IO connections still need revocation handling. Complete recovery design and delivery verification.
- Existing refresh/logout contracts and database schema were retained. No endpoints or migrations added. No deployment performed.
- Continue phase 1 before Aero phase 2. The matrix records all subsequent sections as pending.

### Guardian phase 1 — manual recovery and session revocation

- Added migration 025 for recovery expiry and token version. Apply before starting the updated API.
- Existing admin reset routes now issue unique 30-minute credentials and revoke sessions. Account password changes also retire prior access tokens.
- Restricted device revocation to the authenticated owner. Already connected sockets are rechecked before private event delivery.
- Both login screens have a manual recovery entry point. See docs/PASSWORD_RECOVERY_AR.md for verification, delivery and the build-time support contact.
- Node workspace build, focused auth and socket regressions, and the shared Flutter suite passed. Production DNS still failed and ADB found no attached devices. Verify production TLS, configured support and physical Android releases before rollout.
- No new HTTP endpoints. No server deployment. Continue with Aero phase 2.

### Guardian phase 2 — shared Aero login

- Shared patient and nurse login now has a visible password toggle, a separate recovery action below the password, a filled Aero sign-in button and a separate outline registration or nurse application button.
- Widget regression verifies password visibility and the manual recovery dialog. Patient and nurse demo suites passed. Pending: physical RTL, TalkBack and large text review, then the map-first shell and saved places.
- No endpoints or migrations added in phase 2. No deployment.

### Guardian phase 3 — patient home map slice

- Patient home now keeps one map mounted under a draggable service sheet. The visible viewport resizes as the sheet moves.
- The RTL drawer opens orders, wallet and account. Wallet opens the existing screen. No balance is displayed in the home button because the production controller does not load wallet balance.
- Existing service, tracking, code claim and emergency notice actions remain. The map shows a visit pin only when the controller has a point.
- Patient Flutter suite passed 7 tests, including service-to-booking and navigation/keyboard layout. Physical GPS and accessibility remain unverified.
- No endpoints or migrations added in this slice. Continue phase 3 with saved places, visit-address flow and authoritative wallet data.

### Guardian phase 3 — confirm visit address from home

- The patient can choose and confirm a visit address before selecting a service. Draft edits stay local until confirmation. Booking reopens the confirmed point and address details.
- If the region catalogue fails, production shows a retry and allows GPS or manual pin selection. Sample regions are limited to demo mode.
- Patient Flutter suite passed 8 tests, including confirmation without submitting a request, booking, and navigation layout.
- No endpoints or migrations added. Saved places, wallet data, and device verification remain.

### Guardian phase 3 — saved places

- Migration 026 adds user_saved_places with an owner foreign key, coordinate bounds, place types and a partial unique index for the single default. Apply before running the updated API.
- Added patient-only GET/POST /v1/patient/saved-places, PUT/DELETE /v1/patient/saved-places/:id and POST /v1/patient/saved-places/:id/use.
- The visit location picker can save a pin, list and select places, edit details, set a default and delete. Selection updates recency and still requires address confirmation before booking. The default sorts first.
- API built. One PGlite lifecycle and access-control test, three route audits and nine patient Flutter tests passed. The saved place Flutter test uses a simulated API response. No server deployment or physical verification.
- Remaining: wallet status and real ledger availability, physical map/GPS and accessibility, and later Guardian phases.

### Guardian phase 3 — wallet availability

- The production wallet screen reads GET /v1/wallet/status, shows server-disabled or retry states, and omits local demo balance and transactions. Cash is the initial production payment choice.
- Provider and ledger remain unavailable on the current backend. No payment API, prices, fees or migrations changed.
- Nine patient demo tests and one non-demo wallet widget test passed. The wallet test simulates an API failure followed by a disabled response.
- ADB found no device. Physical phase 3 verification remains pending. Continue with the phase 4 booking and tracking flow review alongside that release check.

### Guardian phase 4 — booking review

- Booking now supports selection among consenting beneficiaries returned by the existing patient endpoint. The chosen beneficiary is included in the existing idempotent request.
- The location step opens an explicit review sheet before dispatch. It summarizes the visit, address, patient, estimate and method of payment. Concurrent taps cannot submit twice from the controller.
- Patient demo flow and two non-demo tests passed. The non-demo booking test checks the selected ID, confirmed address and one request when submission overlaps.
- No endpoints or migrations added. Continue phase 4 with tracking, scheduling gate and history verification. Physical test and later Guardian phases remain pending.

### Guardian phase 4 — reconnect tracking and visit history

- Reconnect restores an active request when the app has no request ID. Concurrent tracking reads for the same ID share one fetch. A late route response cannot attach to a different request, and a missing fresh nurse fix clears the route.
- History now separates network errors from empty results and offers reload. A completed visit opens its existing server invoice without mutating the current booking. Non-completed requests show their real state.
- Three non-demo tests passed, including reconnect and tracking coalescing. The patient demo suite passed nine tests during the tracking changes.
- Existing tracking, active request, history and bill APIs reused. No new endpoints or migrations. Scheduling and device verification remain pending before claiming phase 4 complete.

### Guardian phase 4 — scheduled visits

- Migration 027 adds scheduled_visits and extends request and cancellation states. Existing immediate orders still create dispatch jobs immediately.
- GET /v1/requests/scheduling exposes server capability. POST /v1/requests accepts optional scheduledAt with timezone. Mobile shows date and time only when enabled.
- SCHEDULED_VISITS_ENABLED defaults off. The current policy accepts times from 30 minutes to 30 days ahead, starts search 15 minutes before the appointment and marks unreleased missed appointments unfulfilled. It does not reserve a nurse.
- API and Worker must use the same rollout flag. The worker also reads the Open Dispatch flag and current dispatch settings at release. Apply migration 027 before enabling. Drain pending scheduled visits before turning the flag off.
- Worker integration exercised no early job, one due job, open search initialization, expiry, and cancelled exclusion using PGlite. Real PostGIS concurrency and Android verification remain pending.
- No deployment performed. Continue phase 4 verification, then implement phase 5 Guardian backend.

### Guardian phase 5 — foundation

- Migration 028 adds safety_sessions, safety_location_points, emergency_events and emergency_event_actions.
- Added nurse-only GET /v1/safety/me/status, POST /v1/safety/sos, GET /v1/safety/events/:id, POST /v1/nurse/safety/sessions/start, POST /v1/nurse/safety/sessions/:id/locations/batch and POST /v1/nurse/safety/sessions/:id/checkout.
- A recording session starts only for the assigned nurse once the visit is underway. GPS batches preserve capture and receipt times, reject altered sequence replays and reject new captures after checkout. Initial capture window is capped server-side at 12 hours.
- SOS creation, RECEIVED history and outbox are atomic and idempotent. RECEIVED means server persisted only. Checkout does not close the SOS. No operations consumer, human acknowledgement, escalation or nurse UI is connected.
- API built. PGlite lifecycle and three route audits passed. Geography was substituted in the test harness. Real PostGIS testing, check-ins, policy versions, incident workflows, staff handling and retention remain pending. No deployment.

### Guardian phase 5 — policy versions and safety check-ins

- Migration 029 adds safety_policies, safety_policy_versions, safety_checkins, safety_checkin_responses and safety_alerts. New sessions pin the current standard policy; pre-migration sessions are not enrolled retroactively.
- Added nurse-only GET/POST /v1/nurse/safety/sessions/:id/checkin. Owner-scoped responses support OK, MORE_TIME, HELP and SAFE_EXIT with idempotency and one extension per prompt.
- Worker queues the prompt, reminder and missed-check-in alert atomically. Help and safe-exit responses record alerts for future staff review; they do not end the visit. Checkout cancels pending prompts. Missed prompts trigger no penalties.
- Initial policy prompts after 20 minutes, reminds after two minutes and allows three more minutes. One extension adds five minutes. These are initial configuration values, pending operational validation.
- GUARDIAN_CHECKINS_ENABLED defaults off. It gates worker polling. Check-in signals are queued but app presentation, staff acknowledgement and escalation are not wired yet. No deployment.
- API and Worker built. PGlite lifecycle and three route audits passed. Real PostGIS and concurrency tests remain pending.

### Guardian staff case handling

- Migration 030 adds explicit safety staff grants, the SOS/check-in case queue and its action history. It enqueues newly recorded incidents transactionally and backfills existing reports.
- Added GET /v1/admin/safety/events, GET /v1/admin/safety/events/:id and POST actions acknowledge, escalate, resolve under that path. Existing staff auth plus an active safety grant is required. Operator queue previews are redacted; operators can open only their assigned cases. Supervisors can resolve with an action note.
- Action writes lock the case, validate the version and persist the actor, note and idempotency key. SOS changes propagate to the reporting nurse through the existing private realtime mechanism. Queue and detail reads and changes are audited.
- API build and four targeted tests passed. The lifecycle test covers non-granted admin denial, operator isolation, replay, stale version, escalation, supervisor resolution and nurse-visible state.
- No staff grants were provisioned. Dashboard, shift presence enforcement, supervisor handover, external delivery and human-response verification remain pending. No deployment.
