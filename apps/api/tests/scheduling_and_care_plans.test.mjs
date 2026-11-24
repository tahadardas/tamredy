import test from 'node:test';
import assert from 'node:assert/strict';
import { CarePlansService } from '../dist/care-plans/care-plans.service.js';

test('CarePlansService calculates daily occurrences correctly', () => {
  const service = new CarePlansService(null);
  const dates = service.calculateOccurrenceDates(
    '2026-12-01',
    '10:00:00',
    'DAILY',
    {},
    5,
    '2026-12-10',
  );

  assert.equal(dates.length, 5);
  assert.equal(dates[0].toISOString().startsWith('2026-12-01T'), true);
  assert.equal(dates[1].toISOString().startsWith('2026-12-02T'), true);
  assert.equal(dates[2].toISOString().startsWith('2026-12-03T'), true);
  assert.equal(dates[3].toISOString().startsWith('2026-12-04T'), true);
  assert.equal(dates[4].toISOString().startsWith('2026-12-05T'), true);
});

test('CarePlansService calculates every-other-day occurrences correctly', () => {
  const service = new CarePlansService(null);
  const dates = service.calculateOccurrenceDates(
    '2026-12-01',
    '14:30:00',
    'EVERY_OTHER_DAY',
    {},
    4,
    '2026-12-15',
  );

  assert.equal(dates.length, 4);
  assert.equal(dates[0].toISOString().startsWith('2026-12-01T'), true);
  assert.equal(dates[1].toISOString().startsWith('2026-12-03T'), true);
  assert.equal(dates[2].toISOString().startsWith('2026-12-05T'), true);
  assert.equal(dates[3].toISOString().startsWith('2026-12-07T'), true);
});

test('CarePlansService respects specific weekdays (e.g. Mon=1, Wed=3, Sat=6)', () => {
  const service = new CarePlansService(null);
  const dates = service.calculateOccurrenceDates(
    '2026-12-01', // Tuesday (2)
    '09:00:00',
    'THREE_TIMES_A_WEEK',
    { weekdays: [1, 3, 6] },
    6,
    '2026-12-20',
  );

  for (const d of dates) {
    const day = d.getDay() === 0 ? 7 : d.getDay();
    assert.equal([1, 3, 6].includes(day), true);
  }
});

test('Schedule overlap detection with 30m travel buffer', () => {
  const existingVisit = {
    start: new Date('2026-12-01T10:00:00Z'),
    expectedMinutes: 45,
  };
  // Buffered protected interval: 09:30:00Z to 11:15:00Z
  const bufferStart = new Date(existingVisit.start.getTime() - 30 * 60 * 1000);
  const bufferEnd = new Date(existingVisit.start.getTime() + (existingVisit.expectedMinutes + 30) * 60 * 1000);

  const overlaps = (start, durationMinutes) => {
    const pStart = new Date(start);
    const pEnd = new Date(pStart.getTime() + durationMinutes * 60 * 1000);
    return pStart < bufferEnd && pEnd > bufferStart;
  };

  // 1. Exact overlap
  assert.equal(overlaps('2026-12-01T10:15:00Z', 30), true);
  // 2. Starts 15m before existing visit starts (within 30m travel buffer)
  assert.equal(overlaps('2026-12-01T09:40:00Z', 30), true);
  // 3. Starts 10m after existing visit finishes (within 30m travel buffer)
  assert.equal(overlaps('2026-12-01T10:50:00Z', 30), true);
  // 4. Clearly before buffer (e.g. 08:30:00 to 09:00:00)
  assert.equal(overlaps('2026-12-01T08:30:00Z', 30), false);
  // 5. Clearly after buffer (e.g. 11:30:00 to 12:00:00)
  assert.equal(overlaps('2026-12-01T11:30:00Z', 30), false);
});
