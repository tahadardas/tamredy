# TAMREEDY HANDOFF — Medical Aero Premium & Core Engineering

**Status:** IN_PROGRESS  
**Branch:** feature/aero-signature  
**Last Commit:** `98760e6` (feat(system): complete dispatch repair, modular worker dispatch, UI enhancements, and push updates)  
**Last Update:** 2026-11-23  
**Current Phase:** Phase 2 — Persistent Authentication  
**Overall Status:** Active Engineering  

---

## 1. PROJECT STATUS
- **Project Name:** Tamreedy (تمريضي) — On-demand home healthcare platform
- **Active Branch:** `feature/aero-signature`
- **Target Apps:**
  - `apps/patient_app` (Flutter)
  - `apps/nurse_app` (Flutter)
  - `packages/flutter_core` (Shared Flutter Design & Auth)
  - `apps/api` (NestJS Authentication & Session Persistence)
- **Last Verified Baseline Build:** PASS (Monorepo test suite green at `98760e6`)

---

## 2. ORIGINAL REQUIREMENTS (Fixed Architectural Decisions)
1. **Medical Aero Premium & Aero Signature:**
   - Light Mode canvas with delicate, clinical frosted glass (`#F5FAFD`, `#DFF4F2`).
   - Primary Navy `#074577`, Accent Teal `#079D90`, Text `#163B52`.
   - Multi-layer diffuse elevation shadows, illuminated borders, 20-26px radii.
   - Flutter implicit motion tokens (springs, page transitions, responsive micro-interactions).
2. **Persistent Trusted Device Authentication (P0):**
   - User signs in once on a trusted device; session survives for months without accidental logout.
   - Server-side device sessions tracking with secure token rotation and replay detection.
   - `AuthGate` refactored into distinct states (`Initializing`, `Authenticated`, `Refreshing`, `OfflineWithSavedSession`, `ReauthenticationRequired`, `SignedOut`, `AccountSuspended`).
   - Temporary network loss or 5xx never wipes local credentials or triggers `logout()`.
3. **Syrian Phone Number Standard (P0):**
   - Fixed visual prefix `+963` in dedicated capsule.
   - User types standard 10-digit local format: `09XXXXXXXX` (e.g. `0987080330`).
   - Unified sanitization and normalization to E.164: `+963987080330` (strips leading 0, adds +963).
   - Backend continues to receive and store canonical E.164 format without database migration conflicts.
4. **Nurse Full-Screen Deep Navy Offer:**
   - Full-screen immersion `#102F49` with teal aura, insistent ringtone, live countdown clamped to `expires_at`, atomic first-accept lock, and one-tap mute.
5. **Floating Aero Dock & Smart CTA:**
   - Shared floating curved dock navigation for both apps.
   - Smart CTA for patient (Option C: Hero button + floating button when hero scrolls out of view).
6. **Zero Breaking Changes:**
   - Preserve existing API contracts, medical pricing, and dispatch mechanics.

---

## 3. COMPLETED WORK
- Initialized dedicated engineering branch `feature/aero-signature`.
- Monorepo baseline verification passed (Node domain tests, Flutter unit tests, dispatch worker tests).
- Established handoff protocol (`HANDOFF.md` + `handoff/checkpoint.json`).

---

## 4. CURRENT TASK
- **Phase 2 — Persistent Authentication:**
  - Inspect backend `apps/api/src/auth/` and database migrations for session tracking.
  - Implement trusted device session policy with refresh token rotation and revocation.
  - Refactor `AuthGate` in `packages/flutter_core/lib/src/login_screen.dart` and `api.dart` to prevent premature logouts on network glitches.

---

## 5. PENDING WORK (Prioritized)
1. **Phase 2:** Persistent Authentication (API session storage + Flutter secure storage + resilient AuthGate + single-flight refresh).
2. **Phase 3:** Syrian Phone Input (`AeroSyrianPhoneField`, normalizer utility, unified across login, register, and nurse application).
3. **Phase 4:** Aero Design System Tokens in `packages/flutter_core/lib/src/design/tokens/`.
4. **Phase 5:** Shared Aero UI Components in `packages/flutter_core/lib/src/design/widgets/` (AeroScaffold, AeroGlassCard, AeroHeroCard, AeroButton, AeroFloatingDock, AeroGlassSheet).
5. **Phase 6:** Patient App Redesign (Home, Hero, Smart CTA, Services, Booking, Live Tracking).
6. **Phase 7:** Nurse App Redesign (Home, Readiness Header, Deep Navy Full-Screen Offer, Visit flow).
7. **Phase 8:** Motion transitions, accessibility (reduced motion), and frame budget optimizations.
8. **Phase 9:** Full QA suite, Flutter analyze, Golden tests, and release APK validation.

---

## 6. MODIFIED FILES
- `HANDOFF.md`: Created master handoff ledger.
- `handoff/checkpoint.json`: Created machine-readable state checkpoint.

---

## 7. TEST RESULTS
- `node --test apps/api/tests/domain.test.mjs`: PASS (5/5)
- `node --test apps/api/tests/dispatch_diagnostics.test.mjs`: PASS (3/3)
- `node --test apps/worker/tests/dispatch.test.mjs`: PASS (1/1)
- `apps/nurse_app test`: PASS (5/5)
- `apps/patient_app test`: PASS (6/6)
- `flutter analyze`: CLEAN (0 issues)

---

## 8. KNOWN ISSUES
- Current `AuthGate` in `login_screen.dart` calls `c.logout()` on any unhandled exception or 401, discarding valid sessions when the server is unreachable or slow.
- Phone fields across auth screens currently require or accept raw text without fixed Syrian +963 formatting.

---

## 9. NEXT MODEL INSTRUCTIONS
If resuming:
1. Run `git status` and verify HEAD matches or succeeds `98760e6` on `feature/aero-signature`.
2. Inspect `HANDOFF.md` and `handoff/checkpoint.json`.
3. Check **CURRENT TASK** section and continue directly without re-analyzing the whole codebase.
4. Maintain `HANDOFF.md` updates after completing each major milestone.

---

## 10. DO NOT REPEAT
- Do NOT re-analyze the dispatch system or GPS filters (already finalized and verified).
- Do NOT create another branch; stay on `feature/aero-signature`.
- Do NOT rewrite backend business logic or databases from scratch.
