import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { FcmClient, pushBatch, pushCopy, loadServiceAccount } from '../src/push.ts';

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
  assert.ok(pushCopy('offer.created'));
  assert.equal(pushCopy('request.cancelled'), null);
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

test('pushBatch does one token query, sends to every device, prunes dead tokens', async () => {
  const pg = new PGlite();
  await pg.exec(`CREATE TABLE device_tokens(user_id uuid, token text UNIQUE)`);
  const U1 = '11111111-1111-1111-1111-111111111111', U2 = '22222222-2222-2222-2222-222222222222';
  await pg.query(`INSERT INTO device_tokens VALUES($1,'a-token'),($1,'dead'),($2,'b-token')`, [U1, U2]);
  let queries = 0;
  const db = { query: (s, p) => { queries++; return pg.query(s, p); } };
  const f = fakeFetch(t => t === 'dead' ? 404 : 200);
  const res = await pushBatch(db, new FcmClient(sa, f), [
    { id: 1, event_type: 'offer.created', payload: { recipientUserId: U1, requestId: 'r1' } },
    { id: 2, event_type: 'visit.arrive', payload: { recipientUserId: U2, requestId: 'r1' } },
    { id: 3, event_type: 'request.cancelled', payload: { recipientUserId: U2 } },
  ]);
  assert.deepEqual(res, { sent: 2, pruned: 1 });
  assert.equal(queries, 3); // one token SELECT + one DELETE + one alarm-switch lookup (offer events only)
  assert.equal((await pg.query('SELECT count(*)::int n FROM device_tokens')).rows[0].n, 2);
  const bodies = f.calls.filter(x => x.url.includes('messages:send')).map(x => JSON.parse(x.init.body));
  const normal = bodies.find(b => b.message.data.type === 'visit.arrive');
  assert.deepEqual(Object.keys(normal.message.data).sort(), ['expiresAt', 'offerId', 'requestId', 'type']); // ids only, no personal data
  const alarm = bodies.find(b => b.message.data.type === 'offer.created');
  assert.equal(alarm.message.data.alarm, '1');                                                           // new requests raise the alarm
});

test('incomplete service account is rejected; absence disables push', () => {
  assert.equal(loadServiceAccount(undefined), undefined);
  assert.throws(() => loadServiceAccount('{"project_id":"x"}'));
});
