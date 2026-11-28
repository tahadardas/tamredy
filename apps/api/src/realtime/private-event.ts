import type { RecipientRole, TargetApp } from '../notifications/notification-routing.js';

export interface PrivateEventEnvelope extends Record<string, unknown> {
  eventId: string;
  eventType: string;
  recipientUserId: string;
  recipientRole: RecipientRole;
  targetApp: TargetApp;
  createdAt: string;
}

export function isPrivateEventEnvelope(value: unknown, userId: string, type: string): value is PrivateEventEnvelope {
  if (!value || typeof value !== 'object') return false;
  const e = value as Record<string, unknown>;
  const app = e.recipientRole === 'PATIENT' ? 'PATIENT_APP' : e.recipientRole === 'NURSE' ? 'NURSE_APP' :
    ['ADMIN','CLINICAL_REVIEWER'].includes(String(e.recipientRole)) ? 'ADMIN_WEB' : null;
  return typeof e.eventId === 'string' && e.eventId.length > 0 && e.eventType === type &&
    e.recipientUserId === userId && app !== null && e.targetApp === app &&
    typeof e.createdAt === 'string' && Number.isFinite(Date.parse(e.createdAt));
}

export interface CallSignalEventEnvelope extends PrivateEventEnvelope {
  eventType: 'call.signal';
  callId: string;
  signalType: 'SDP_OFFER' | 'SDP_ANSWER' | 'ICE_CANDIDATE' | 'ICE_RESTART';
  sequenceNumber: number;
  data: Record<string, unknown>;
}

export interface TrackingEventEnvelope extends PrivateEventEnvelope {
  eventType: 'tracking.updated';
  requestId: string;
  assignmentId: string;
  sequenceNumber: number;
  latitude: number;
  longitude: number;
  capturedAt: string;
}

export function validHighFrequencyEvent(e: PrivateEventEnvelope): boolean {
  if (e.eventType !== 'call.signal' && e.eventType !== 'tracking.updated') return true;
  if (!Number.isSafeInteger(e.sequenceNumber) || Number(e.sequenceNumber) < 0) return false;
  if (e.eventType === 'call.signal') {
    return typeof e.callId === 'string' && Number(e.sequenceNumber) > 0 &&
      ['SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART'].includes(String(e.signalType)) &&
      !!e.data && typeof e.data === 'object' && !Array.isArray(e.data);
  }
  return typeof e.requestId === 'string' && typeof e.assignmentId === 'string' &&
    typeof e.latitude === 'number' && Number.isFinite(e.latitude) && Math.abs(e.latitude) <= 90 &&
    typeof e.longitude === 'number' && Number.isFinite(e.longitude) && Math.abs(e.longitude) <= 180 &&
    typeof e.capturedAt === 'string' && Number.isFinite(Date.parse(e.capturedAt));
}
