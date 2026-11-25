import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    location: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.LOCATION_EVENTS_PER_SECOND || 100),
      timeUnit: '1s',
      duration: __ENV.DURATION || '2m',
      preAllocatedVUs: Number(__ENV.PREALLOCATED_VUS || 100),
      maxVUs: Number(__ENV.MAX_VUS || 2000),
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<100', 'p(99)<250'],
  },
};

const baseUrl = __ENV.API_BASE_URL;
const sessions = JSON.parse(open(__ENV.LOCATION_SESSIONS_FILE || './location-sessions.synthetic.json'));

export default function () {
  const identity = sessions[__VU % sessions.length];
  const sequence = (__ITER + 1) + (__VU * 1000000);
  const payload = JSON.stringify({
    latitude: 33.5138 + ((__VU % 100) / 10000),
    longitude: 36.2765 + ((__VU % 100) / 10000),
    accuracyMeters: 12,
    capturedAt: new Date().toISOString(),
    sequenceNumber: sequence,
    sessionId: identity.sessionId,
    speedMetersPerSecond: 4.5,
    heading: 90,
    locationSource: 'GPS',
  });
  const response = http.put(`${baseUrl}/v1/nurse/me/location`, payload, {
    headers: { Authorization: `Bearer ${identity.accessToken}`, 'Content-Type': 'application/json' },
  });
  check(response, { 'location accepted': r => r.status === 200 });
}
