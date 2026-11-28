import { collectDispatchCandidates, diagnoseExclusions } from './dispatch-candidates.ts';
import type pg from 'pg';
import { runOpenSearch } from './open-dispatch.ts';
import { featureCapabilities } from '../../../packages/backend-policy/capabilities.mjs';

const defaultWaves = [
  { radius: 3000, seconds: 15 },
  { radius: 6000, seconds: 15 },
  { radius: 10000, seconds: 20 },
];

async function loadWaves(c: pg.PoolClient) {
  try {
    const r = await c.query(`SELECT value FROM app_settings WHERE key='dispatch'`);
    const w = r.rows[0]?.value?.waves;
    if (Array.isArray(w) && w.length >= 1 && w.length <= 5 && w.every((x: any) => x.radiusM > 0 && x.seconds > 0)) {
      return w.map((x: any) => ({ radius: Number(x.radiusM), seconds: Number(x.seconds) }));
    }
  } catch {}
  return defaultWaves;
}

export async function doDispatch(pool: pg.Pool): Promise<boolean> {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const due = await c.query(`
      SELECT j.request_id, cr.status, cr.requester_user_id, cr.search_expires_at,
        cr.clinical_approval_status
      FROM dispatch_jobs j JOIN care_requests cr ON cr.id = j.request_id
      WHERE j.next_run_at <= now() AND ($1::boolean OR cr.search_expires_at IS NULL)
      ORDER BY j.next_run_at, j.request_id LIMIT 1
      FOR UPDATE OF cr SKIP LOCKED
    `,[featureCapabilities().openDispatchEnabled]);

    if (!due.rowCount) {
      await c.query('COMMIT');
      return false;
    }

    const request = due.rows[0];
    const { request_id: requestId } = request;
    const job = await c.query(
      'SELECT next_wave FROM dispatch_jobs WHERE request_id=$1 AND next_run_at <= clock_timestamp()',
      [requestId],
    );
    if (!job.rowCount) {
      await c.query('COMMIT');
      return false;
    }
    const wave: number = job.rows[0].next_wave;

    if (request.status !== 'OFFERING' || !['NOT_REQUIRED','APPROVED'].includes(request.clinical_approval_status)) {
      await c.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [requestId]);
      await c.query('COMMIT');
      return true;
    }

    if (request.search_expires_at !== null) {
      await runOpenSearch(c, requestId);
      await c.query('COMMIT');
      return true;
    }

    const waveConfig = await loadWaves(c);
    if (wave > waveConfig.length) {
      console.log(`[Dispatch] Request ${requestId} exhausted all ${waveConfig.length} waves with no acceptance. Marking UNFULFILLED (AWAITING_RECOVERY_CHOICE).`);
      await c.query('SAVEPOINT recovery_choice_sp');
      try {
        await c.query(`UPDATE care_requests SET status='UNFULFILLED', marketplace_status='AWAITING_RECOVERY_CHOICE', version=version+1, updated_at=now() WHERE id=$1`, [requestId]);
        await c.query('RELEASE SAVEPOINT recovery_choice_sp');
      } catch {
        await c.query('ROLLBACK TO SAVEPOINT recovery_choice_sp');
        await c.query(`UPDATE care_requests SET status='UNFULFILLED', version=version+1, updated_at=now() WHERE id=$1`, [requestId]);
      }
      await c.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [requestId]);
      await c.query(`UPDATE request_offers SET status='EXPIRED' WHERE request_id=$1 AND status='OPEN'`, [requestId]);
      await c.query(`
        INSERT INTO outbox_events(event_type, aggregate_id, payload)
        VALUES('request.unfulfilled', $1, $2::jsonb)
      `, [requestId, JSON.stringify({
        eventType: 'request.unfulfilled',
        requestId,
        recipientUserId: request.requester_user_id,
        recipientRole: 'PATIENT',
        targetApp: 'PATIENT_APP',
        priority: 'HIGH',
        deepLink: `tamreedy://patient/requests/${requestId}`,
      })]);
      await c.query(`
        INSERT INTO outbox_events(event_type, aggregate_id, payload)
        VALUES('request.instant.search.expired', $1, $2::jsonb)
      `, [requestId, JSON.stringify({
        eventType: 'request.instant.search.expired',
        requestId,
        recipientUserId: request.requester_user_id,
        recipientRole: 'PATIENT',
        targetApp: 'PATIENT_APP',
        priority: 'HIGH',
        skipPush: true,
        deepLink: `tamreedy://patient/requests/${requestId}`,
      })]);
      await c.query('COMMIT');
      return true;
    }

    const cfg = waveConfig[wave - 1]!;
    await c.query(`UPDATE request_offers SET status='EXPIRED'
      WHERE request_id=$1 AND status='OPEN' AND expires_at <= now()`, [requestId]);

    const snapshot = await collectDispatchCandidates(c, requestId, cfg.radius);
    const diag = diagnoseExclusions(snapshot);
    const eligible = snapshot.filter(candidate => !candidate.reasons.length);
    const recipients = eligible.filter(candidate => !candidate.alreadyOffered).map(candidate => candidate.nurseId);
    const candidateOffers = await c.query(`
      WITH inserted AS (
        INSERT INTO request_offers(request_id, nurse_id, wave_no, expires_at)
        SELECT $1, id, $2, now() + ($3::integer * interval '1 second')
        FROM unnest($4::uuid[]) AS candidates(id)
        ON CONFLICT(request_id, nurse_id) DO NOTHING
        RETURNING id, nurse_id, expires_at
      ), emitted AS (
        INSERT INTO outbox_events(event_type, aggregate_id, payload)
        SELECT 'offer.created', $1,
          jsonb_build_object(
            'eventType', 'offer.created',
            'requestId', $1,
            'offerId', i.id,
            'recipientUserId', n.user_id,
            'recipientRole', 'NURSE',
            'targetApp', 'NURSE_APP',
            'expiresAt', i.expires_at,
            'priority', 'CRITICAL',
            'deepLink', 'tamreedy://nurse/offers/' || i.id::text,
            'createdAt', statement_timestamp()
          )
        FROM inserted i JOIN nurses n ON n.id = i.nurse_id
        RETURNING id
      ) SELECT count(*)::integer AS emitted_count FROM emitted
    `, [requestId, wave, cfg.seconds, recipients]);

    const emittedCount = candidateOffers.rows[0]?.emitted_count ?? 0;

    // 3. Record diagnostic audit entry
    await c.query(`
      INSERT INTO dispatch_diagnostics(
        request_id, wave_no, radius_m, candidates_found, offers_created, exclusion_reasons, excluded_nurses
      ) VALUES($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)
    `, [requestId, wave, cfg.radius, eligible.length, emittedCount, JSON.stringify(diag.reasons), JSON.stringify(diag.excludedNurses)]);

    console.log(`[Dispatch] Request ${requestId} Wave ${wave}/${waveConfig.length} (r: ${cfg.radius}m): ${emittedCount} offers created. Excluded reasons: ${JSON.stringify(diag.reasons)}`);

    // 4. Advance dispatch job schedule for next wave
    await c.query(`
      UPDATE dispatch_jobs
      SET next_wave = $2, next_run_at = now() + ($3 || ' seconds')::interval, updated_at = now()
      WHERE request_id = $1
    `, [requestId, wave + 1, String(emittedCount > 0 ? cfg.seconds : 0)]);

    await c.query('COMMIT');
    return true;
  } catch (e) {
    await c.query('ROLLBACK');
    throw e;
  } finally {
    c.release();
  }
}
