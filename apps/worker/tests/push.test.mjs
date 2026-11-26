import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { FcmClient, pushDeliverBatch, pushCopy, loadServiceAccount } from '../src/push.ts';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
const sa = { project_id: 'proj', client_email: 'svc@proj.iam.gserviceaccount.com', private_key: privateKey };

function fakeFetch(statusFor = () => 200) {
  const calls = [];
  const f = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes('oauth2')) return new Response(JSON.stringify({ access_token: 'tok', expires_in: 3600 }), { status: 200 });
    const status = statusFor(JSON.parse(init.body).message.token);
    return new Response(status === 404 ? JSON.stringify({ error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }) : '{}', { status });
  };
  f.calls = calls;
  return f;
}

test('copy never contains personal data and unknown events are silent', () => {
  assert.ok(pushCopy('offer.created', {}, 'NURSE'));
  assert.equal(pushCopy('offer.created', {}, 'PATIENT'), null);
  assert.equal(pushCopy('marketplace.proposal.created', {}, 'NURSE'), null);
  assert.ok(pushCopy('marketplace.proposal.created', {}, 'PATIENT'));
  assert.equal(pushCopy('test.unknown'), null);
  for (const t of ['offer.created', 'request.assigned', 'visit.depart', 'visit.arrive', 'visit.complete', 'request.unfulfilled'])
    assert.doesNotMatch(JSON.stringify(pushCopy(t)), /\d{4}|شارع|عنوان/);
});

test('FCM client authenticates once, caches the token, and classifies results', async () => {
  const f = fakeFetch(t => t === 'dead' ? 404 : t === 'boom' ? 500 : 200);
  const c = new FcmClient(sa, f);
  assert.equal(await c.send('good', { title: 't', body: 'b' }, { type: 'x' }), 'ok');
  assert.equal(await c.send('dead', { title: 't', body: 'b' }, {}), 'unregistered');
  assert.equal(await c.send('boom', { title: 't', body: 'b' }, {}), 'error');
  assert.equal(f.calls.filter(x => x.url.includes('oauth2')).length, 1);
  assert.match(f.calls.find(x => x.url.includes('messages:send')).url, /projects\/proj\//);
});

test('push delivery enforces role/app isolation, active_status filtering, full envelope metadata, and ledger dedupe', async t => {
  const pg = new PGlite();
  t.after(() => pg.close());
  const root = new URL('../../../infra/db/migrations/', import.meta.url);
  for (const name of ['001_core', '005_password_accounts_push', '018_dispatch_diagnostics_and_deliveries']) {
    const sql = readFileSync(new URL(`${name}.sql`, root), 'utf8')
      .replace(/CREATE EXTENSION[^;]*;/g, '')
      .replace(/geography\(Point,4326\)/g, 'text')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
    await pg.exec(sql);
  }
  await pg.exec('CREATE TABLE IF NOT EXISTS device_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid());');
  await pg.exec(readFileSync(new URL('063_notifications_routing_and_device_tokens.sql', root), 'utf8'));
  const U1 = '11111111-1111-1111-1111-111111111111', U2 = '22222222-2222-2222-2222-222222222222';
  await pg.query("INSERT INTO users(id,phone_e164,role) VALUES($1,'+1','PATIENT'),($2,'+2','PATIENT')", [U1, U2]);
  await pg.query(
    `INSERT INTO device_tokens(user_id,token,platform,app_type,role,active_status) VALUES
      ($1,'a-token','android','PATIENT_APP','PATIENT','ACTIVE'),
      ($1,'dead','android','PATIENT_APP','PATIENT','ACTIVE'),
      ($1,'wrong-app-tok','android','NURSE_APP','NURSE','ACTIVE'),
      ($1,'logged-out-tok','android','PATIENT_APP','PATIENT','LOGOUT'),
      ($2,'b-token','ios','PATIENT_APP','PATIENT','ACTIVE')`,
    [U1, U2],
  );
  await pg.query("INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES ('request.assigned',$1,'{}'),('visit.arrive',$2,'{}')", [U1, U2]);
  let tokenQueries = 0;
  const db = { query: (s, p) => {
    if (s.includes('FROM device_tokens dt')) tokenQueries++;
    return pg.query(s, p);
  } };
  const f = fakeFetch(t => t === 'dead' ? 404 : 200);
  const res = await pushDeliverBatch(db, new FcmClient(sa, f), [
    { id: 1, event_type: 'request.assigned', payload: { recipientUserId: U1, recipientRole: 'PATIENT', targetApp: 'PATIENT_APP', requestId: 'r1' } },
    { id: 2, event_type: 'visit.arrive', payload: { recipientUserId: U2, recipientRole: 'PATIENT', targetApp: 'PATIENT_APP', requestId: 'r1' } },
    { id: 3, event_type: 'test.unknown', payload: { recipientUserId: U2 } },
  ]);
  assert.deepEqual(res, { sent: 2, failed: 1, pruned: 1 });
  assert.equal(tokenQueries, 1);
  assert.equal(f.calls.filter(x => x.url.includes('oauth2')).length, 1);

  const sentTokens = f.calls.filter(x => x.url.includes('messages:send')).map(x => JSON.parse(x.init.body).message.token);
  assert.equal(sentTokens.includes('wrong-app-tok'), false);
  assert.equal(sentTokens.includes('logged-out-tok'), false);

  const bodies = f.calls.filter(x => x.url.includes('messages:send')).map(x => JSON.parse(x.init.body));
  const normal = bodies.find(b => b.message.data.type === 'visit.arrive');
  for (const k of ['eventId', 'eventType', 'recipientUserId', 'recipientRole', 'targetApp', 'requestId', 'deepLink', 'priority']) {
    assert.ok(k in normal.message.data, `Missing metadata key ${k}`);
  }
  assert.equal(normal.message.data.recipientRole, 'PATIENT');
  assert.equal(normal.message.data.targetApp, 'PATIENT_APP');
  assert.equal(normal.message.data.alarm, undefined);

  const replay = await pushDeliverBatch(db, new FcmClient(sa, f), [
    { id: 1, event_type: 'request.assigned', payload: { recipientUserId: U1, recipientRole: 'PATIENT', targetApp: 'PATIENT_APP', requestId: 'r1' } },
    { id: 2, event_type: 'visit.arrive', payload: { recipientUserId: U2, recipientRole: 'PATIENT', targetApp: 'PATIENT_APP', requestId: 'r1' } },
  ]);
  assert.equal(replay.sent, 0);
  assert.equal(f.calls.filter(x => x.url.includes('messages:send')).length, 3);
});

test('incomplete service account is rejected; absence disables push', () => {
  assert.equal(loadServiceAccount(undefined), undefined);
  assert.equal(loadServiceAccount('{"project_id":"x"}'), undefined);
});

test('offer closure is a data message addressed to the specific offer', async () => {
  const transport = fakeFetch();
  const client = new FcmClient(sa, transport);
  await client.sendClosureDetailed('test-token', { type: 'offer.closed', offerId: 'offer-1' });
  const call = transport.calls.find(item => item.url.includes('messages:send'));
  const { message } = JSON.parse(call.init.body);
  assert.deepEqual(message.data, { type: 'offer.closed', offerId: 'offer-1' });
  assert.equal(message.notification, undefined);
});
