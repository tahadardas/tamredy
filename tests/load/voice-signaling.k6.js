import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    signaling: {
      executor: 'constant-vus',
      vus: Number(__ENV.CALLS || 10),
      duration: __ENV.DURATION || '2m',
    },
  },
  thresholds: { http_req_failed: ['rate<0.01'], http_req_duration: ['p(95)<250'] },
};

const baseUrl = __ENV.API_BASE_URL;
const calls = JSON.parse(open(__ENV.CALL_SESSIONS_FILE || './call-sessions.synthetic.json'));

export default function () {
  const call = calls[__VU % calls.length];
  const response = http.post(`${baseUrl}/v1/calls/${call.callId}/signal`, JSON.stringify({
    eventId: `${String(__VU).padStart(8, '0')}-0000-4000-8000-${String(__ITER + 1).padStart(12, '0')}`,
    sequenceNumber: __ITER + 1,
    eventType: 'ICE_CANDIDATE',
    data: { candidate: `candidate:synthetic-${__VU}-${__ITER}`, sdpMid: '0', sdpMLineIndex: 0 },
  }), { headers: { Authorization: `Bearer ${call.accessToken}`, 'Content-Type': 'application/json' } });
  check(response, { 'signal relayed': r => r.status === 200 });
}
