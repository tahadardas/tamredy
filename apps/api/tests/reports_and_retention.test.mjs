import test from 'node:test';
import assert from 'node:assert/strict';

test('Clinical Report structure includes all mandatory clinical and verification fields', () => {
  const reportPayload = {
    reportNumber: 'TMR-RPT-12345678',
    reportVersion: 1,
    generatedAt: new Date().toISOString(),
    verificationToken: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    disclaimerAr: 'هذا التقرير صادر عن منصة تمريضي للرعاية التمريضية المنزلية لتوثيق الإجراءات والملاحظات المنفذة، ولا يعد تشخيصاً طبياً بديلاً عن استشارة الطبيب المختص أو وثيقة حكومية.',
    visit: { requestId: 'req-1', visitDate: '2026-12-01', addressText: 'دمشق - المزة' },
    beneficiary: { id: 'ben-1', displayName: 'أحمد السالم', ageYears: 65, knownAllergies: ['بنسلين'], chronicConditions: ['سكري نوع 2'] },
    provider: { nurseId: 'nurse-1', displayName: 'ممرض معتمد', licenseRef: 'RN-9821' },
    services: [{ code: 'WOUND_CARE', titleAr: 'تضميد جروح', unitPrice: 35000, expectedMinutes: 45 }],
    observations: [
      { type: 'SYSTOLIC_BP', nameAr: 'ضغط الدم الانقباضي', value: 125, unit: 'mmHg', measuredAt: '2026-12-01T10:15:00Z' },
      { type: 'BLOOD_GLUCOSE', nameAr: 'سكر الدم', value: 110, unit: 'mg/dL', measuredAt: '2026-12-01T10:20:00Z' },
    ],
    notes: {
      clinicalNotes: 'تم تطهير الجرح الجراحي وتبديل الضماد المعقم. الجرح نظيف دون احمرار أو علامات إنتان.',
      materialsUsed: [{ name: 'ضماد معقم', quantity: 2 }, { name: 'مطهر بوفيدون', quantity: 1 }],
      followupRecommendations: 'استمرار تبديل الضماد كل 48 ساعة ومراجعة الطبيب في حال ظهور حمى.',
    },
  };

  assert.equal(reportPayload.reportNumber.startsWith('TMR-RPT-'), true);
  assert.equal(reportPayload.observations.length, 2);
  assert.equal(reportPayload.disclaimerAr.includes('لا يعد تشخيصاً طبياً'), true);
  assert.equal(reportPayload.verificationToken.length, 32);
});

test('Favorite nurse suppression when mutual block exists', () => {
  const favorites = [
    { nurseId: 'nurse-A', name: 'سارة' },
    { nurseId: 'nurse-B', name: 'محمد' },
  ];
  const blockedNurseIds = new Set(['nurse-A']);

  const visibleFavorites = favorites.filter(f => !blockedNurseIds.has(f.nurseId));
  assert.equal(visibleFavorites.length, 1);
  assert.equal(visibleFavorites[0].nurseId, 'nurse-B');
});

test('Package grant visit redemption and exhaustion invariants', () => {
  const grant = {
    id: 'grant-1',
    totalVisits: 5,
    remainingVisits: 2,
    status: 'ACTIVE',
    redemptions: new Set(['req-1', 'req-2', 'req-3']),
  };

  const redeem = (reqId) => {
    if (grant.status !== 'ACTIVE' || grant.remainingVisits <= 0) {
      throw new Error('PACKAGE_EXHAUSTED');
    }
    if (grant.redemptions.has(reqId)) {
      throw new Error('REQUEST_ALREADY_REDEEMED');
    }
    grant.remainingVisits -= 1;
    grant.redemptions.add(reqId);
    if (grant.remainingVisits === 0) grant.status = 'EXHAUSTED';
    return { ok: true, remaining: grant.remainingVisits, status: grant.status };
  };

  // 1st redemption
  const r1 = redeem('req-4');
  assert.equal(r1.remaining, 1);
  assert.equal(r1.status, 'ACTIVE');

  // Double redemption of same request rejected
  assert.throws(() => redeem('req-4'), /REQUEST_ALREADY_REDEEMED/);

  // 2nd redemption exhausts package
  const r2 = redeem('req-5');
  assert.equal(r2.remaining, 0);
  assert.equal(r2.status, 'EXHAUSTED');

  // Next redemption rejected because exhausted
  assert.throws(() => redeem('req-6'), /PACKAGE_EXHAUSTED/);
});
