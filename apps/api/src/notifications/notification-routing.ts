import { randomUUID } from 'node:crypto';

export type RecipientRole = 'PATIENT' | 'NURSE' | 'ADMIN' | 'CLINICAL_REVIEWER';
export type TargetApp = 'PATIENT_APP' | 'NURSE_APP' | 'ADMIN_WEB';
export type NotificationPriority = 'CRITICAL' | 'HIGH' | 'NORMAL' | 'LOW';

export interface NotificationEnvelopeInput {
  eventId?: string;
  eventType: string;
  recipientUserId: string;
  recipientRole: RecipientRole;
  targetApp?: TargetApp;
  requestId?: string | null;
  assignmentId?: string | null;
  offerId?: string | null;
  proposalId?: string | null;
  conversationId?: string | null;
  callId?: string | null;
  entityVersion?: number | null;
  createdAt?: string | null;
  expiresAt?: string | null;
  priority?: NotificationPriority;
  deepLink?: string;
  skipPush?: boolean;
  extra?: Record<string, unknown>;
}

export function targetAppForRole(role: RecipientRole): TargetApp {
  if (role === 'NURSE') return 'NURSE_APP';
  if (role === 'PATIENT') return 'PATIENT_APP';
  return 'ADMIN_WEB';
}

export function defaultPriorityForEvent(eventType: string): NotificationPriority {
  switch (eventType) {
    case 'offer.created':
    case 'call.incoming':
    case 'visit.departure_delayed':
    case 'safety.sos_received':
      return 'CRITICAL';
    case 'request.assigned':
    case 'marketplace.proposal.created':
    case 'marketplace.proposal.accepted':
    case 'visit.depart':
    case 'visit.arrive':
    case 'visit.start':
    case 'visit.complete':
    case 'visit.interrupted':
    case 'request.cancelled':
    case 'chat.message':
    case 'payment.paid':
    case 'payment.partially_paid':
    case 'payment.partial':
    case 'request.clinical_review_changed':
      return 'HIGH';
    default:
      return 'NORMAL';
  }
}

export function deepLinkForEvent(
  eventType: string,
  role: RecipientRole,
  ids: {
    requestId?: string | null;
    assignmentId?: string | null;
    offerId?: string | null;
    proposalId?: string | null;
    conversationId?: string | null;
    callId?: string | null;
  },
): string {
  const prefix = role === 'NURSE' ? 'tamreedy://nurse' : role === 'PATIENT' ? 'tamreedy://patient' : 'tamreedy://admin';

  if (eventType === 'call.incoming' && ids.callId) {
    return `${prefix}/calls/${ids.callId}`;
  }
  if (eventType === 'chat.message' && ids.conversationId) {
    return `${prefix}/chat/${ids.conversationId}`;
  }
  if (role === 'NURSE') {
    if (eventType === 'offer.created' && ids.offerId) {
      return `${prefix}/offers/${ids.offerId}`;
    }
    if (eventType.startsWith('marketplace.recovery') || eventType === 'marketplace.request.published') {
      return ids.requestId ? `${prefix}/marketplace/${ids.requestId}` : `${prefix}/marketplace`;
    }
    if (eventType === 'marketplace.proposal.accepted' || eventType === 'visit.departure_delayed' || eventType === 'request.schedule_released') {
      return ids.assignmentId ? `${prefix}/assignments/${ids.assignmentId}` : `${prefix}/home`;
    }
    if (eventType === 'payment.tip' && ids.requestId) {
      return `${prefix}/requests/${ids.requestId}/bill`;
    }
    if (eventType.startsWith('safety.')) {
      return `${prefix}/guardian`;
    }
    return ids.requestId ? `${prefix}/requests/${ids.requestId}` : `${prefix}/home`;
  }

  if (role === 'PATIENT') {
    if (eventType === 'marketplace.proposal.created' || eventType === 'marketplace.proposal.withdrawn') {
      return ids.requestId ? `${prefix}/requests/${ids.requestId}/proposals` : `${prefix}/requests`;
    }
    if (eventType === 'visit.complete' || eventType === 'payment.paid' || eventType === 'payment.partially_paid' || eventType === 'payment.partial') {
      return ids.requestId ? `${prefix}/requests/${ids.requestId}/bill` : `${prefix}/requests`;
    }
    if (ids.requestId) {
      return `${prefix}/requests/${ids.requestId}`;
    }
    return `${prefix}/home`;
  }

  return `${prefix}/home`;
}

export function buildNotificationPayload(input: NotificationEnvelopeInput): Record<string, unknown> {
  const targetApp = input.targetApp ?? targetAppForRole(input.recipientRole);
  const createdAt = input.createdAt ?? new Date().toISOString();
  const deepLink = input.deepLink ?? deepLinkForEvent(input.eventType, input.recipientRole, input);
  const priority = input.priority ?? defaultPriorityForEvent(input.eventType);

  return {
    ...(input.extra ?? {}),
    eventId: input.eventId ?? randomUUID(),
    eventType: input.eventType,
    recipientUserId: input.recipientUserId,
    recipientRole: input.recipientRole,
    targetApp,
    requestId: input.requestId ?? null,
    assignmentId: input.assignmentId ?? null,
    offerId: input.offerId ?? null,
    proposalId: input.proposalId ?? null,
    conversationId: input.conversationId ?? null,
    callId: input.callId ?? null,
    entityVersion: input.entityVersion ?? null,
    createdAt,
    expiresAt: input.expiresAt ?? null,
    priority,
    deepLink,
    ...(input.skipPush ? { skipPush: true } : {}),
  };
}
