import test from 'node:test';
import assert from 'node:assert/strict';

test('Voice call state machine legal transitions and terminal state locking', () => {
  const legalTransitions = {
    INITIATED: ['RINGING', 'ACCEPTED', 'REJECTED', 'MISSED', 'FAILED', 'ENDED'],
    RINGING: ['ACCEPTED', 'REJECTED', 'MISSED', 'FAILED', 'ENDED'],
    ACCEPTED: ['CONNECTING', 'CONNECTED', 'FAILED', 'ENDED'],
    CONNECTING: ['CONNECTED', 'FAILED', 'ENDED'],
    CONNECTED: ['ENDED', 'FAILED'],
    REJECTED: [],
    MISSED: [],
    FAILED: [],
    ENDED: [],
  };

  const canTransition = (current, next) => (legalTransitions[current] ?? []).includes(next);

  // Normal flow
  assert.equal(canTransition('INITIATED', 'ACCEPTED'), true);
  assert.equal(canTransition('ACCEPTED', 'CONNECTED'), true);
  assert.equal(canTransition('CONNECTED', 'ENDED'), true);

  // Rejection flow
  assert.equal(canTransition('INITIATED', 'REJECTED'), true);

  // Terminal state cannot transition
  assert.equal(canTransition('ENDED', 'CONNECTED'), false);
  assert.equal(canTransition('REJECTED', 'ACCEPTED'), false);
});

test('Call duration calculation upon hangup', () => {
  const calculateDuration = (connectedAtStr, endedAtStr) => {
    if (!connectedAtStr) return 0;
    const connected = new Date(connectedAtStr).getTime();
    const ended = new Date(endedAtStr).getTime();
    return Math.max(0, Math.round((ended - connected) / 1000));
  };

  // 1. Connected for 2 minutes 30 seconds
  const d1 = calculateDuration('2026-12-01T10:00:00Z', '2026-12-01T10:02:30Z');
  assert.equal(d1, 150);

  // 2. Unconnected rejected call
  const d2 = calculateDuration(null, '2026-12-01T10:00:15Z');
  assert.equal(d2, 0);
});

test('WebRTC signaling event types validation', () => {
  const validEventTypes = new Set(['SDP_OFFER', 'SDP_ANSWER', 'ICE_CANDIDATE']);
  const isValid = type => validEventTypes.has(type);

  assert.equal(isValid('SDP_OFFER'), true);
  assert.equal(isValid('SDP_ANSWER'), true);
  assert.equal(isValid('ICE_CANDIDATE'), true);
  assert.equal(isValid('AUDIO_RECORDING'), false); // No call recording allowed
});
