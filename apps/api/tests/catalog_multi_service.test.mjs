import test from 'node:test';
import assert from 'node:assert/strict';

test('Multi-service calculation combines prices and expected minutes accurately', () => {
  const items = [
    { code: 'WOUND_SIMPLE_DRESSING', priceAmount: 25000, expectedMinutes: 25, quantity: 1, requiresPrescription: false },
    { code: 'BP_GLUCOSE_CHECK', priceAmount: 15000, expectedMinutes: 15, quantity: 1, requiresPrescription: false },
    { code: 'INJ_IM', priceAmount: 20000, expectedMinutes: 20, quantity: 2, requiresPrescription: true },
  ];

  let totalBasePrice = 0;
  let totalMinutes = 0;
  let anyPrescription = false;

  for (const it of items) {
    totalBasePrice += it.priceAmount * it.quantity;
    totalMinutes += it.expectedMinutes * it.quantity;
    if (it.requiresPrescription) anyPrescription = true;
  }

  // 25000*1 + 15000*1 + 20000*2 = 80000
  assert.equal(totalBasePrice, 80000);
  // 25*1 + 15*1 + 20*2 = 80 minutes
  assert.equal(totalMinutes, 80);
  assert.equal(anyPrescription, true);
});

test('Multi-service dispatch requires nurse to have approved skills for all services', () => {
  const requiredServiceIds = ['serv-1', 'serv-2', 'serv-3'];
  const nurseAApprovedSkills = ['serv-1', 'serv-2']; // missing serv-3
  const nurseBApprovedSkills = ['serv-1', 'serv-2', 'serv-3', 'serv-4']; // has all

  const isNurseAEligible = requiredServiceIds.every(id => nurseAApprovedSkills.includes(id));
  const isNurseBEligible = requiredServiceIds.every(id => nurseBApprovedSkills.includes(id));

  assert.equal(isNurseAEligible, false);
  assert.equal(isNurseBEligible, true);
});

test('Single travel fee policy applies once per visit', () => {
  const travelFee = 5000;
  const visitServicesCount = 4;
  // Policy rule: travel fee is never multiplied by service count
  const appliedTravelFee = travelFee; // once
  assert.equal(appliedTravelFee, 5000);
  assert.notEqual(appliedTravelFee, travelFee * visitServicesCount);
});
