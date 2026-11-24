import test from 'node:test';
import assert from 'node:assert/strict';
import {
  inspectMessageForContactInfo,
  normalizeDigits,
  PRIVACY_ADVISORY_TEXT,
} from '../dist/chat/phone-shield.js';

test('Phone shield detects standard and Arabic digit phone numbers', () => {
  const englishPhone = inspectMessageForContactInfo('تواصل معي على الرقم 0987080330');
  assert.equal(englishPhone.hasContactLeak, true);
  assert.equal(englishPhone.detectedKind, 'PHONE');
  assert.equal(englishPhone.advisoryMessage, PRIVACY_ADVISORY_TEXT);

  const arabicPhone = inspectMessageForContactInfo('رقم هاتفي هو ٠٩٨٧٠٨٠٣٣٠');
  assert.equal(arabicPhone.hasContactLeak, true);
  assert.equal(arabicPhone.detectedKind, 'PHONE');
});

test('Phone shield detects emails and external links', () => {
  const emailMsg = inspectMessageForContactInfo('راسلي على info@example.com');
  assert.equal(emailMsg.hasContactLeak, true);
  assert.equal(emailMsg.detectedKind, 'EMAIL');

  const linkMsg = inspectMessageForContactInfo('تفضل هذا الرابط https://wa.me/963911111111');
  assert.equal(linkMsg.hasContactLeak, true);
  assert.equal(linkMsg.detectedKind, 'EXTERNAL_LINK');
});

test('Phone shield protects medical readings and does NOT falsely trigger', () => {
  const bpMsg = inspectMessageForContactInfo('ضغط المريض اليوم هو 120/80 والنبض 72');
  assert.equal(bpMsg.hasContactLeak, false);

  const glucoseMsg = inspectMessageForContactInfo('سكر الدم الصباحي 110 mg/dl مع جرعة أنسولين 10 iu');
  assert.equal(glucoseMsg.hasContactLeak, false);

  const dosageMsg = inspectMessageForContactInfo('يرجى أخذ 500mg باراسيتامول كل 8 ساعات');
  assert.equal(dosageMsg.hasContactLeak, false);

  const dateMsg = inspectMessageForContactInfo('موعد مراجعة الطبيب في 2026-12-01');
  assert.equal(dateMsg.hasContactLeak, false);

  const emergencyMsg = inspectMessageForContactInfo('110');
  assert.equal(emergencyMsg.hasContactLeak, false);
});

test('Mutual block exclusion invariant', () => {
  const userA = 'patient-uuid-1';
  const userB = 'nurse-uuid-2';
  const activeBlocks = [
    { blocker_user_id: userA, blocked_user_id: userB, revoked_at: null },
  ];

  const isBlocked = (u1, u2) => activeBlocks.some(b =>
    !b.revoked_at && (
      (b.blocker_user_id === u1 && b.blocked_user_id === u2) ||
      (b.blocker_user_id === u2 && b.blocked_user_id === u1)
    )
  );

  assert.equal(isBlocked(userA, userB), true);
  assert.equal(isBlocked(userB, userA), true);
  assert.equal(isBlocked(userA, 'other-nurse'), false);
});
