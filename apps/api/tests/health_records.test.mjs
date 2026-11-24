import test from 'node:test';
import assert from 'node:assert/strict';

test('Clinical observation range validation correctly identifies out-of-range values', () => {
  const observationTypes = {
    SYSTOLIC_BP: { min: 50, max: 300, unit: 'mmHg' },
    DIASTOLIC_BP: { min: 30, max: 200, unit: 'mmHg' },
    HEART_RATE: { min: 30, max: 250, unit: 'bpm' },
    TEMPERATURE: { min: 30.0, max: 45.0, unit: '°C' },
    BLOOD_GLUCOSE: { min: 20, max: 800, unit: 'mg/dL' },
    PAIN_SCORE: { min: 0, max: 10, unit: 'scale_0_10' },
  };

  const validate = (type, val) => {
    const def = observationTypes[type];
    if (!def) return false;
    return val >= def.min && val <= def.max;
  };

  // Valid
  assert.equal(validate('SYSTOLIC_BP', 120), true);
  assert.equal(validate('DIASTOLIC_BP', 80), true);
  assert.equal(validate('TEMPERATURE', 37.2), true);
  assert.equal(validate('BLOOD_GLUCOSE', 115), true);
  assert.equal(validate('PAIN_SCORE', 4), true);

  // Out of range (typo guards)
  assert.equal(validate('SYSTOLIC_BP', 450), false);
  assert.equal(validate('SYSTOLIC_BP', 20), false);
  assert.equal(validate('TEMPERATURE', 55.0), false);
  assert.equal(validate('BLOOD_GLUCOSE', -5), false);
  assert.equal(validate('PAIN_SCORE', 15), false);
});

test('Clinical visit note 24h amendment window transitions', () => {
  const evaluateAmendment = (submittedAt, now, hasReason) => {
    if (!hasReason) return { ok: false, error: 'AMENDMENT_REASON_MANDATORY' };
    const hours = (now.getTime() - submittedAt.getTime()) / (3600 * 1000);
    return {
      ok: true,
      status: hours <= 24 ? 'AMENDED' : 'FINALIZED',
      requiresAddendum: hours > 24,
    };
  };

  const submitted = new Date('2026-12-01T10:00:00Z');
  // 1. Within 2 hours
  const updateWithin2h = evaluateAmendment(submitted, new Date('2026-12-01T12:00:00Z'), true);
  assert.equal(updateWithin2h.ok, true);
  assert.equal(updateWithin2h.status, 'AMENDED');
  assert.equal(updateWithin2h.requiresAddendum, false);

  // 2. Missing reason
  const updateNoReason = evaluateAmendment(submitted, new Date('2026-12-01T12:00:00Z'), false);
  assert.equal(updateNoReason.ok, false);

  // 3. Past 24 hours (e.g. 36 hours later)
  const updateLate = evaluateAmendment(submitted, new Date('2026-12-02T22:00:00Z'), true);
  assert.equal(updateLate.ok, true);
  assert.equal(updateLate.status, 'FINALIZED');
  assert.equal(updateLate.requiresAddendum, true);
});

test('RBAC for health records enforces least-privilege', () => {
  const checkAccess = (role, isOwner, isAssignedNurse) => {
    if (['ADMIN', 'CLINICAL_REVIEWER'].includes(role)) return true;
    if (role === 'PATIENT' && isOwner) return true;
    if (role === 'NURSE' && isAssignedNurse) return true;
    return false; // Unauthorized marketing/billing/unassigned nurses
  };

  assert.equal(checkAccess('PATIENT', true, false), true); // owner
  assert.equal(checkAccess('PATIENT', false, false), false); // non-owner patient
  assert.equal(checkAccess('NURSE', false, true), true); // assigned nurse
  assert.equal(checkAccess('NURSE', false, false), false); // unassigned random nurse
  assert.equal(checkAccess('MARKETING', false, false), false); // non-clinical staff
});
