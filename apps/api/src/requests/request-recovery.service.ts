import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { missing } from '../common/errors.js';

const PATIENT_RECOVERABLE_STATUSES = [
  'SCHEDULED', 'OFFERING', 'OPEN_FOR_PROPOSALS', 'ASSIGNED',
  'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'UNFULFILLED', 'AWAITING_RECOVERY_CHOICE',
] as const;

@Injectable()
export class RequestRecoveryService {
  constructor(private readonly db: DbService) {}

  async patientState(patientUserId: string) {
    const active = await this.db.query(`
      SELECT cr.id, cr.status, cr.version, cr.price_amount, cr.currency_code,
        cr.created_at, cr.booking_mode, cr.marketplace_status, cr.open_expires_at,
        cr.latest_acceptable_arrival_at, cr.payment_status, cr.amount_due,cr.clinical_approval_status,
        cr.address_text, ST_Y(cr.location::geometry) AS patient_lat,
        ST_X(cr.location::geometry) AS patient_lng,
        s.id AS service_id, s.title_ar AS service_title, s.code AS service_code,
        s.requires_prescription, b.id AS beneficiary_id, b.display_name AS beneficiary_name,
        sv.appointment_at AS scheduled_at,
        a.id AS assignment_id, a.nurse_id,
        CASE WHEN cr.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE') THEN u.display_name END AS nurse_name,
        NULL::text AS nurse_phone,
        CASE WHEN cr.status='EN_ROUTE' AND nl.recorded_at>statement_timestamp()-coalesce(cr.search_max_location_seconds,120)*interval '1 second'
          THEN ST_Y(nl.location::geometry) END AS nurse_lat,
        CASE WHEN cr.status='EN_ROUTE' AND nl.recorded_at>statement_timestamp()-coalesce(cr.search_max_location_seconds,120)*interval '1 second'
          THEN ST_X(nl.location::geometry) END AS nurse_lng,
        (SELECT count(*)::int FROM marketplace_proposals mp
          WHERE mp.request_id=cr.id AND mp.status='PENDING' AND mp.expires_at>statement_timestamp())
          AS active_proposals_count,
        coalesce((SELECT jsonb_agg(jsonb_build_object(
          'id', cri.id, 'serviceId', cri.service_id, 'quantity', cri.quantity,
          'unitPrice', cri.unit_price, 'expectedMinutes', cri.expected_minutes,
          'status', cri.item_status, 'titleAr', item_service.title_ar
        ) ORDER BY cri.created_at)
        FROM care_request_items cri JOIN services item_service ON item_service.id=cri.service_id
        WHERE cri.request_id=cr.id), '[]'::jsonb) AS items
      FROM care_requests cr
      JOIN services s ON s.id=cr.service_id
      JOIN beneficiaries b ON b.id=cr.beneficiary_id
      LEFT JOIN scheduled_visits sv ON sv.request_id=cr.id
      LEFT JOIN request_assignments a ON a.request_id=cr.id AND a.status IN ('RESERVED','ACTIVE')
      LEFT JOIN nurses n ON n.id=a.nurse_id
      LEFT JOIN users u ON u.id=n.user_id
      LEFT JOIN nurse_locations nl ON nl.nurse_id=a.nurse_id
      WHERE cr.requester_user_id=$1 AND cr.status=ANY($2::text[])
      ORDER BY coalesce(sv.appointment_at,cr.created_at),cr.id
    `, [patientUserId, [...PATIENT_RECOVERABLE_STATUSES]]);

    const unpaid = await this.db.query(`
      SELECT cr.id,cr.status,cr.version,cr.booking_mode,cr.marketplace_status,cr.clinical_approval_status,
        cr.payment_status,cr.amount_due,cr.tip_amount,cr.currency_code,cr.billed_at,cr.created_at,
        s.title_ar AS service_title, b.display_name AS beneficiary_name
      FROM care_requests cr
      JOIN services s ON s.id=cr.service_id
      JOIN beneficiaries b ON b.id=cr.beneficiary_id
      WHERE cr.requester_user_id=$1 AND cr.status='COMPLETED' AND cr.payment_status IN ('DUE','PARTIAL')
      ORDER BY cr.billed_at DESC NULLS LAST,cr.id DESC
    `, [patientUserId]);

    const pendingReviews = await this.db.query(`
      SELECT cr.id AS request_id,v.id AS visit_id,v.completed_at
      FROM care_requests cr
      JOIN request_assignments a ON a.request_id=cr.id
      JOIN visits v ON v.assignment_id=a.id AND v.completed_at IS NOT NULL
      WHERE cr.requester_user_id=$1 AND cr.status='COMPLETED'
        AND NOT EXISTS (SELECT 1 FROM visit_reviews vr
          WHERE vr.visit_id=v.id AND vr.reviewer_user_id=$1 AND vr.reviewer_role='PATIENT')
      ORDER BY v.completed_at DESC LIMIT 20
    `, [patientUserId]);

    return {
      hasActive: active.rows.length > 0,
      request: active.rows[0] ?? null,
      requests: active.rows,
      unpaidInvoices: unpaid.rows,
      pendingReviews: pendingReviews.rows,
      serverTime: new Date().toISOString(),
    };
  }

  async nurseAssignments(nurseUserId: string) {
    const nurse = (await this.db.query(
      'SELECT id,verified,availability_intent,work_status FROM nurses WHERE user_id=$1',
      [nurseUserId],
    )).rows[0];
    if (!nurse) missing();

    const assignments = await this.db.query(`
      SELECT a.id AS assignment_id,a.status AS assignment_status,a.accepted_at AS assigned_at,
        cr.id AS request_id,cr.status AS request_status,cr.version,cr.booking_mode,
        cr.marketplace_status,cr.price_amount,cr.currency_code,cr.commission_bps,
        cr.scheduled_start_at,cr.scheduled_end_at,sv.appointment_at AS scheduled_at,
        facts.departure_window_open, facts.departure_window_open AS exact_location_authorized,
        CASE WHEN facts.departure_window_open THEN cr.address_text END AS address_text,
        CASE WHEN facts.departure_window_open
          THEN ST_Y(cr.location::geometry) END AS patient_lat,
        CASE WHEN facts.departure_window_open
          THEN ST_X(cr.location::geometry) END AS patient_lng,
        s.id AS service_id,s.title_ar AS service_title,s.code AS service_code,s.requires_prescription,
        b.display_name AS beneficiary_name,
        CASE WHEN cr.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE') THEN u.display_name END AS patient_name,
        NULL::text AS patient_phone
      FROM request_assignments a
      JOIN care_requests cr ON cr.id=a.request_id
      JOIN services s ON s.id=cr.service_id
      JOIN beneficiaries b ON b.id=cr.beneficiary_id
      JOIN users u ON u.id=cr.requester_user_id
      LEFT JOIN scheduled_visits sv ON sv.request_id=cr.id
      CROSS JOIN LATERAL (SELECT a.status='ACTIVE' OR (
        a.status='RESERVED' AND cr.status='ASSIGNED' AND a.planned_start_at
          -a.travel_buffer_before_minutes*interval '1 minute'<=statement_timestamp()
      ) AS departure_window_open) facts
      WHERE a.nurse_id=$1 AND a.status IN ('RESERVED','ACTIVE')
        AND cr.status IN ('SCHEDULED','ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE')
      ORDER BY coalesce(sv.appointment_at,cr.scheduled_start_at,a.accepted_at),a.id
    `, [nurse.id]);

    const unpaidInvoices = await this.db.query(`
      SELECT a.id AS assignment_id,i.id AS invoice_id,i.request_id,i.status,
        i.total_amount+i.tip_amount-i.paid_amount AS remaining,i.currency_code,
        cr.version AS request_version,s.title_ar AS service_title,b.display_name AS beneficiary_name
      FROM invoices i
      JOIN visits v ON v.id=i.visit_id
      JOIN request_assignments a ON a.id=v.assignment_id
      JOIN care_requests cr ON cr.id=i.request_id
      JOIN services s ON s.id=cr.service_id
      JOIN beneficiaries b ON b.id=cr.beneficiary_id
      WHERE a.nurse_id=$1 AND i.status IN ('ISSUED','PARTIALLY_PAID')
      ORDER BY i.issued_at DESC,i.id DESC LIMIT 50`, [nurse.id]);

    const enrichedAssignments = assignments.rows.map(row => ({
      ...row,
      allowedActions: this.allowedNurseActions(row.request_status, row.departure_window_open === true),
    }));
    const active = enrichedAssignments.find(row => row.assignment_status === 'ACTIVE')
      ?? enrichedAssignments.find(row => row.departure_window_open === true) ?? null;
    return {
      hasActive: active !== null,
      verified: nurse.verified,
      availability: nurse.availability_intent,
      workStatus: nurse.work_status,
      assignment: active,
      assignments: enrichedAssignments,
      unpaidInvoices: unpaidInvoices.rows,
      serverTime: new Date().toISOString(),
    };
  }

  private allowedNurseActions(requestStatus: string, departureWindowOpen: boolean): string[] {
    switch (requestStatus) {
      case 'ASSIGNED':
        return departureWindowOpen ? ['DEPART', 'SAFE_ABORT'] : [];
      case 'EN_ROUTE':
        return ['ARRIVE', 'UPDATE_LOCATION', 'SAFE_ABORT'];
      case 'ARRIVED':
        return ['START_SERVICE', 'SAFE_ABORT'];
      case 'IN_SERVICE':
        return ['CLINICAL_NOTES', 'SERVICE_OUTCOMES', 'COMPLETE_VISIT', 'SAFE_ABORT'];
      case 'ESCALATED':
        return ['COMPLETE_VISIT', 'SAFE_ABORT'];
      default:
        return [];
    }
  }
}
