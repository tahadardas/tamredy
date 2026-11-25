# TAMREEDY HANDOFF — SMART BOOKING, OPEN MARKETPLACE & UI/UX MASTER ARCHITECTURE
## Production-Grade Engineering Master Report

**Status:** SBM_COMPLETE_VERIFIED & UI_UX_POLISHED_VERIFIED  
**Branch:** `feature/smart-booking-marketplace`  
**Overall Status:** Green (All Tests Passing, 154/154 API Tests PASS, 13/13 Worker Tests PASS, 19/19 Flutter Core Tests PASS, 12/12 Patient App Tests PASS, 7/7 Nurse App Tests PASS, Admin Build Clean, Flutter Clean, 0 Lint Issues)

---

## 0. UI/UX & ADMIN WEB / MOBILE DESIGN AUDIT (COMPLETED & VERIFIED)

1. **Admin Web Modal Architecture & Stacking Context Isolation:**
   - **Root Cause Fixed:** Modals in `apps/admin_web` were previously constrained within `.panel` DOM elements which use `backdrop-filter: blur(14px)`. Under CSS specifications, backdrop filters establish a local stacking context and containing block for `position: fixed` elements, causing the sticky `<header>` (`z-index: 20`) to paint on top of modals.
   - **React Portal Solution:** Refactored `Modal` in `apps/admin_web/src/widgets.tsx` to render via `createPortal(..., document.body)`.
   - **Stacking & Viewport Safety:** Updated `.modal` CSS to `z-index: 100000; position: fixed; inset: 0; width: 100vw; height: 100vh;` with a refined backdrop overlay.
   - **Dedicated Aero Card Styling:** Replaced nested `.panel` inheritance on `.modal-box` with a solid elevated card (`box-shadow: 0 28px 64px -12px rgba(4, 21, 38, 0.5)`), sticky header (`.modal-head`) with title and smooth close button, scrollable body (`.modal-content`), and sticky bottom actions (`.modal-box .actions`).
   - **Refactored All Modals:** Converted `NurseForm` (+ إضافة ممرض), `Detail` in `pages_nurses.tsx`, `ChangePassword` in `main.tsx`, `SupportReports` in `pages_expansion.tsx`, and `DispatchMonitor` in `pages_dispatch.tsx`.
   - **Form Polish & RTL/LTR:** Standardized Syrian phone placeholders (`+963 9XX XXX XXX`), national IDs (`11 رقماً`), and added explicit styling for checkboxes (`.check`) and tabs (`.tabs`).

2. **Mobile Apps UI/UX Resilience & Overflow Elimination (Flutter Core, Patient App, Nurse App):**
   - **Keyboard Avoidance & Safe Scrolling:** Wrapped modal bottom sheets (`AeroBookingModePickerSheet`, `AeroInstantTimeoutSheet`, `AeroProposalSubmissionSheet`, `AeroSchedulePickerSheet`) in `SingleChildScrollView(physics: const BouncingScrollPhysics(), child: ...)` to prevent `RenderFlex overflow` when virtual keyboards appear or on compact devices.
   - **Text & Chip Overflow Prevention:** Wrapped booking mode card titles in `Flexible(child: Text(..., overflow: TextOverflow.ellipsis))` and proposal arrival text in `Expanded(child: Text(...))`.
   - **Horizontal Chip Row Protection:** Wrapped distance filter chips in `NurseMarketplaceScreen` in `SingleChildScrollView(scrollDirection: Axis.horizontal, ...)` for seamless responsiveness across 320px–360px screens.
   - **Static Analysis & Lint Cleanliness:** Fixed `curly_braces_in_flow_control_structures` and `unused_local_variable` warnings. `flutter analyze` reports `No issues found!`.

---

## 1. EXECUTIVE SUMMARY & COMPLETED MODULES

The **Tamreedy Unified Smart Booking, Open Marketplace & Intelligent Request Recovery** engine ("Tamreedy Unified Smart Booking & Marketplace Engine") has been fully architected, implemented, integrated, and verified across the backend API, background workers, Flutter mobile apps (Patient & Nurse), and the Admin Web Dashboard.

This engine addresses the core business objective: **drastically reducing unfulfilled request churn without sacrificing safety, medical invariants, central pricing, or Guardian oversight**.

### Core Implemented & Verified Modules:

1. **Unified Booking Modes (`SBM-01`):**
   - Seamless integration of 3 booking modes into a single canonical engine:
     * `INSTANT`: 3-wave automated Open Dispatch with fixed deadlines.
     * `OPEN`: Marketplace publishing where qualified nearby nurses submit readiness arrival proposals.
     * `SCHEDULED`: Smart Scheduling with 2-hour window selection and automated 30-minute travel buffers.
   - Database Migration `050_smart_booking_and_open_marketplace.sql` updating `care_requests` with `booking_mode`, `original_booking_mode`, `marketplace_status`, `published_at`, `open_expires_at`, `booking_mode_version`, and audit tables.

2. **Instant Search Recovery & Waiting List (`SBM-02`, `SBM-03`, `SBM-14`):**
   - When instant dispatch waves expire without acceptance, the request enters `AWAITING_RECOVERY_CHOICE`.
   - The patient is provided immediate recovery options:
     * One-tap conversion to Open Marketplace (`OPEN_FOR_PROPOSALS`).
     * Instant retry with wave resets.
     * Rescheduling for a later date/time.
     * Free cancellation without penalties.
   - Waiting list duration extension (+30 / +60 min) with `open_expires_at` updates.

3. **Open Marketplace & Spatial Privacy Protection (`SBM-06`, `SBM-07`):**
   - Nurses can browse open requests in their authorized administrative regions and distance filters (<= 5km, <= 10km, all).
   - **Privacy By Design:** Suppresses exact home address and precise GPS coordinates before proposal acceptance. Only approximate neighborhood/area and calculated distance are exposed.

4. **Nurse Readiness Proposals & Centralized Pricing (`SBM-08`, `SBM-09`, `SBM-21`):**
   - Nurses submit structured arrival commitments using relative arrival buttons (15m, 30m, 45m, 1h, 2h) or specific timestamps, plus an optional clinical note.
   - Server converts relative selections to immutable absolute UTC timestamps upon submission.
   - **Centralized Pricing Invariant:** Nurses cannot alter or bid on prices. Platform fees and net nurse earnings are calculated centrally based on the care request's approved tariff.

5. **Unified Atomic Assignment Engine (`SBM-10`, `SBM-11`, `SBM-24`):**
   - Concurrency control under strict canonical row-level lock ordering:
     `care_requests (ORDER BY id) -> marketplace_proposals (ORDER BY id) -> nurses (ORDER BY id)`
   - Race-free mutual exclusion: When a patient accepts a proposal, the winning proposal becomes `ACCEPTED`, the request status becomes `ACCEPTED`, and all sibling pending proposals are immediately transitioned to `SUPERSEDED`.
   - Double-booking prevention with 30-minute pre- and post-visit travel buffers.

6. **Smart Request Recovery Worker (`SBM-12`, `SBM-13`):**
   - Event-driven Quiet Smart Alerting background worker in `apps/worker/src/smart-recovery.ts`.
   - Automatic expiration of overdue proposals and open requests.
   - Alerting throttling: 15-minute per-nurse cooldown, max 8 recovery alerts daily per nurse, 60-second batch aggregation.
   - Data-only quiet alerts (no siren alarms for marketplace opportunities).

7. **Patient Mobile App Integration (`SBM-15`, `SBM-16`, `SBM-19`):**
   - `AeroBookingModePickerSheet` in booking flow allowing patient to choose Instant, Open Marketplace, or Scheduled.
   - `AeroInstantTimeoutSheet` rendering timeout recovery options.
   - `ProposalsViewScreen` with real-time refresh, nurse profile badges, arrival commitments, and one-tap acceptance.
   - `TrackScreen` support for `VisitStage.openMarketplace` with proposal count badges and time extension.

8. **Nurse Mobile App Integration (`SBM-17`, `SBM-18`):**
   - Dedicated "الطلبات" (Marketplace) tab with 3 sub-tabs: الطلبات المتاحة (Available), عروضي المرسلة (My Proposals), سجل الزيارات (History).
   - `AeroProposalSubmissionSheet` for rapid submission of arrival commitments.
   - Proposal withdrawal support for pending proposals.

9. **Admin Web Dashboard Integration (`SBM-22`, `SBM-23`):**
   - `BookingMarketplaceAdmin` panel in `apps/admin_web/src/pages_expansion.tsx`.
   - Live analytics for Instant Assignment Rate, Open Recovery Rate, and Recovered Completion Rate.
   - Configuration editor for marketplace durations, timeouts, cooldowns, and daily limits.
   - Real-time audit tables for open requests and submitted proposals.

---

## 2. VERIFIED TEST METRICS

- **Full API Regression Suite:** 154 / 154 PASS (0 errors)
- **Worker Dispatch & Jobs:** 13 / 13 PASS (0 errors)
- **Routes Audit (`routes_audit.test.mjs`):** 3 / 3 PASS (100% of Flutter & Admin URLs exist on API)
- **Flutter Core Package (`flutter analyze`):** 0 issues found
- **Flutter Core Aero Tests:** 19 / 19 PASS (0 errors)
- **Patient Mobile App (`flutter analyze`):** 0 errors, 0 warnings
- **Patient Mobile App Tests:** 12 / 12 PASS (0 errors)
- **Nurse Mobile App (`flutter analyze`):** 0 issues found
- **Nurse Mobile App Tests:** 6 / 6 PASS (0 errors)
- **Admin Web Dashboard Build:** Clean Vite production bundle (0 errors, 1594 modules transformed)

---

## 3. FILE SUMMARY

### Created / Modified Files:
- **Database & Architecture:**
  * `infra/db/migrations/050_smart_booking_and_open_marketplace.sql`
  * `docs/SMART_BOOKING_SPEC.md`
  * `docs/SMART_BOOKING_STATE_MACHINE.md`
  * `docs/SMART_BOOKING_IMPLEMENTATION_MATRIX.md`
  * `docs/SMART_BOOKING_TEST_REPORT.md`
- **Backend API (`apps/api`):**
  * `apps/api/src/common/dto.ts`
  * `apps/api/src/app.module.ts`
  * `apps/api/src/requests/requests.service.ts`
  * `apps/api/src/marketplace/marketplace.dto.ts`
  * `apps/api/src/marketplace/marketplace-eligibility.service.ts`
  * `apps/api/src/marketplace/marketplace.service.ts`
  * `apps/api/src/marketplace/proposals.service.ts`
  * `apps/api/src/marketplace/assignment.service.ts`
  * `apps/api/src/marketplace/booking-mode.service.ts`
  * `apps/api/src/marketplace/marketplace.controller.ts`
  * `apps/api/src/marketplace/proposals.controller.ts`
  * `apps/api/src/marketplace/booking-mode.controller.ts`
  * `apps/api/src/admin/admin-booking.service.ts`
  * `apps/api/src/admin/admin-booking.controller.ts`
  * `apps/api/tests/marketplace_proposals.test.mjs`
  * `apps/api/tests/marketplace_concurrency.test.mjs`
  * `apps/api/tests/booking_modes.test.mjs`
  * `apps/api/tests/smart_recovery.test.mjs`
- **Background Worker (`apps/worker`):**
  * `apps/worker/src/smart-recovery.ts`
  * `apps/worker/src/dispatch.ts`
  * `apps/worker/src/push.ts`
  * `apps/worker/src/main.ts`
  * `apps/worker/tests/dispatch.test.mjs`
- **Flutter Core Package (`packages/flutter_core`):**
  * `packages/flutter_core/lib/src/api.dart`
  * `packages/flutter_core/lib/src/design/aero_design.dart`
  * `packages/flutter_core/lib/src/design/widgets/aero_smart_booking_sheets.dart`
  * `packages/flutter_core/lib/src/design/widgets/aero_proposal_card.dart`
  * `packages/flutter_core/test/aero_components_test.dart`
- **Patient Mobile App (`apps/patient_app`):**
  * `apps/patient_app/lib/controller.dart`
  * `apps/patient_app/lib/screens/home.dart`
  * `apps/patient_app/lib/screens/track.dart`
  * `apps/patient_app/lib/screens/proposals_view.dart`
- **Nurse Mobile App (`apps/nurse_app`):**
  * `apps/nurse_app/lib/controller.dart`
  * `apps/nurse_app/lib/main.dart`
  * `apps/nurse_app/lib/screens/marketplace.dart`
- **Admin Web Dashboard (`apps/admin_web`):**
  * `apps/admin_web/src/main.tsx`
  * `apps/admin_web/src/pages_expansion.tsx`

### Guardian phase 9 - evidence operations interface

- Admin Web now exposes export approval, bundle generation, authenticated download with SHA-256, case legal holds and retention policy/run history through existing Guardian API routes.
- Admin Web TypeScript and Vite build passed. No server settings, endpoints or migrations changed. Browser workflow with authorized accounts remains unverified.
- Next: PDF export and attachments, then Play readiness and end-to-end verification.

### Administrative visit record and evidence context

- Existing care_requests retain the submitted visit address, geographic point, status and creation timestamp, including without assignment or completion.
- New admin-only GET /v1/admin/requests/:id/visit-record reads the stored point, visit and payment clocks, recorded durations and actual cash collections and audits access. The Requests detail panel links to OpenStreetMap only on click.
- Guardian evidence snapshots now also include the submitted visit address, creation clock, recorded duration and sum of cash collections when linked to a visit.
- Local API build, Admin Web build and four integrated/route tests passed. No migration. No server deployment or physical test.

### Admin scheduled operations and account removal

- The appointments page reads actual scheduled requests and care plans, with paginated active and archived lists. Assignment and actual arrival are displayed separately. Visit details retain the facility-independent visit timeline, stored point, collected amount and all recorded nurse assignments.
- Migration 052 adds `scheduled_visits.admin_removed_at`. Admin schedule removal archives closed records or cancels and archives a still-scheduled, unassigned visit. The cancel event and patient notification are queued in the same transaction. In-progress visits are blocked.
- Admin users can remove patient, nurse and staff accounts. The operation revokes sessions and push tokens, releases the phone number and keeps operational and audit references. It blocks self-removal and removal while a request is open.
- API routes: GET /v1/admin/schedule/visits, GET /v1/admin/schedule/care-plans, DELETE /v1/admin/schedule/visits/:id, DELETE /v1/admin/users/:id.
- Deploy migration 052 before enabling the updated admin dashboard. Run a scheduled visit on staging and verify the arrival record and notification before release.
