import test from 'node:test';
import assert from 'node:assert/strict';

test('Mode transition: Instant Search Timeout -> Open Marketplace', () => {
  const request = {
    id: 'req-001',
    status: 'UNFULFILLED',
    booking_mode: 'INSTANT',
    marketplace_status: 'AWAITING_RECOVERY_CHOICE',
    published_at: null,
    open_expires_at: null,
    booking_mode_version: 1,
  };

  const transitions = [];

  function switchToOpenMarketplace(req, durationMinutes = 60, reason = 'PATIENT_TIMEOUT_CONVERSION') {
    if (req.marketplace_status !== 'AWAITING_RECOVERY_CHOICE' && req.status !== 'SUBMITTED') {
      throw new Error('INVALID_STATE_FOR_MARKETPLACE_SWITCH');
    }

    const fromMode = req.booking_mode;
    const toMode = 'OPEN';
    const now = new Date();

    req.booking_mode = toMode;
    req.marketplace_status = 'OPEN_FOR_PROPOSALS';
    req.published_at = now;
    req.open_expires_at = new Date(now.getTime() + durationMinutes * 60 * 1000);
    req.booking_mode_version += 1;

    transitions.push({
      request_id: req.id,
      from_mode: fromMode,
      to_mode: toMode,
      transition_reason: reason,
      transitioned_at: now,
    });

    return req;
  }

  const updated = switchToOpenMarketplace(request, 90);
  assert.equal(updated.booking_mode, 'OPEN');
  assert.equal(updated.marketplace_status, 'OPEN_FOR_PROPOSALS');
  assert.equal(updated.booking_mode_version, 2);
  assert.ok(updated.open_expires_at.getTime() > updated.published_at.getTime());
  assert.equal(transitions.length, 1);
  assert.equal(transitions[0].transition_reason, 'PATIENT_TIMEOUT_CONVERSION');
});

test('Mode transition: Extend Open Marketplace wait window', () => {
  const initialPublished = new Date();
  const initialExpiry = new Date(initialPublished.getTime() + 60 * 60 * 1000);

  const request = {
    id: 'req-002',
    marketplace_status: 'OPEN_FOR_PROPOSALS',
    open_expires_at: initialExpiry,
  };

  function extendWaitWindow(req, additionalMinutes = 60) {
    if (req.marketplace_status !== 'OPEN_FOR_PROPOSALS') {
      throw new Error('REQUEST_NOT_OPEN');
    }
    const currentExpiry = req.open_expires_at.getTime();
    req.open_expires_at = new Date(currentExpiry + additionalMinutes * 60 * 1000);
    return req;
  }

  const extended = extendWaitWindow(request, 30);
  assert.equal(
    extended.open_expires_at.getTime(),
    initialExpiry.getTime() + 30 * 60 * 1000,
  );
});

test('Marketplace privacy shield masks exact location and addresses', () => {
  const rawRequest = {
    id: 'req-003',
    requester_name: 'محمد العلي',
    requester_phone: '+963911223344',
    address_text: 'دمشق، المزة، فيلات غربية، بناء السعادة، طابق 3، شقة 6',
    exact_coordinates: { lat: 33.5138, lng: 36.2765 },
    service_title: 'حقن وريدي ومراقبة حيوية',
    price_amount: 120000,
  };

  // Shield function used by marketplace browse
  function maskForMarketplaceBrowse(item, nurseDistanceKm) {
    const area = item.address_text.split('،')[1]?.trim() || item.address_text.split(',')[1]?.trim() || 'دمشق';
    return {
      id: item.id,
      service_title: item.service_title,
      approximate_area: area,
      distance_km: Math.round(nurseDistanceKm * 10) / 10,
      price_amount: item.price_amount,
      // Suppress exact fields
      requester_name: undefined,
      requester_phone: undefined,
      address_text: undefined,
      exact_coordinates: undefined,
    };
  }

  const masked = maskForMarketplaceBrowse(rawRequest, 2.43);

  assert.equal(masked.approximate_area, 'المزة');
  assert.equal(masked.distance_km, 2.4);
  assert.equal(masked.service_title, 'حقن وريدي ومراقبة حيوية');
  assert.equal(masked.requester_name, undefined);
  assert.equal(masked.requester_phone, undefined);
  assert.equal(masked.address_text, undefined);
  assert.equal(masked.exact_coordinates, undefined);
});
