import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { SafetyRepository } from '../dist/safety/safety.repository.js';
import { SafetyService } from '../dist/safety/safety.service.js';

const migrations = new URL('../../../infra/db/migrations/', import.meta.url);
const read = (name) => readFile(new URL(name + '.sql', migrations), 'utf8');

test('Guardian binds sessions to the assigned nurse and stores immutable points and one SOS', async (t) => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec((await read('001_core')).replace(/CREATE EXTENSION[^;]*;/g, '')
    .replaceAll('geography(Point,4326)', 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, ''));
  await db.exec(`
    CREATE DOMAIN geography AS text;
    CREATE FUNCTION ST_MakePoint(float8,float8) RETURNS text LANGUAGE sql AS $$ SELECT $1::text || ',' || $2::text $$;
    CREATE FUNCTION ST_SetSRID(text, integer) RETURNS text LANGUAGE sql AS $$ SELECT $1 $$;
  `);
  await db.exec((await read('028_guardian_foundation')).replaceAll('geography(Point,4326)', 'geography'));
  const makeUser = async (phone, role) => (await db.query(
    'INSERT INTO users(phone_e164,role) VALUES($1,$2) RETURNING id', [phone, role])).rows[0].id;
  const requester = await makeUser('patient', 'PATIENT');
  const nurse = await makeUser('nurse-a', 'NURSE');
  const outsider = await makeUser('nurse-b', 'NURSE');
  const assignment = (await db.query(`
    WITH n AS (INSERT INTO nurses(user_id) VALUES($2) RETURNING id),
      b AS (INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'مستفيد','GRANTED') RETURNING id),
      s AS (INSERT INTO services(code,title_ar,price_amount) VALUES('T','زيارة',100) RETURNING id),
      r AS (INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,price_amount,currency_code,commission_bps,status)
        SELECT $1,b.id,s.id,'','MANUAL_PIN','دمشق',100,'SYP',100,'EN_ROUTE' FROM b CROSS JOIN s RETURNING id)
    INSERT INTO request_assignments(request_id,nurse_id) SELECT r.id,n.id FROM r CROSS JOIN n RETURNING id
  `, [requester, nurse])).rows[0].id;

  const svc = new SafetyService(new SafetyRepository({
    query: db.query.bind(db), transaction: db.transaction.bind(db),
  }));
  await assert.rejects(svc.start(outsider, assignment), { status: 404 });
  const session = await svc.start(nurse, assignment);
  assert.equal((await svc.start(nurse, assignment)).id, session.id);
  const point = { sequence: 1, latitude: 33.5, longitude: 36.3, accuracy: 12, capturedAt: new Date().toISOString() };
  assert.deepEqual(await svc.upload(nurse, session.id, { points: [point] }), { acceptedSequences: [1] });
  await svc.upload(nurse, session.id, { points: [point] });
  await assert.rejects(svc.upload(nurse, session.id, { points: [{ ...point, latitude: 33 }] }), { status: 409 });
  await assert.rejects(svc.upload(outsider, session.id, { points: [point] }), { status: 404 });

  const dto = { sessionId: session.id, clientEventId: randomUUID(), silent: true };
  const sos = await svc.sos(nurse, dto);
  assert.equal(sos.state, 'RECEIVED');
  assert.equal((await svc.sos(nurse, dto)).id, sos.id);
  await assert.rejects(svc.sos(nurse, { ...dto, silent: false }), { status: 409 });
  await assert.rejects(svc.event(outsider, sos.id), { status: 404 });
  await svc.checkout(nurse, session.id);
  assert.equal(await svc.status(nurse), null);
  await assert.rejects(svc.upload(nurse, session.id, {
    points: [{ ...point, sequence: 2, capturedAt: new Date(Date.now() + 10_000).toISOString() }],
  }), { status: 400 });
  assert.equal((await svc.event(nurse, sos.id)).state, 'RECEIVED');
  assert.equal((await db.query("SELECT id FROM outbox_events WHERE event_type='safety.sos_received'")).rows.length, 1);
});
