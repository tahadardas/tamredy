import { Injectable } from '@nestjs/common';

export interface AssignmentLocationPolicyInput {
  assignmentStatus: string;
  requestStatus: string;
  departureWindowOpen: boolean;
}

/**
 * BUG-023: Authorizes exact patient address & GPS coordinate visibility for nurses.
 * Exact address/coordinates are exposed ONLY during an active visit or within the
 * active departure window; historical or far-future scheduled bookings expose area only.
 */
@Injectable()
export class AssignmentLocationAuthorizationService {
  canExposeExactLocation(input: AssignmentLocationPolicyInput): boolean {
    if (input.assignmentStatus === 'ACTIVE') {
      return ['ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE'].includes(input.requestStatus);
    }
    if (input.assignmentStatus === 'RESERVED') {
      return input.departureWindowOpen && input.requestStatus === 'ASSIGNED';
    }
    return false;
  }

  sanitizeLocationFields<T extends Record<string, any>>(row: T, areaName?: string | null): T {
    const authorized = this.canExposeExactLocation({
      assignmentStatus: String(row.assignment_status ?? ''),
      requestStatus: String(row.request_status ?? row.status ?? ''),
      departureWindowOpen: row.departure_window_open === true,
    });
    if (authorized) {
      return {
        ...row,
        exact_location_authorized: true,
        area_name: areaName ?? row.area_name ?? 'ضمن نطاق الخدمة',
      };
    }
    return {
      ...row,
      exact_location_authorized: false,
      area_name: areaName ?? row.area_name ?? 'ضمن نطاق الخدمة',
      address_text: null,
      latitude: null,
      longitude: null,
      patient_lat: null,
      patient_lng: null,
    };
  }
}
