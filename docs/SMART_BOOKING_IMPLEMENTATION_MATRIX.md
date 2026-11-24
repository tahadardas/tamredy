# TAMREEDY SMART BOOKING & OPEN MARKETPLACE IMPLEMENTATION MATRIX

| Req ID | Description | Priority | Dependencies | Implementation Status | Files Affected | Migration | Test Evidence | Remaining Issues |
|---|---|---|---|---|---|---|---|---|
| **SBM-01** | Unified Booking Modes (`INSTANT`, `OPEN`, `SCHEDULED`) & Request Schema | P0 | Core DB | VERIFIED | `apps/api/src/requests/`, `infra/db/migrations/050*` | `050_smart_booking_and_open_marketplace.sql` | `booking_modes.test.mjs`, `routes_audit.test.mjs` | None |
| **SBM-02** | Instant Search Recovery State (`AWAITING_RECOVERY_CHOICE`) | P0 | SBM-01 | VERIFIED | `apps/worker/src/dispatch.ts`, `apps/api/src/requests/` | 050 | `apps/worker/tests/dispatch.test.mjs` | None |
| **SBM-03** | Atomic Mode Conversion (Instant -> Open Marketplace) | P0 | SBM-01, SBM-02 | VERIFIED | `apps/api/src/marketplace/booking-mode.service.ts` | 050 | `apps/api/tests/booking_modes.test.mjs` | None |
| **SBM-04** | Direct Open Request Publishing | P0 | SBM-01 | VERIFIED | `apps/api/src/requests/requests.service.ts` | 050 | `apps/api/tests/booking_modes.test.mjs` | None |
| **SBM-05** | Three-Tiered Eligibility Engine (Browse, Proposal, Assignment) | P0 | SBM-01 | VERIFIED | `apps/api/src/marketplace/marketplace-eligibility.service.ts` | 050 | `apps/api/tests/marketplace_concurrency.test.mjs` | None |
| **SBM-06** | Open Marketplace Browse & Filter API for Nurses | P0 | SBM-05 | VERIFIED | `apps/api/src/marketplace/marketplace.controller.ts` | 050 | `apps/api/tests/routes_audit.test.mjs` | None |
| **SBM-07** | Approximate Regional Map & Spatial Privacy Protection | P0 | SBM-06 | VERIFIED | `apps/api/src/marketplace/marketplace.service.ts`, `apps/nurse_app/` | 050 | `apps/api/tests/booking_modes.test.mjs` | None |
| **SBM-08** | Nurse Readiness Proposal Submission & Validation Engine | P0 | SBM-01, SBM-05 | VERIFIED | `apps/api/src/marketplace/proposals.service.ts` | 050 | `apps/api/tests/marketplace_proposals.test.mjs` | None |
| **SBM-09** | Patient Proposal Review & Multi-Proposal Inbox | P0 | SBM-08 | VERIFIED | `apps/api/src/marketplace/proposals.controller.ts` | 050 | `apps/api/tests/marketplace_proposals.test.mjs` | None |
| **SBM-10** | Unified Atomic Assignment & Race-Free Proposal Acceptance | P0 | SBM-08, SBM-09 | VERIFIED | `apps/api/src/marketplace/assignment.service.ts` | 050 | `apps/api/tests/marketplace_concurrency.test.mjs` | None |
| **SBM-11** | Proposal Invalidation Engine (Schedule Conflicts, Mutual Blocks) | P0 | SBM-10 | VERIFIED | `apps/api/src/marketplace/proposals.service.ts` | 050 | `apps/api/tests/marketplace_concurrency.test.mjs` | None |
| **SBM-12** | Smart Request Recovery (Option B: Quiet Smart Alerting Worker) | P0 | SBM-01, SBM-06 | VERIFIED | `apps/worker/src/smart-recovery.ts` | 050 | `apps/api/tests/smart_recovery.test.mjs` | None |
| **SBM-13** | Notification Throttling, Cooldown & Quiet Hours | P1 | SBM-12 | VERIFIED | `apps/worker/src/smart-recovery.ts`, `apps/api/src/notifications/` | 050 | `apps/api/tests/smart_recovery.test.mjs` | None |
| **SBM-14** | Patient Smart Waiting List & Waiting Duration Extensions | P1 | SBM-03, SBM-04 | VERIFIED | `apps/api/src/marketplace/booking-mode.service.ts`, `apps/patient_app/` | 050 | `apps/api/tests/booking_modes.test.mjs` | None |
| **SBM-15** | Patient Booking Mode Selection UI (Aero Bottom Sheet) | P0 | SBM-01 | VERIFIED | `packages/flutter_core/`, `apps/patient_app/lib/screens/home.dart` | - | `packages/flutter_core/test/aero_components_test.dart` | None |
| **SBM-16** | Patient Instant Search Timeout Sheet ("لم نجد ممرضاً متاحاً") | P0 | SBM-02 | VERIFIED | `packages/flutter_core/`, `apps/patient_app/lib/screens/track.dart` | - | `packages/flutter_core/test/aero_components_test.dart` | None |
| **SBM-17** | Nurse Marketplace Tab & Aero Proposal Cards | P0 | SBM-06, SBM-08 | VERIFIED | `apps/nurse_app/lib/screens/marketplace.dart` | - | `apps/nurse_app/test/flow_test.dart`, `flutter analyze` | None |
| **SBM-18** | Nurse Readiness Proposal Submission Sheet with Absolute Times | P0 | SBM-08 | VERIFIED | `packages/flutter_core/`, `apps/nurse_app/lib/screens/marketplace.dart` | - | `packages/flutter_core/test/aero_components_test.dart` | None |
| **SBM-19** | Patient Proposal Confirmation & Visit Handoff | P0 | SBM-10 | VERIFIED | `apps/patient_app/lib/screens/proposals_view.dart`, `track.dart` | - | `apps/patient_app/test/flow_test.dart` | None |
| **SBM-20** | Guardian Safety & Mutual Block Strict Integration | P0 | SBM-05, SBM-10 | VERIFIED | `apps/api/src/marketplace/marketplace-eligibility.service.ts` | 050 | `apps/api/tests/connect_and_trust.test.mjs` | None |
| **SBM-21** | Financial Engine & Single Fee Guarantee Integration | P0 | SBM-01, SBM-10 | VERIFIED | `apps/api/src/marketplace/assignment.service.ts` | 050 | `apps/api/tests/marketplace_proposals.test.mjs` | None |
| **SBM-22** | Admin Booking Policies & Marketplace Configuration | P1 | SBM-01 | VERIFIED | `apps/api/src/admin/`, `apps/admin_web/src/pages_expansion.tsx` | 050 | `apps/admin_web` build, `routes_audit.test.mjs` | None |
| **SBM-23** | Admin Booking Analytics & Recovery Rates Telemetry | P1 | SBM-10, SBM-12 | VERIFIED | `apps/api/src/admin/`, `apps/admin_web/src/pages_expansion.tsx` | 050 | `apps/admin_web` build, `routes_audit.test.mjs` | None |
| **SBM-24** | High-Concurrency & Stress Test Verification (Canonical Locks) | P0 | All | VERIFIED | `apps/api/tests/marketplace_concurrency.test.mjs` | 050 | `apps/api/tests/marketplace_concurrency.test.mjs` | None |
