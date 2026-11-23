# Migration 021 · Open dispatch and cancellation foundation

## Preflight

- Verify migrations through 020 are applied and the database backup can be restored.
- Check that the target has the existing request/nurse active assignment unique indexes and PostGIS geography indexes. Run a staging migration before approving a deployment.
- Schedule the migration in a quiet window. ALTER TABLE takes exclusive locks, and the new assignment constraint and partial search index build inside the migration transaction.

## Compatibility

The migration adds nullable metadata and empty tables. Old requests, waves, assignments, and billing remain usable. No historic cancellation, departure time, or ETA is synthesized. Producers must populate the complete search and ETA tuples when they opt into the new policy.

## Verify

Check the migration name in `schema_migrations`, the four cancellation/appeal tables, and `idx_open_dispatch_deadline`. Run `pnpm exec node --test apps/api/tests/open_dispatch_foundation.test.mjs`. Before deploying the worker, capture query plans with representative PostGIS data and run the multi-connection suite on a disposable database.

## Roll forward

Keep the new columns and evidence tables during any application rollback. Keep the open-dispatch flag disabled for new requests while diagnosing issues. If it has ever been enabled, drain the already-open searches on the compatible worker before reverting the worker. Do not delete cancellation or appeal evidence.


## Migration 022 · Open-dispatch eligibility wake-ups

Preflight on a restored staging database with 021, PostGIS, and migration 007 installed. Keep the API’s OPEN_DISPATCH_ENABLED environment flag off during migration. New requests use the new policy only when that flag and the admin dispatch.openEnabled setting are both true. Review operational timings before enabling either on production. Existing searches have no snapshot and keep the old wave policy. No historic rows are updated. Migration 022 adds three nullable thresholds and checks only initialized searches, plus triggers on availability, locations, skills, credentials and settlements. The trigger reuses the existing dispatch-job row. It skips locked jobs, which the five-second reconciliation picks up. Check the 021 partial deadline index and existing request and nurse geography indexes with representative data before rollout. Roll back operationally by disabling open dispatch for new requests and allowing existing searches to drain with the compatible worker. Do not revert the database by removing evidence columns or tables.


## Migration 023 · Outbox delivery leases

Verify migration 018 exists and historical delivery rows have not been deleted. Back up the target before running the migration during a quiet deployment window. Both ALTER TABLEs take exclusive locks; the new fields are nullable with no backfill. For rollout, stop the old worker before starting the lease-aware worker. Verify lease expiry recovery and independent realtime/push claims with the outbox test. Rows with an active lease remain pending for up to three minutes. Preserve the columns during app rollback; let claims drain or expire before starting a previous worker. External delivery is at least once when a worker dies after the provider accepted a message but before the ledger has recorded it.


## Migration 024 · Delayed departure reminders

The new deadline and reminder timestamp are nullable. There is no backfill or automatic penalty. Review ALTER TABLE lock time on staging, and verify the partial reminder index. The dispatch admin settings control the deadline for newly accepted assignments, with zero disabling it. Verify one reminder per overdue assignment, no reminder after departure, and no cancellation or fee mutation. Keep evidence columns if reverting application code.
