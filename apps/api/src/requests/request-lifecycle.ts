import type { PoolClient } from 'pg';
import { conflict } from '../common/errors.js';

export const REQUEST_STATUSES = [
  'SCHEDULED',
  'OFFERING',
  'AWAITING_RECOVERY_CHOICE',
  'OPEN_FOR_PROPOSALS',
  'ASSIGNED',
  'EN_ROUTE',
  'ARRIVED',
  'IN_SERVICE',
  'COMPLETED',
  'CANCELLED',
  'UNFULFILLED',
  'EXPIRED',
  'ESCALATED',
] as const;

export type RequestStatus = (typeof REQUEST_STATUSES)[number];
export type RequestTransitionActor = 'PATIENT' | 'NURSE' | 'ADMIN' | 'WORKER' | 'SYSTEM';

const TERMINAL_STATUSES = new Set<RequestStatus>(['COMPLETED', 'CANCELLED', 'EXPIRED']);

const TRANSITIONS: Readonly<Record<RequestStatus, ReadonlySet<RequestStatus>>> = {
  SCHEDULED: new Set(['OFFERING', 'UNFULFILLED', 'CANCELLED', 'EXPIRED']),
  OFFERING: new Set(['OPEN_FOR_PROPOSALS', 'ASSIGNED', 'UNFULFILLED', 'CANCELLED', 'EXPIRED']),
  AWAITING_RECOVERY_CHOICE: new Set(['OFFERING', 'OPEN_FOR_PROPOSALS', 'SCHEDULED', 'CANCELLED', 'EXPIRED']),
  OPEN_FOR_PROPOSALS: new Set(['OFFERING', 'SCHEDULED', 'ASSIGNED', 'UNFULFILLED', 'CANCELLED', 'EXPIRED']),
  ASSIGNED: new Set(['EN_ROUTE', 'CANCELLED', 'ESCALATED']),
  EN_ROUTE: new Set(['ARRIVED', 'CANCELLED', 'ESCALATED']),
  ARRIVED: new Set(['IN_SERVICE', 'ESCALATED']),
  IN_SERVICE: new Set(['COMPLETED', 'ESCALATED']),
  COMPLETED: new Set(),
  CANCELLED: new Set(),
  UNFULFILLED: new Set(['OFFERING', 'OPEN_FOR_PROPOSALS', 'SCHEDULED', 'CANCELLED', 'EXPIRED']),
  EXPIRED: new Set(),
  ESCALATED: new Set(['IN_SERVICE', 'COMPLETED', 'CANCELLED']),
};

const ACTOR_RULES: Readonly<Partial<Record<RequestStatus, ReadonlySet<RequestTransitionActor>>>> = {
  CANCELLED: new Set(['PATIENT', 'ADMIN', 'SYSTEM']),
  ASSIGNED: new Set(['NURSE', 'PATIENT', 'ADMIN', 'WORKER', 'SYSTEM']),
  EN_ROUTE: new Set(['NURSE']),
  ARRIVED: new Set(['NURSE']),
  IN_SERVICE: new Set(['NURSE', 'ADMIN']),
  COMPLETED: new Set(['NURSE', 'ADMIN', 'SYSTEM']),
  ESCALATED: new Set(['NURSE', 'ADMIN', 'WORKER', 'SYSTEM']),
};

export function isRequestStatus(value: string): value is RequestStatus {
  return (REQUEST_STATUSES as readonly string[]).includes(value);
}

export function assertRequestTransition(
  from: string,
  to: RequestStatus,
  actor: RequestTransitionActor,
): void {
  if (!isRequestStatus(from) || !TRANSITIONS[from].has(to)) {
    conflict(TERMINAL_STATUSES.has(from as RequestStatus)
      ? 'REQUEST_TERMINAL_STATE'
      : 'REQUEST_STATUS_TRANSITION_NOT_ALLOWED');
  }
  const actors = ACTOR_RULES[to];
  if (actors && !actors.has(actor)) conflict('REQUEST_STATUS_ACTOR_NOT_ALLOWED');
}

export interface TransitionRequestInput {
  requestId: string;
  fromStatus: string;
  toStatus: RequestStatus;
  currentVersion: number;
  actor: RequestTransitionActor;
  actorUserId?: string | null;
  reason: string;
  metadata?: Record<string, unknown>;
}

/**
 * Performs the canonical optimistic state transition. The database trigger is a
 * second line of defence for callers (workers and administrative jobs) that do
 * not execute through the API service layer.
 */
export async function transitionRequest(
  client: PoolClient,
  input: TransitionRequestInput,
): Promise<number> {
  assertRequestTransition(input.fromStatus, input.toStatus, input.actor);

  await client.query(
    `SELECT set_config('app.request_actor_kind', $1, true),
            set_config('app.request_actor_user_id', $2, true),
            set_config('app.request_transition_reason', $3, true),
            set_config('app.request_transition_metadata', $4, true)`,
    [
      input.actor,
      input.actorUserId ?? '',
      input.reason,
      JSON.stringify(input.metadata ?? {}),
    ],
  );

  const updated = await client.query<{ version: number }>(
    `UPDATE care_requests
     SET status=$2, version=version+1, updated_at=statement_timestamp()
     WHERE id=$1 AND status=$3 AND version=$4
     RETURNING version`,
    [input.requestId, input.toStatus, input.fromStatus, input.currentVersion],
  );
  if (updated.rowCount !== 1) conflict('REQUEST_VERSION_CONFLICT');
  return updated.rows[0].version;
}
