# TAMREEDY SMART BOOKING & MARKETPLACE STATE MACHINE
## Lifecycle Invariants, Legal Transitions, and Concurrency Controls

---

## 1. Domain State Machines Overview

The platform explicitly decouples three orthogonal lifecycle dimensions:
1. **Search & Marketplace Lifecycle (`marketplace_status` & `booking_mode`):** How a provider is located.
2. **Visit Execution Lifecycle (`status`):** How care is delivered once assigned.
3. **Readiness Proposal Lifecycle (`proposal.status`):** How an individual nurse's readiness offer evolves.

---

## 2. Request Booking & Search State Machine

```
                        ┌───────────────────┐
                        │       DRAFT       │
                        └─────────┬─────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │ (Mode=INSTANT)        │ (Mode=OPEN)           │ (Mode=SCHEDULED)
          ▼                       ▼                       ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│ INSTANT_SEARCHING │   │OPEN_FOR_PROPOSALS │   │ SCHEDULED_PENDING │
└─────────┬─────────┘   └─────────┬─────────┘   └─────────┬─────────┘
          │                       │                       │
     Timeout/No Nurse             │                       │ Release Horizon
          ▼                       │                       ▼
┌───────────────────┐             │             ┌───────────────────┐
│AWAITING_RECOVERY_ │             │             │SCHEDULED_SEARCHING│
│      CHOICE       │             │             └─────────┬─────────┘
└─────────┬─────────┘             │                       │
          │                       │                       │
     ┌────┴──────────────┐        │                       │
     │ Keep Open (OPEN)  │        │                       │
     │ Retry Instant     │        │                       │
     │ Reschedule        │        │                       │
     ▼                   ▼        │                       ▼
┌─────────────────────────────────┼───────────────────────────────┐
│                                 ▼                               │
│                         Proposal Accepted                       │
│                       or Instant Acceptance                     │
│                                 ▼                               │
│                             ASSIGNED                            │
└─────────────────────────────────────────────────────────────────┘
                                  │
                       Visit Execution Lifecycle
                                  │
                                  ▼
                             (COMPLETED)
```

### Legal Transitions Matrix:

| From State | Event / Trigger | Target State | Pre-conditions & Guards |
|---|---|---|---|
| `DRAFT` | `submit(INSTANT)` | `INSTANT_SEARCHING` | Active beneficiary consent, verified approved service, positive pricing snapshot, valid location. |
| `DRAFT` | `submit(OPEN)` | `OPEN_FOR_PROPOSALS` | Patient specifies `latest_acceptable_arrival_at` or wait window, service is open-eligible. |
| `DRAFT` | `submit(SCHEDULED)` | `SCHEDULED_PENDING` | Valid appointment window (UTC+3), safety check passes. |
| `INSTANT_SEARCHING` | Instant Acceptance | `ASSIGNED` | Nurse is available, qualified, non-blocked, atomic winner of offer. |
| `INSTANT_SEARCHING` | Search Timeout (Waves Exhausted) | `AWAITING_RECOVERY_CHOICE` | Search deadline passed, zero acceptances recorded. Closes instant offers. |
| `AWAITING_RECOVERY_CHOICE` | Choose Keep Open | `OPEN_FOR_PROPOSALS` | Patient confirms wait window. Mode transitions to `OPEN`. Emits `marketplace.request.published`. |
| `AWAITING_RECOVERY_CHOICE` | Choose Retry Instant | `INSTANT_SEARCHING` | Creates new dispatch round, resets search expiration. |
| `AWAITING_RECOVERY_CHOICE` | Choose Reschedule | `SCHEDULED_PENDING` | Valid future appointment window selected. |
| `AWAITING_RECOVERY_CHOICE` | Choose Cancel | `CANCELLED` | Free cancellation, no nurse assigned. |
| `OPEN_FOR_PROPOSALS` | Accept Proposal | `ASSIGNED` | Proposal active (`PENDING`), nurse qualified, no temporal conflict, no mutual block. |
| `OPEN_FOR_PROPOSALS` | Open Window Expired | `EXPIRED` | `open_expires_at <= now()`. Closes all pending proposals as `EXPIRED`. |
| `OPEN_FOR_PROPOSALS` | Patient Extends Window | `OPEN_FOR_PROPOSALS` | Valid new expiration within maximum service cap, service pricing re-validated. |
| `OPEN_FOR_PROPOSALS` | Patient Cancels | `CANCELLED` | Free cancellation before assignment. Closes all active proposals as `INVALIDATED`. |
| `SCHEDULED_PENDING` | Dispatch Release Horizon | `SCHEDULED_SEARCHING` | Release timer reaches horizon (`release_at`). Initiates dispatch. |
| `SCHEDULED_SEARCHING` | Nurse Accepts Offer | `ASSIGNED` | Assigned for scheduled appointment. |

---

## 3. Nurse Readiness Proposal State Machine

```
                      ┌───────────────────┐
                      │    (New Pitch)    │
                      └─────────┬─────────┘
                                │ Nurse submits proposal
                                ▼
                      ┌───────────────────┐
       ┌──────────────┤      PENDING      ├──────────────┐
       │              └─────────┬─────────┘              │
       │                        │                        │
       │ Patient Accepts        │ Nurse Withdraws        │ Request Cancelled
       ▼                        ▼                        ▼
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   ACCEPTED   │         │  WITHDRAWN   │         │ INVALIDATED  │
└──────────────┘         └──────────────┘         └──────────────┘
                                │                        ▲
                                │ Timeout                │ Another Accepted
                                ▼                        │ or Nurse Busy
                         ┌──────────────┐                │
                         │   EXPIRED    │────────────────┘
                         └──────────────┘
```

### Legal Proposal Transitions:
1. `PENDING` -> `ACCEPTED`:
   - Triggered exclusively by patient calling `POST /v1/requests/:id/proposals/:proposalId/accept`.
   - Atomically locks request row, proposal row, and nurse row.
   - Transitions winning proposal to `ACCEPTED`.
   - Transitions all sibling pending proposals for this request to `SUPERSEDED`.
   - Transitions any competing pending proposals by this nurse for overlapping time windows to `INVALIDATED` (reason: `NURSE_COMMITTED_ELSEWHERE`).
2. `PENDING` -> `WITHDRAWN`:
   - Nurse withdraws before acceptance.
   - Immediate release with no negative penalty.
3. `PENDING` -> `EXPIRED`:
   - `proposal.expires_at <= now()` or `request.open_expires_at <= now()`.
4. `PENDING` -> `INVALIDATED`:
   - Triggered when:
     * Request is cancelled by patient (`REQUEST_CANCELLED`).
     * Nurse accepts another assignment with overlapping schedule (`SCHEDULE_CONFLICT`).
     * Mutual block is created (`USER_BLOCKED`).
     * Nurse license or credential revoked (`CREDENTIAL_REVOKED`).

---

## 4. Concurrency Protection & Deadlock Prevention

### Strict Lock Ordering Hierarchy:
To prevent deadlocks during high-concurrency races, all database transactions MUST acquire locks in strict canonical order:
1. `care_requests` row (`SELECT ... FOR UPDATE` by `id`)
2. `marketplace_proposals` row (`SELECT ... FOR UPDATE` by `id`)
3. `nurses` row (`SELECT ... FOR UPDATE` by `id`)
4. Financial account / ledger rows

### Idempotency Invariants:
- Every state transition requires passing the entity's current `version`.
- Updates increment `version = version + 1`.
- If another process modified the row, a `409 Conflict` (`PROPOSAL_VERSION_CONFLICT` or `REQUEST_VERSION_CONFLICT`) is thrown.
