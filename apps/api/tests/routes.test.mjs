import test from 'node:test';
import assert from 'node:assert/strict';
const { RoutesService } = await import('../dist/maps/routes.service.js');
const o = { lat: 33.5138, lng: 36.2765 }, d = { lat: 33.52, lng: 36.29 };
const google = { routes: [{ distanceMeters: 2400, duration: '754s', polyline: { encodedPolyline: 'abc' } }] };
const ors = { routes: [{ summary: { distance: 4418.9, duration: 377.6 }, geometry: 'otpkEegl|EYt' }] };
function svc(resp, status = 200) {
  const s = new RoutesService(); s.calls = [];
  s.fetchImpl = async (u, i) => { s.calls.push({ u, i }); return { ok: status < 300, status, json: async () => resp }; };
  return s;
}
const reset = () => { delete process.env.MAPS_PROVIDER; delete process.env.GOOGLE_MAPS_SERVER_KEY; delete process.env.ORS_API_KEY; };

test('not configured without the provider key (OSM default and Google)', async () => {
  reset();
  await assert.rejects(svc(ors).compute(o, d), e => e.getStatus() === 503 && e.getResponse().provider === 'osm');
  process.env.MAPS_PROVIDER = 'google';
  await assert.rejects(svc(google).compute(o, d), e => e.getStatus() === 503 && e.getResponse().provider === 'google');
});

test('OpenRouteService: [lng,lat] order, key header, parsing, 30s cache', async () => {
  reset(); process.env.ORS_API_KEY = 'k';
  const s = svc(ors); let t = 1_000_000; s.now = () => t;
  const a = await s.compute(o, d);
  assert.deepEqual(a, { distanceMeters: 4419, durationSeconds: 378, polyline: 'otpkEegl|EYt' });
  assert.match(s.calls[0].u, /api\.heigit\.org\/openrouteservice\/v2\/directions\/driving-car$/);
  assert.equal(s.calls[0].i.headers.Authorization, 'k');
  assert.deepEqual(JSON.parse(s.calls[0].i.body).coordinates, [[o.lng, o.lat], [d.lng, d.lat]]);
  await s.compute({ lat: o.lat + 0.00001, lng: o.lng }, d);
  assert.equal(s.calls.length, 1);
  t += 31_000; await s.compute(o, d);
  assert.equal(s.calls.length, 2);
});

test('Google provider still works behind the flag', async () => {
  reset(); process.env.MAPS_PROVIDER = 'google'; process.env.GOOGLE_MAPS_SERVER_KEY = 'g';
  const s = svc(google);
  assert.deepEqual(await s.compute(o, d), { distanceMeters: 2400, durationSeconds: 754, polyline: 'abc' });
  assert.equal(s.calls[0].i.headers['X-Goog-Api-Key'], 'g');
});

test('upstream failure and empty result map to 502/404', async () => {
  reset(); process.env.ORS_API_KEY = 'k';
  await assert.rejects(svc({}, 500).compute(o, d), e => e.getStatus() === 502);
  await assert.rejects(svc({ routes: [] }).compute(o, d), e => e.getStatus() === 404);
});
