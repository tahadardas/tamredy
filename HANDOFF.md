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
- IN_PROGRESS: Phase 6, commitment history.
- NEXT_EXACT_ACTION: Add authenticated commitment summaries scoped to patient ownership and active nurse offers, then test privacy and rolling time windows.
- PENDING: Phases 6–10, distinct arrived/early-termination incident workflows, configurable delayed-departure alerts and detailed open-search exclusion reporting. The opt-in worker and admin setting are implemented and tested off production.
- FILES_CHANGED: HANDOFF.md, handoff/checkpoint.json, migration 021, docs/MIGRATION_021.md and apps/api/tests/open_dispatch_foundation.test.mjs. Existing dirty apps/nurse_app/lib/screens/home.dart belongs to the workspace baseline.
- TEST_RESULTS: API build passed. Focused baseline tests 10 passed, 1 skipped. Migration 021 passed a pre-existing-data and integrity test (PGlite).
- KNOWN_ISSUES: PGlite tests substitute geometry; they cannot establish PostGIS query plans or concurrent multi-connection behavior.
- DECISIONS: Preserve legacy in-flight records and keep open dispatch disabled until a separately authorized rollout. Preserve billing and historical records.
- MIGRATIONS: 021 adds search/closure, ETA, cancellations, appeals and audit invariants; 022 adds snapshot thresholds and durable eligibility wake-ups.
- BLOCKERS: No disposable PostgreSQL/PostGIS connection in TEST_DATABASE_URL; no Docker or psql detected.

- Phase 3 evidence: 100 recipients matched initially on eligibility change, a 101st joined under the same deadline, no duplicates on reconciliation, and no new offer after expiry. Legacy waves still passed. Admin build and policy validation passed. Corrected the admin test fixture to include baseline migration 019.

- Phase 4 evidence: expired offer rejected, winning acceptance replay after departure returns the original assignment, ETA computed outside the transaction and persisted once. Billing/routes regression suite 23/23 and nurse Flutter 5/5 passed. PostGIS and multi-connection acceptance/cancellation remain to verify.

- Phase 5 evidence: cancel locks request → nurse → assignment, evaluates server time, requires acknowledgement for counted cases, writes one record and one event, and replays the previous result. Health reasons and notes are excluded from outbox payloads. Added the patient-owned cancellation-policy preview endpoint. Existing clients with no cancellation DTO receive no negative commitment impact. The post-travel pause is a disabled-by-default setting.
