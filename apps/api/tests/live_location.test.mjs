import assert from 'node:assert/strict';
import test from 'node:test';
import { LocationValidator } from '../dist/live-location/location-validator.js';

const update = (overrides = {}) => ({
  latitude: 33.5138,
  longitude: 36.2765,
  accuracyMeters: 12,
  capturedAt: new Date().toISOString(),
  sequenceNumber: 2,
  sessionId: 'session-a',
  ...overrides,
});

const code = expected => error => error.getResponse?.().code === expected;

test('live location accepts a fresh, accurate and ordered update', () => {
  const validator = new LocationValidator();
  const capturedAt = new Date(Date.now() - 1_000);
  const result = validator.validate(update({ capturedAt: capturedAt.toISOString() }), 'session-a', {
    latitude: 33.5137,
    longitude: 36.2764,
    capturedAt: new Date(capturedAt.getTime() - 5_000),
    sequenceNumber: 1,
    sessionId: 'session-a',
  });
  assert.equal(result.toISOString(), capturedAt.toISOString());
});

test('live location rejects session replay, stale points and duplicate sequences', () => {
  const validator = new LocationValidator();
  assert.throws(() => validator.validate(update(), 'session-b'), code('DEVICE_SESSION_MISMATCH'));
  assert.throws(() => validator.validate(update({ capturedAt: new Date(Date.now() - 180_000).toISOString() }), 'session-a'), code('LOCATION_STALE'));
  const capturedAt = new Date(Date.now() - 1_000);
  assert.throws(() => validator.validate(update({ capturedAt: capturedAt.toISOString(), sequenceNumber: 7 }), 'session-a', {
    latitude: 33.5138,
    longitude: 36.2765,
    capturedAt: new Date(capturedAt.getTime() - 1_000),
    sequenceNumber: 7,
    sessionId: 'session-a',
  }), code('LOCATION_DUPLICATE'));
});

test('live location rejects implausible geographic jumps', () => {
  const validator = new LocationValidator();
  const capturedAt = new Date(Date.now() - 1_000);
  assert.throws(() => validator.validate(update({
    latitude: 34.5138,
    capturedAt: capturedAt.toISOString(),
  }), 'session-a', {
    latitude: 33.5138,
    longitude: 36.2765,
    capturedAt: new Date(capturedAt.getTime() - 1_000),
    sequenceNumber: 1,
    sessionId: 'session-a',
  }), code('LOCATION_IMPLAUSIBLE_JUMP'));
});
