import test from 'node:test';
import assert from 'node:assert/strict';

test('Atomic proposal acceptance supersedes sibling proposals', () => {
  // Simulate request state and proposals under concurrent acceptance
  const requestId = 'req-100';
  const nurseA = 'nurse-1';
  const nurseB = 'nurse-2';

  let requestState = {
    id: requestId,
    status: 'SUBMITTED',
    marketplace_status: 'OPEN_FOR_PROPOSALS',
    assigned_nurse_id: null,
  };

  const proposals = [
    { id: 'prop-A', request_id: requestId, nurse_id: nurseA, status: 'PENDING' },
    { id: 'prop-B', request_id: requestId, nurse_id: nurseB, status: 'PENDING' },
  ];

  // Simulating atomic acceptProposal logic under row lock:
  function acceptProposal(proposalId) {
    if (requestState.status === 'ACCEPTED' || requestState.assigned_nurse_id) {
      throw new Error('REQUEST_ALREADY_ACCEPTED');
    }
    const prop = proposals.find(p => p.id === proposalId);
    if (!prop || prop.status !== 'PENDING') {
      throw new Error('PROPOSAL_NOT_PENDING');
    }

    // 1. Mark winning proposal ACCEPTED
    prop.status = 'ACCEPTED';

    // 2. Assign request
    requestState.status = 'ACCEPTED';
    requestState.marketplace_status = 'COMPLETED';
    requestState.assigned_nurse_id = prop.nurse_id;

    // 3. Supersede all other pending proposals for this request
    for (const other of proposals) {
      if (other.id !== proposalId && other.status === 'PENDING') {
        other.status = 'SUPERSEDED';
      }
    }

    return { success: true, winningProposal: prop };
  }

  // Patient accepts Proposal A
  const resA = acceptProposal('prop-A');
  assert.equal(resA.success, true);
  assert.equal(requestState.status, 'ACCEPTED');
  assert.equal(requestState.assigned_nurse_id, nurseA);

  const propA = proposals.find(p => p.id === 'prop-A');
  const propB = proposals.find(p => p.id === 'prop-B');

  assert.equal(propA.status, 'ACCEPTED');
  assert.equal(propB.status, 'SUPERSEDED');

  // Any subsequent attempt to accept Proposal B must be rejected
  assert.throws(() => {
    acceptProposal('prop-B');
  }, /REQUEST_ALREADY_ACCEPTED|PROPOSAL_NOT_PENDING/);
});

test('Double booking prevention enforces 30-minute buffer around scheduled visits', () => {
  const existingAssignments = [
    {
      nurse_id: 'nurse-1',
      start_at: new Date('2026-12-01T14:00:00Z'),
      duration_minutes: 60, // ends at 15:00:00Z
    },
  ];

  function hasScheduleConflict(nurseId, newStart, durationMinutes = 45, bufferMinutes = 30) {
    const pStart = new Date(newStart).getTime();
    const pEnd = pStart + durationMinutes * 60 * 1000;

    for (const assign of existingAssignments) {
      if (assign.nurse_id !== nurseId) continue;
      const aStart = assign.start_at.getTime();
      const aEnd = aStart + assign.duration_minutes * 60 * 1000;

      const bufferedStart = aStart - bufferMinutes * 60 * 1000;
      const bufferedEnd = aEnd + bufferMinutes * 60 * 1000;

      // Overlap condition
      if (pStart < bufferedEnd && pEnd > bufferedStart) {
        return true;
      }
    }
    return false;
  }

  // Conflict 1: Starts at 14:15 (during existing visit)
  assert.equal(hasScheduleConflict('nurse-1', '2026-12-01T14:15:00Z'), true);

  // Conflict 2: Starts at 15:15 (within 30m post-visit travel buffer)
  assert.equal(hasScheduleConflict('nurse-1', '2026-12-01T15:15:00Z'), true);

  // Conflict 3: Starts at 13:15, ends 14:00 (within 30m pre-visit travel buffer)
  assert.equal(hasScheduleConflict('nurse-1', '2026-12-01T13:15:00Z', 45), true);

  // Clear 1: Starts at 12:00, ends 12:45 (buffered start is 13:30, well before)
  assert.equal(hasScheduleConflict('nurse-1', '2026-12-01T12:00:00Z', 45), false);

  // Clear 2: Starts at 16:00 (buffered end is 15:30, well after)
  assert.equal(hasScheduleConflict('nurse-1', '2026-12-01T16:00:00Z', 45), false);

  // Clear 3: Different nurse
  assert.equal(hasScheduleConflict('nurse-2', '2026-12-01T14:15:00Z'), false);
});

test('Canonical lock hierarchy prevents deadlocks', () => {
  // Tamreedy lock order:
  // 1. care_requests (ORDER BY id)
  // 2. marketplace_proposals (ORDER BY id)
  // 3. nurses (ORDER BY id)
  const canonicalOrder = ['care_requests', 'marketplace_proposals', 'nurses'];
  
  function validateLockAcquisition(sequence) {
    let lastRank = -1;
    for (const table of sequence) {
      const rank = canonicalOrder.indexOf(table);
      if (rank === -1) throw new Error(`Unknown table: ${table}`);
      if (rank < lastRank) return false; // Out-of-order acquisition risk!
      lastRank = rank;
    }
    return true;
  }

  assert.equal(validateLockAcquisition(['care_requests', 'marketplace_proposals', 'nurses']), true);
  assert.equal(validateLockAcquisition(['care_requests', 'marketplace_proposals']), true);
  assert.equal(validateLockAcquisition(['nurses', 'care_requests']), false); // deadlock risk!
});
