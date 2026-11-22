# Architectural Decision Records — Tamreedy

## ADR-001: Two independent Flutter apps
Patient and nurse have different permissions, UI flows, background location needs and release cadence. Share only `packages/flutter_core`, `flutter_design_system`, `flutter_api`.

## ADR-002: NestJS 12 / Node 26 LTS / TypeScript
Strong typed modules, dependency injection and WebSocket integration. All sensitive decisions on server.

## ADR-003: PostgreSQL 18.7 baseline + PostGIS
PostgreSQL 19 was released 2026-11-19. Postgres 18.7 is chosen as an initial production-tested baseline until PostGIS extension compatibility, backup restore and performance with 19 are validated. PostGIS geography uses SRID 4326; GiST index.

## ADR-004: Atomic accept + partial unique indexes
Always lock request and nurse, validate offer and credentials, write assignment + state changes + outbox in one PostgreSQL transaction. DB constraints enforce one active request assignment and one active nurse assignment.

## ADR-005: Real-time but not source of truth
Socket.IO and FCM are best-effort notification channels; REST reconciliation and database truth survive duplicates, late events and disconnections.

## ADR-006: Wallet as licensed provider integration
No stored-value electronic money issued by Tamreedy. The UI maps to provider-backed balance and signed transactions, and the platform keeps its own immutable accounting ledger separately.

## ADR-007: GPS is ephemeral and access-scoped
Before winning, nurse sees approximate area only. After winning, exact confirmed pin; patient sees nurse route only when authorized and in the appropriate stage. Expire sharing at the end.

## ADR-008: Clinical eligibility is not proximity
Proximity only sorts already verified, legally/clinically eligible nurses. Emergency and medically inappropriate cases do not enter normal dispatch.

## ADR-009: Modular monolith and worker
Simplifies transactions and operations, can later extract services when measurable demand and operational boundaries justify it.
