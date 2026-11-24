# Tamreedy Competitive Expansion Matrix
## Connect + Health Record + Smart Scheduling + Financial Management

**Branch:** `feature/competitive-expansion`  
**Baseline Commit:** `a38dfe7 feat(guardian): add restricted safety evidence bundle exports`  
**Statuses:** `NOT_STARTED` | `IN_PROGRESS` | `IMPLEMENTED` | `VERIFIED` | `BLOCKED`

---

| Requirement ID | Module / Feature | Priority | Dependencies | Implementation Status | Files / Components | Database Migration | Test Evidence | Remaining Issues |
|---|---|---|---|---|---|---|---|---|
| **EXP-01** | Security & Verification Provider Architecture | P0 | Auth Module | IN_PROGRESS | `apps/api/src/auth/verification-provider.ts`, `auth.service.ts` | 042_competitive_expansion_foundation.sql | Unit & integration tests | Production WhatsApp/SMS credentials pending |
| **EXP-02** | Advanced Medical Catalog & Categories | P0 | Catalog Module | NOT_STARTED | `apps/api/src/catalog/*`, `packages/flutter_core/lib/src/catalog/*` | 042_competitive_expansion_foundation.sql | Catalog service tests | None |
| **EXP-03** | Multi-Service Selection & Single Visit Items (`care_request_items`) | P0 | Requests, Catalog, Dispatch | NOT_STARTED | `apps/api/src/requests/*`, `apps/patient_app/lib/screens/booking.dart` | 042_competitive_expansion_foundation.sql | Booking multi-service test | None |
| **EXP-04** | Medical Pricing Engine & Syrian Currency Alignment | P0 | Pricing Module | NOT_STARTED | `apps/api/src/pricing/*` | 042_competitive_expansion_foundation.sql | Pricing regression test | Exact numeric(18,2) preserved |
| **EXP-05** | Tamreedy Connect (In-App Chat & Attachments) | P0 | Realtime, Sockets, Requests | NOT_STARTED | `apps/api/src/chat/*`, `packages/flutter_core/lib/src/chat/*` | 043_tamreedy_connect_and_trust.sql | Chat lifecycle & receipt tests | Secure offline queue |
| **EXP-06** | Contact Masking & Phone Exchange Advisory | P1 | Chat Module | NOT_STARTED | `apps/api/src/chat/phone-shield.ts` | 043_tamreedy_connect_and_trust.sql | Shield unit tests | Non-destructive alert only |
| **EXP-07** | Tamreedy Trust & Mutual Blocking | P0 | Dispatch, Requests | NOT_STARTED | `apps/api/src/trust/*`, `apps/api/src/dispatch/*` | 043_tamreedy_connect_and_trust.sql | Block exclusion test | None |
| **EXP-08** | Unified Reports & Support Center (Incident Separation) | P1 | Trust, Guardian | NOT_STARTED | `apps/api/src/trust/reports.controller.ts` | 043_tamreedy_connect_and_trust.sql | Report triage test | Safety case integration |
| **EXP-09** | Tamreedy Smart Scheduling (Scheduled Visits) | P0 | Requests, Worker | NOT_STARTED | `apps/api/src/scheduling/*`, `apps/worker/src/scheduling.ts` | 044_smart_scheduling_and_recurring.sql | Scheduling worker tests | Worker cron recovery |
| **EXP-10** | Nurse Calendar & Schedule Overlap Prevention | P0 | Scheduling, Nurses | NOT_STARTED | `apps/api/src/scheduling/calendar.service.ts`, `apps/nurse_app/lib/screens/calendar.dart` | 044_smart_scheduling_and_recurring.sql | Concurrency overlap test | Database transaction lock |
| **EXP-11** | Tamreedy Recurring Care (Care Plans) | P1 | Scheduling, Requests | NOT_STARTED | `apps/api/src/care-plans/*`, `apps/patient_app/lib/screens/care_plans.dart` | 044_smart_scheduling_and_recurring.sql | Care plan generation test | Rolling horizon |
| **EXP-12** | Tamreedy Health Record & Beneficiary Profiles | P0 | Requests, Health Records | NOT_STARTED | `apps/api/src/health-records/*`, `apps/patient_app/lib/screens/health_record.dart` | 045_health_records_and_clinical_observations.sql | Access audit & profile test | Strict RBAC |
| **EXP-13** | Clinical Observations Engine (Vitals, Glycemia, O2, Pain) | P0 | Health Records | NOT_STARTED | `apps/api/src/health-records/observations.service.ts` | 045_health_records_and_clinical_observations.sql | Observation validation test | No auto-diagnosis |
| **EXP-14** | Fast Clinical Notes & Visit Observation Entry (Nurse App) | P0 | Health Records, Nurse App | NOT_STARTED | `apps/nurse_app/lib/screens/clinical_notes.dart` | 045_health_records_and_clinical_observations.sql | Nurse observation flow test | Offline draft |
| **EXP-15** | Clinical Reports & Arabic RTL PDF Generation with QR | P1 | Health Records, Admin | NOT_STARTED | `apps/api/src/clinical-reports/*` | 045_health_records_and_clinical_observations.sql | PDF builder test | 24h amendment window |
| **EXP-16** | Customer Retention (Rebook Service & Favorite Nurses) | P1 | Requests, Nurses | NOT_STARTED | `apps/api/src/nurses/favorites.controller.ts`, `apps/patient_app/lib/screens/favorite_nurses.dart` | 046_retention_and_financial_expansion.sql | Dedicated offer test | Fallback to open dispatch |
| **EXP-17** | Tamreedy Financial Control (Double-Entry Ledger & Multi-Model) | P0 | Wallet, Pricing, Settlements | NOT_STARTED | `apps/api/src/wallet/ledger.service.ts`, `apps/api/src/wallet/financial-account.service.ts` | 046_retention_and_financial_expansion.sql | Balanced ledger & reservation test | Physical cashout disabled |
| **EXP-18** | Packages, Bundles & Loyalty Discounts | P1 | Marketing, Wallet | NOT_STARTED | `apps/api/src/marketing/packages.service.ts` | 046_retention_and_financial_expansion.sql | Package redemption test | Prevent double redemption |
| **EXP-19** | Multi-Factor Rating System & Quality Reviews | P1 | Reviews Module | NOT_STARTED | `apps/api/src/reviews/*` | 046_retention_and_financial_expansion.sql | Review aggregation test | Bayesian average |
| **EXP-20** | Tamreedy Voice (In-App Calling Signaling Architecture) | P1 | Realtime, Sockets | NOT_STARTED | `apps/api/src/voice/*`, `packages/flutter_core/lib/src/voice/*` | 047_tamreedy_voice_signaling.sql | Signaling session test | WebRTC ICE/TURN config |
| **EXP-21** | Unified In-App Notifications Center | P1 | Common, Realtime, FCM | NOT_STARTED | `apps/api/src/notifications/*`, `packages/flutter_core/lib/src/notifications/*` | 048_notifications_center.sql | Delivery & read-all test | Secure payload scrubbing |
| **EXP-22** | Admin Web Expansion & Business Intelligence Telemetry | P1 | Admin Web | NOT_STARTED | `apps/admin_web/src/pages_*` | None | Web build | None |
| **EXP-23** | Mobile UI Integration & Aero Visual Polish | P0 | Patient App, Nurse App | NOT_STARTED | `apps/patient_app/*`, `apps/nurse_app/*` | None | Flutter widget tests | Zero pixel overflow |
| **EXP-24** | Comprehensive Verification & Concurrency Tests | P0 | Monorepo | NOT_STARTED | `apps/api/tests/*` | All | Full test suite green | Real PostGIS in staging |
