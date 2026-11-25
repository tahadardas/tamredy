import { ForbiddenException } from '@nestjs/common';
import type { AuthUser, Role } from './auth.guard.js';

export const permissions = [
  'health_record.read_own','health_record.write_own','health_record.read_assigned','health_record.write_assigned',
  'clinical_review.queue','clinical_review.evidence','clinical_review.decide',
  'credential.review','platform.admin','safety.respond','financial.admin',
] as const;
export type Permission = (typeof permissions)[number];

const ROLE_PERMISSIONS: Readonly<Record<Role, ReadonlySet<Permission>>> = {
  PATIENT: new Set(['health_record.read_own','health_record.write_own']),
  NURSE: new Set(['health_record.read_assigned','health_record.write_assigned','safety.respond']),
  CLINICAL_REVIEWER: new Set(['clinical_review.queue','clinical_review.evidence','clinical_review.decide','credential.review']),
  ADMIN: new Set(['platform.admin','financial.admin','safety.respond']),
};

export function requirePermission(user: AuthUser, permission: Permission): void {
  if (!ROLE_PERMISSIONS[user.role].has(permission)) {
    throw new ForbiddenException({code:'PERMISSION_DENIED',permission});
  }
}

export function permissionsFor(role: Role): readonly Permission[] {
  return [...ROLE_PERMISSIONS[role]];
}
