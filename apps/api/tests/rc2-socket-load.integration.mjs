/**
 * Opt-in loopback-only load test of the real LiveGateway and Socket.IO server.
 * Uses Node's native WebSocket client with Engine.IO 4 / Socket.IO namespace
 * packets; does not install a client dependency or contact Redis/FCM.
 * RUN_RC2_SOCKET_LOAD=true TEST_DATABASE_URL=postgresql://.../tamreedy_test_...
 *   node --test apps/api/tests/rc2-socket-load.integration.mjs
 */
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdirSync, writeFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import test from 'node:test';
import pg from 'pg';
import jwt from 'jsonwebtoken';
import { Server } from 'socket.io';
import { LiveGateway } from '../dist/realtime/live.gateway.js';
import { buildNotificationPayload } from '../dist/notifications/notification-routing.js';
import { OperationalMetricsService } from '../dist/observability/operational-metrics.service.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
const enabled = process.env.RUN_RC2_SOCKET_LOAD === 'true' && Boolean(databaseUrl);
const connectionCount = 500;
const eventType = 'notification.created';

function quantiles(samples) {
  const ordered = [...samples].sort((a, b) => a - b);
  const at = p => ordered.length ? Number(ordered[Math.max(0, Math.ceil(p * ordered.length) - 1)].toFixed(3)) : null;
  return { count: ordered.length, p50Ms: at(0.50), p95Ms: at(0.95), p99Ms: at(0.99) };
}

async function deadline(promise, milliseconds, code) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(code)), milliseconds); }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

test('500 authenticated Socket.IO sessions preserve private delivery and revocation', {
  skip: !enabled && 'Requires RUN_RC2_SOCKET_LOAD=true and an explicit disposable loopback TEST_DATABASE_URL',
  timeout: 120_000,
}, async () => {
  const url = new URL(databaseUrl);
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname), 'Socket load DB must be loopback');
  assert.match(url.pathname, /^\/tamreedy_test_\w+$/, 'Socket load DB must be explicitly disposable');
  assert.notEqual(process.env.NODE_ENV, 'production', 'Production environment is forbidden');
  assert.notEqual(databaseUrl, process.env.DATABASE_URL, 'Operational DATABASE_URL must not be reused');

  const startedAt = new Date().toISOString();
  const runId = randomUUID();
  const pool = new pg.Pool({ connectionString: databaseUrl, max: 16, statement_timeout: 15_000 });
  const http = createServer();
  const io = new Server(http, { serveClient: false, pingInterval: 10_000, pingTimeout: 20_000, maxHttpBufferSize: 65_536 });
  const namespace = io.of('/live');
  const previousEnv = Object.fromEntries(['JWT_SECRET', 'JWT_ISSUER', 'JWT_AUDIENCE'].map(key => [key, process.env[key]]));
  process.env.JWT_SECRET = randomBytes(48).toString('base64url');
  process.env.JWT_ISSUER = 'tamreedy-rc2-load';
  process.env.JWT_AUDIENCE = 'tamreedy-rc2-load-clients';
  let poolWaitPeak = 0;
  let databaseQueries = 0;
  let databaseErrors = 0;
  const databaseDurations = [];
  const connectDurations = [];
  const propagationDurations = [];
  const violations = [];
  const clients = [];
  let authenticatedPeak = 0;
  let seeded = false;
  let failure = null;
  let revokedSessionDisconnected = false;
  let revokedSessionEvents = 0;
  const sentAt = new Map();
  const receivedEventIds = new Set();
  const identities = Array.from({ length: connectionCount }, (_, index) => ({
    userId: randomUUID(), sessionId: randomUUID(),
    role: index % 2 === 0 ? 'PATIENT' : 'NURSE',
    appType: index % 2 === 0 ? 'PATIENT_APP' : 'NURSE_APP',
    appKind: index % 2 === 0 ? 'patient' : 'nurse',
    eventId: randomUUID(),
  }));
  const samplePool = () => { poolWaitPeak = Math.max(poolWaitPeak, pool.waitingCount); };
  const sampler = setInterval(samplePool, 1);
  const db = {
    async query(sql, parameters) {
      databaseQueries++;
      const before = performance.now();
      const pending = pool.query(sql, parameters);
      samplePool();
      try { return await pending; }
      catch (error) { databaseErrors++; throw error; }
      finally { databaseDurations.push(performance.now() - before); samplePool(); }
    },
  };
  const gateway = new LiveGateway(db, {}, {}, new OperationalMetricsService(), {});
  gateway.io = namespace;
  // Deliberately omit onModuleInit(): this test exercises direct single-replica
  // delivery, never an ambient REDIS_URL or an external service configuration.
  namespace.on('connection', socket => { void gateway.handleConnection(socket); });

  function openClient(identity, baseUrl) {
    const token = jwt.sign({ sub: identity.userId, dsi: identity.sessionId, sgen: 1, av: null }, process.env.JWT_SECRET, {
      algorithm: 'HS256', issuer: process.env.JWT_ISSUER, audience: process.env.JWT_AUDIENCE, expiresIn: '5m',
    });
    const before = performance.now();
    const socket = new WebSocket(`${baseUrl}/socket.io/?EIO=4&transport=websocket`);
    let readyResolve, readyReject, eventResolve, eventReject, closeResolve;
    const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
    const event = new Promise((resolve, reject) => { eventResolve = resolve; eventReject = reject; });
    const closed = new Promise(resolve => { closeResolve = resolve; });
    // A failed authentication can close before the event-stage Promise.all.
    // Observe rejections immediately so cleanup never emits an unhandled one.
    event.catch(() => undefined);
    let authenticated = false;
    let eventReceived = false;
    let revoked = false;
    const context = { socket, ready, event, closed, markRevoked() { revoked = true; } };
    clients.push(context);
    socket.addEventListener('message', message => {
      const packet = String(message.data);
      if (packet.startsWith('0')) {
        socket.send('40/live,' + JSON.stringify({ token, appType: identity.appType }));
      } else if (packet === '2') {
        socket.send('3');
      } else if (packet.startsWith('41/live,')) {
        socket.close();
      } else if (packet.startsWith('42/live,')) {
        const [name, payload] = JSON.parse(packet.slice('42/live,'.length));
        if (name === 'connected' && !authenticated) {
          authenticated = true;
          connectDurations.push(performance.now() - before);
          authenticatedPeak = Math.max(authenticatedPeak, namespace.sockets.size);
          readyResolve();
        } else if (name === eventType) {
          if (revoked) revokedSessionEvents++;
          if (payload.recipientUserId !== identity.userId || payload.recipientRole !== identity.role ||
              payload.targetApp !== identity.appType || payload.eventId !== identity.eventId || payload.runId !== runId) {
            violations.push({ code: 'PRIVATE_EVENT_IDENTITY_MISMATCH', expectedUser: identity.userId, recipientUser: payload.recipientUserId });
          }
          if (receivedEventIds.has(payload.eventId)) violations.push({ code: 'DUPLICATE_PRIVATE_EVENT', eventId: payload.eventId });
          receivedEventIds.add(payload.eventId);
          if (!eventReceived) {
            eventReceived = true;
            propagationDurations.push(performance.now() - sentAt.get(payload.eventId));
            eventResolve();
          }
        }
      }
    });
    socket.addEventListener('error', () => {
      readyReject(new Error('SOCKET_TRANSPORT_ERROR'));
      eventReject(new Error('SOCKET_TRANSPORT_ERROR'));
    });
    socket.addEventListener('close', () => {
      if (!authenticated) readyReject(new Error('SOCKET_AUTHENTICATION_CLOSED'));
      if (!eventReceived) eventReject(new Error('SOCKET_CLOSED_BEFORE_PRIVATE_EVENT'));
      closeResolve();
    });
    return context;
  }

  try {
    await db.query(`INSERT INTO users(id,phone_e164,role,display_name,must_change_password)
      SELECT id,'rc2-socket-'||$4::text||'-'||id::text,role,'حساب اختبار اتصال اصطناعي',false
      FROM unnest($1::uuid[],$2::text[],$3::text[]) AS seed(id,role,app_kind)`,
    [identities.map(value => value.userId), identities.map(value => value.role), identities.map(value => value.appKind), runId]);
    seeded = true;
    await db.query(`INSERT INTO device_sessions(id,user_id,device_id,app_kind,session_generation)
      SELECT session_id,user_id,'rc2-socket-'||session_id::text,app_kind,1
      FROM unnest($1::uuid[],$2::uuid[],$3::text[]) AS seed(session_id,user_id,app_kind)`,
    [identities.map(value => value.sessionId), identities.map(value => value.userId), identities.map(value => value.appKind)]);
    await new Promise((resolve, reject) => { http.once('error', reject); http.listen(0, '127.0.0.1', resolve); });
    const baseUrl = `ws://127.0.0.1:${http.address().port}`;
    const contexts = [];
    // Bound handshake bursts to avoid testing the host TCP accept backlog;
    // all earlier sessions stay open until the simultaneous 500-session check.
    for (let offset = 0; offset < identities.length; offset += 25) {
      const batch = identities.slice(offset, offset + 25).map(identity => openClient(identity, baseUrl));
      contexts.push(...batch);
      await deadline(Promise.all(batch.map(context => context.ready)), 15_000, 'SOCKET_AUTHENTICATION_TIMEOUT');
    }
    assert.equal(namespace.sockets.size, connectionCount, 'All 500 authenticated sockets must remain concurrent');
    assert.equal(namespace.adapter.rooms.size >= connectionCount * 2, true, 'Every socket must have a private user room');

    await deadline(Promise.all(identities.map(identity => {
      sentAt.set(identity.eventId, performance.now());
      return gateway.sendToUser(identity.userId, eventType, buildNotificationPayload({
        eventId: identity.eventId, eventType, recipientUserId: identity.userId,
        recipientRole: identity.role, targetApp: identity.appType,
        extra: { runId },
      }));
    })), 30_000, 'PRIVATE_EVENT_SEND_TIMEOUT');
    await deadline(Promise.all(contexts.map(context => context.event)), 15_000, 'PRIVATE_EVENT_PROPAGATION_TIMEOUT');
    assert.equal(receivedEventIds.size, connectionCount);
    assert.deepEqual(violations, []);

    const revoked = identities[0];
    contexts[0].markRevoked();
    await db.query('UPDATE device_sessions SET revoked_at=statement_timestamp() WHERE id=$1', [revoked.sessionId]);
    await gateway.sendToUser(revoked.userId, eventType, buildNotificationPayload({
      eventId: randomUUID(), eventType, recipientUserId: revoked.userId, recipientRole: revoked.role,
      targetApp: revoked.appType, extra: { runId },
    }));
    await deadline(contexts[0].closed, 5_000, 'REVOKED_SOCKET_DID_NOT_CLOSE');
    revokedSessionDisconnected = true;
    assert.equal(revokedSessionEvents, 0, 'Revoked account must receive no subsequent private events');
    assert.equal(namespace.sockets.size, connectionCount - 1);
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    clearInterval(sampler);
    for (const context of clients) context.socket.close();
    await new Promise(resolve => io.close(resolve));
    await gateway.onModuleDestroy();
    if (seeded) {
      await pool.query('UPDATE device_sessions SET revoked_at=coalesce(revoked_at,statement_timestamp()) WHERE user_id=ANY($1::uuid[])', [identities.map(value => value.userId)]);
      await pool.query("UPDATE users SET status='DELETED' WHERE id=ANY($1::uuid[])", [identities.map(value => value.userId)]);
    }
    await pool.end();
    for (const [key, value] of Object.entries(previousEnv)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
    const metrics = {
      status: failure ? 'FAILED' : 'PASS', runId, startedAt, completedAt: new Date().toISOString(),
      runtime: process.version, database: { host: url.hostname, database: url.pathname.slice(1), poolMax: 16 },
      scope: 'Actual LiveGateway, Socket.IO server, Engine.IO4 native WebSocket clients; single replica direct delivery; synthetic accounts only',
      redisTested: false, fcmTested: false, mediaTested: false,
      requestedConnections: connectionCount, connectionLaunchBatchSize: 25, authenticatedConnections: connectDurations.length,
      peakConcurrentConnections: authenticatedPeak, receivedPrivateEvents: receivedEventIds.size,
      crossAccountDeliveryViolations: violations.length,
      revokedSessionDisconnected, revokedSessionEvents,
      connections: quantiles(connectDurations), realtimePropagation: quantiles(propagationDurations),
      databaseQuery: quantiles(databaseDurations), databaseQueries, databaseErrors, poolWaitPeak,
      syntheticFixtureRetention: 'Users marked DELETED and device sessions revoked; rows preserved for audit references',
      ...(failure ? { failure: failure instanceof Error ? failure.message : 'SOCKET_LOAD_FAILED' } : {}),
    };
    const evidence = new URL('../../../docs/rc2-evidence/', import.meta.url);
    mkdirSync(evidence, { recursive: true });
    writeFileSync(new URL('socket-load-500.json', evidence), JSON.stringify(metrics, null, 2) + '\n', 'utf8');
    console.info(JSON.stringify(metrics));
  }
});
