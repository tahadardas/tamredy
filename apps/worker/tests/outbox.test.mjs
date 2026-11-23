import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { deliverOutbox } from '../src/outbox.ts';

test('outbox leases prevent overlapping delivery and permit recovery after a worker crash', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  const migrations = new URL('../../../infra/db/migrations/', import.meta.url);
  for (const name of ['001_core','018_dispatch_diagnostics_and_deliveries','023_outbox_delivery_leases']) {
    await db.exec(readFileSync(new URL(`${name}.sql`,migrations),'utf8')
      .replace(/CREATE EXTENSION[^;]*;/g,'')
      .replaceAll('geography(Point,4326)','text')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/g,''));
  }
  await db.exec(`INSERT INTO outbox_events(event_type,aggregate_id) VALUES('offer.closed',gen_random_uuid())`);
  await assert.rejects(deliverOutbox(db,'push', async events => {
    assert.equal(events.length,1);
    assert.equal(await deliverOutbox(db,'push',async () => assert.fail('claimed twice')),false);
    throw new Error('worker stopped');
  }), /worker stopped/);
  assert.equal((await db.query('SELECT push_published_at FROM outbox_events')).rows[0].push_published_at,null);
  assert.equal(await deliverOutbox(db,'realtime',async events => assert.equal(events.length,1)),true);
  await db.exec("UPDATE outbox_events SET push_lease_until=now()-interval '1 second'");
  assert.equal(await deliverOutbox(db,'push',async events => assert.equal(events[0].event_type,'offer.closed')),true);
  const done = (await db.query('SELECT push_lease_token,push_published_at,realtime_published_at FROM outbox_events')).rows[0];
  assert.equal(done.push_lease_token,null);
  assert.ok(done.push_published_at && done.realtime_published_at);
});
