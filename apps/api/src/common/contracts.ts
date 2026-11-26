/**
 * Canonical API Contracts shared between Backend & Mobile Apps (Phase 11 — Contract Unification).
 * Every status enum has distinct domain boundaries (never overloading request vs assignment statuses).
 */

export type BookingMode = 'INSTANT' | 'OPEN' | 'SCHEDULED';

export type CareRequestStatus =
  | 'REQUESTED'
  | 'SCHEDULED'
  | 'OFFERING'
  | 'OPEN_FOR_PROPOSALS'
  | 'ASSIGNED'
  | 'EN_ROUTE'
  | 'ARRIVED'
  | 'IN_SERVICE'
  | 'COMPLETED'
  | 'AWAITING_RECOVERY_CHOICE'
  | 'UNFULFILLED'
  | 'ESCALATED'
  | 'CANCELLED'
  | 'EXPIRED';

export type AssignmentStatus = 'RESERVED' | 'ACTIVE' | 'RELEASED';

export type ClinicalApprovalStatus = 'NOT_REQUIRED' | 'PENDING' | 'APPROVED' | 'REJECTED';

export type NotificationPriority = 'LOW' | 'NORMAL' | 'HIGH' | 'CRITICAL';

export type TargetApp = 'PATIENT_APP' | 'NURSE_APP';

export type RecipientRole = 'PATIENT' | 'NURSE';

export interface CareRequestResponse {
  id: string;
  requester_user_id: string;
  beneficiary_id: string;
  service_id: string;
  status: CareRequestStatus;
  version: number;
  booking_mode: BookingMode;
  marketplace_status?: string | null;
  clinical_approval_status: ClinicalApprovalStatus;
  price_amount: number;
  currency_code: string;
  payment_status?: string | null;
  amount_due?: number | null;
  tip_amount?: number | null;
  service_title: string;
  beneficiary_name: string;
  address_text?: string | null;
  scheduled_at?: string | null;
  open_expires_at?: string | null;
  search_expires_at?: string | null;
  assignment_id?: string | null;
  assigned_nurse_id?: string | null;
  nurse_name?: string | null;
  active_proposals_count?: number;
  created_at: string;
}

export interface ActiveRequestsResponse {
  requests: CareRequestResponse[];
  totalActiveCount: number;
  serverNow: string;
}

export interface AssignmentResponse {
  assignment_id: string;
  assignment_status: AssignmentStatus;
  request_id: string;
  request_status: CareRequestStatus;
  version: number;
  booking_mode: BookingMode;
  departure_window_open: boolean;
  allowedActions: string[];
  service_title: string;
  beneficiary_name: string;
  patient_name?: string | null;
  address_text?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  price_amount: number;
  currency_code: string;
  scheduled_at?: string | null;
  planned_start_at?: string | null;
  departed_at?: string | null;
  expected_arrival_at?: string | null;
  eta_status?: string | null;
}

export interface ActiveAssignmentsResponse {
  assignments: AssignmentResponse[];
  unpaidInvoices: Array<{
    request_id: string;
    assignment_id: string;
    invoice_id?: string | null;
    service_title: string;
    remaining: number;
    amount_due: number;
    paid_total: number;
    currency_code: string;
  }>;
  serverNow: string;
}

export interface NurseOfferResponse {
  id: string;
  request_id: string;
  wave_no: number;
  expires_at: string;
  server_now: string;
  title_ar: string;
  service_code: string;
  expected_minutes: number;
  distance_m: number;
  price_amount: number;
  currency_code: string;
  commission_bps: number;
  nurse_share: number;
  area: string;
}

export interface MarketplaceProposalResponse {
  id: string;
  request_id: string;
  nurse_id: string;
  nurse_user_id: string;
  nurse_name: string;
  nurse_rating: number;
  completed_orders_count: number;
  license_tail?: string | null;
  status: string;
  proposal_version: number;
  proposed_arrival_at: string;
  estimated_service_minutes: number;
  note?: string | null;
  expires_at: string;
}

export interface InvoiceResponse {
  invoice_id?: string | null;
  request_id: string;
  status: 'DUE' | 'PARTIAL' | 'PAID' | string;
  gross_amount: number;
  discount_amount: number;
  surcharge_amount: number;
  distance_fee: number;
  tax_amount: number;
  tip_amount: number;
  amount_due: number;
  paid_total: number;
  remaining: number;
  currency_code: string;
}

export interface LocationSnapshotResponse {
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  recordedAt: string;
  sequenceNumber: number | null;
  source: 'redis' | 'postgres';
}

export interface ClinicalApprovalResponse {
  requestId: string;
  clinicalApprovalStatus: ClinicalApprovalStatus;
  reviewNotes?: string | null;
  reviewedAt?: string | null;
}

export interface NotificationEnvelope {
  eventId: string;
  eventType: string;
  recipientUserId: string;
  recipientRole: RecipientRole;
  targetApp: TargetApp;
  priority: NotificationPriority;
  deepLink: string;
  entityVersion?: number;
  requestId?: string;
  assignmentId?: string;
  offerId?: string;
  proposalId?: string;
  callId?: string;
  expiresAt?: string | null;
  createdAt: string;
}

export interface CallSessionResponse {
  id: string;
  request_id: string;
  caller_user_id: string;
  receiver_user_id: string;
  is_caller: boolean;
  caller_name?: string;
  receiver_name?: string;
  call_status: string;
  session_version: number;
  ice_servers: unknown[];
  ringing_at?: string | null;
  ring_expires_at?: string | null;
  accepted_at?: string | null;
  connected_at?: string | null;
}

export interface ServerCapabilitiesResponse {
  scheduledVisitsEnabled: boolean;
  openMarketplaceEnabled: boolean;
  openDispatchEnabled: boolean;
  liveLocationRedisEnabled: boolean;
  guardianNightPolicyEnabled: boolean;
  walletProviderEnabled: boolean;
  ordersAccepting: boolean;
  pausedMessage: string | null;
  serverTime: string;
}
