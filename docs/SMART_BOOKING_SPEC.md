# TAMREEDY SMART BOOKING & OPEN MARKETPLACE SPECIFICATION
## Unified Assignment, Open Marketplace & Intelligent Request Recovery

---

## 1. Executive Summary & Purpose

The **Tamreedy Smart Booking & Open Marketplace Engine** unifies all patient-to-nurse matching channels into a single, cohesive, high-performance architectural foundation. It eliminates lost demand from instant dispatch search timeouts by converting unfulfilled requests into an active, transparent marketplace where qualified nurses submit structured **Readiness Proposals**, and patients confirm their preferred provider based on verified credentials and precise arrival times.

### Three Unified Booking Modes:
1. **INSTANT (الحجز الفوري):** On-demand care request dispatched to all qualified nurses within geographic scope under Open Dispatch and First Successful Acceptance. If search timeout occurs without acceptance, the request seamlessly transitions to `AWAITING_RECOVERY_CHOICE`.
2. **OPEN (الطلب المفتوح):** Broadcast to qualified nurses in authorized service regions. Qualified nurses can browse and submit structured Readiness Proposals with specific arrival commitments. Patient chooses and atomically assigns the ideal proposal.
3. **SCHEDULED (الحجز المجدول):** Scheduled care with specific date and time window, subject to Damascus local calendar rules (UTC+3) and automated 30-minute travel buffer conflict prevention.

---

## 2. Core Architecture & Unified Engines

The architecture strictly rejects maintaining three divergent backend dispatchers. All three modes share the single unified set of domain engines:

```
┌────────────────────────────────────────────────────────┐
│             PATIENT OR NURSE CLIENT APPS               │
└──────────────────────────┬─────────────────────────────┘
                           │ HTTP / Socket.IO
┌──────────────────────────▼─────────────────────────────┐
│           TAMREEDY UNIFIED BOOKING GATEWAY             │
│   (Instant Search | Open Marketplace | Smart Schedule) │
└──────────────────────────┬─────────────────────────────┘
                           │
       ┌───────────────────┼───────────────────┐
       ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  ELIGIBILITY │   │   PRICING    │   │  ASSIGNMENT  │
│    ENGINE    │   │    ENGINE    │   │    ENGINE    │
│ (3-Tiered)   │   │ (Single Fee) │   │ (Atomic Lock)│
└──────────────┘   └──────────────┘   └──────────────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│              SHARED FOUNDATIONAL SERVICES              │
│  - Guardian Safety System                              │
│  - Double-Entry Financial Ledger                       │
│  - Medical Records & Clinical Notes                    │
│  - Durable Outbox & Quiet Smart Recovery Alerts        │
└────────────────────────────────────────────────────────┘
```

### Shared Engine Invariants:
1. **Unified Eligibility Engine:**
   - **Browse Eligibility:** Validates account approval, active professional license, verified clinical skill sets for all request services, authorized operational regions, active absence of mutual blocks. Does not require instant readiness or close GPS to browse.
   - **Proposal Eligibility:** Validates proposed arrival window against patient's `latest_acceptable_arrival_at`, nurse calendar conflicts, working shifts, night safety policy, and debt settlement caps.
   - **Assignment Eligibility:** Re-validated atomically under PostgreSQL row-level locks upon patient acceptance.
2. **Unified Pricing Engine:**
   - Strict single travel fee guarantee across multi-service bundled items.
   - Centralized price calculation: No nurse price bidding or auctioning.
   - Clear earnings transparency: Net nurse share, platform commission, and fee breakdown calculated accurately in integer Syrian Pounds (`SYP_NEW`).
3. **Unified Atomic Assignment Engine:**
   - Row-level locking (`SELECT ... FOR UPDATE`) across `care_requests`, `marketplace_proposals`, and `nurses`.
   - Prevents double-booking across concurrent proposal acceptances, simultaneous instant dispatch claims, and race conditions with cancellations or withdrawals.
4. **Guardian Safety Engine:**
   - Night safety restrictions, emergency SOS, trusted contacts notifications, and real-time check-ins apply uniformly once assigned.
5. **Privacy Shield:**
   - Exact patient coordinates and street address remain hidden from nurses during browsing and proposal submission. Only broad region and approximate distance are surfaced. Exact address is revealed exclusively upon confirmed assignment.

---

## 3. Database Schema Design (Migration 050)

### 3.1 Extensions to `care_requests`
- `booking_mode`: text NOT NULL DEFAULT 'INSTANT' CHECK (booking_mode IN ('INSTANT', 'OPEN', 'SCHEDULED'))
- `original_booking_mode`: text NOT NULL DEFAULT 'INSTANT'
- `marketplace_status`: text NOT NULL DEFAULT 'INITIAL' CHECK (marketplace_status IN ('INITIAL', 'SEARCHING', 'AWAITING_RECOVERY_CHOICE', 'OPEN_FOR_PROPOSALS', 'ASSIGNED', 'EXPIRED', 'CANCELLED'))
- `published_at`: timestamptz
- `open_expires_at`: timestamptz
- `latest_acceptable_arrival_at`: timestamptz
- `scheduled_start_at`: timestamptz
- `scheduled_end_at`: timestamptz
- `booking_mode_version`: integer NOT NULL DEFAULT 1
- `last_mode_change_at`: timestamptz

### 3.2 Table `marketplace_proposals`
Tracks nurse readiness proposals submitted for open requests:
- `id`: uuid PRIMARY KEY DEFAULT gen_random_uuid()
- `request_id`: uuid NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE
- `nurse_id`: uuid NOT NULL REFERENCES nurses(id) ON DELETE CASCADE
- `status`: text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'DECLINED', 'WITHDRAWN', 'EXPIRED', 'SUPERSEDED', 'INVALIDATED'))
- `proposed_arrival_at`: timestamptz NOT NULL
- `estimated_service_minutes`: integer NOT NULL
- `estimated_nurse_earning`: numeric(18,2) NOT NULL
- `note`: text
- `pricing_version`: integer NOT NULL DEFAULT 1
- `request_version`: integer NOT NULL DEFAULT 1
- `proposal_version`: integer NOT NULL DEFAULT 1
- `expires_at`: timestamptz NOT NULL
- `created_at`: timestamptz NOT NULL DEFAULT now()
- `updated_at`: timestamptz NOT NULL DEFAULT now()
- `accepted_at`: timestamptz
- `withdrawn_at`: timestamptz
- `invalidated_at`: timestamptz
- `invalidation_reason`: text
- Unique index: Exactly ONE active (`PENDING`) proposal per nurse per request.

### 3.3 Table `request_booking_transitions`
Immutable audit log of all transitions between booking modes:
- `id`: uuid PRIMARY KEY DEFAULT gen_random_uuid()
- `request_id`: uuid NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE
- `from_mode`: text NOT NULL
- `to_mode`: text NOT NULL
- `triggered_by_user_id`: uuid NOT NULL REFERENCES users(id)
- `transition_reason`: text NOT NULL
- `transition_metadata`: jsonb NOT NULL DEFAULT '{}'::jsonb
- `created_at`: timestamptz NOT NULL DEFAULT now()

### 3.4 Table `smart_recovery_deliveries`
Tracks quiet recovery alerts to enforce cooldowns and avoid nurse spamming:
- `id`: uuid PRIMARY KEY DEFAULT gen_random_uuid()
- `nurse_id`: uuid NOT NULL REFERENCES nurses(id) ON DELETE CASCADE
- `request_ids`: uuid[] NOT NULL
- `delivery_channel`: text NOT NULL DEFAULT 'PUSH_SILENT'
- `delivered_at`: timestamptz NOT NULL DEFAULT now()
- `cooldown_until`: timestamptz NOT NULL

---

## 4. Smart Recovery Alerting (Option B: Quiet Smart Alerting)

### Principles:
1. **Never use loud instant alarm:** Recovery notifications use standard system notifications ("توجد 4 طلبات مناسبة لك"), never full-screen intent or sirens.
2. **Never auto-assign:** Notification invites the nurse to view the Open Requests tab. No automatic assignment occurs.
3. **Throttled & Cooled Down:**
   - `notification_cooldown_minutes = 15`
   - `max_daily_notifications = 8`
   - `aggregation_window_seconds = 60`
4. **Event Triggers:**
   - Nurse finishes active visit (`nurse.visit.completed`).
   - Nurse toggles availability to ready (`nurse.availability.changed`).
   - New open request published matching nurse skills and regions (`marketplace.request.published`).
   - Nurse shifts or operational region updated (`nurse.work_location.updated`).

---

## 5. Security & Privacy Protection
- Strict authorization checks verifying patient ownership on accept/decline/extend/cancel.
- Nurses can only view approximate regional location (e.g. "المزة - دمشق") and approximate distance before assignment.
- Patient full name, phone number, and exact coordinates are guarded until proposal acceptance.
- Sanitized notes: Contact exchange advisory warns users if external communication or payments are mentioned.
