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
