import { CanActivate, ExecutionContext, Injectable, UnauthorizedException, ForbiddenException } from '@nestjs/common';
import jwt from 'jsonwebtoken';
import type { JwtPayload } from 'jsonwebtoken';
const { verify } = jwt;
import { DbService } from '../db/db.service.js';
export type Role = 'PATIENT' | 'NURSE' | 'ADMIN' | 'CLINICAL_REVIEWER';
export interface AuthUser { id: string; role: Role; }
export interface AuthRequest { headers: { authorization?: string }; user?: AuthUser; url?: string }
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly db: DbService) {}
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    const token = /^Bearer (.+)$/i.exec(request.headers.authorization ?? '')?.[1];
    if (!token) throw new UnauthorizedException('AUTH_REQUIRED');
    if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must be >=32 characters');
    let payload: JwtPayload;
    try {
      const decoded = verify(token, process.env.JWT_SECRET, {
        algorithms: ['HS256'], issuer: process.env.JWT_ISSUER ?? 'tamreedy-api',
        audience: process.env.JWT_AUDIENCE ?? 'tamreedy-mobile',
      });
      if (typeof decoded === 'string') throw new Error('invalid JWT');
      payload = decoded;
    } catch { throw new UnauthorizedException('INVALID_TOKEN'); }
    if (typeof payload.sub !== 'string') throw new UnauthorizedException('INVALID_SUBJECT');
    const result = await this.db.query('SELECT id,role,status,must_change_password,auth_version,temporary_password_expires_at FROM users WHERE id=$1', [payload.sub]);
    const row = result.rows[0];
    if (!row || row.status !== 'ACTIVE') throw new UnauthorizedException('ACCOUNT_INACTIVE');
    if ((payload.av ?? null) !== (row.auth_version ?? null) ||
        (row.temporary_password_expires_at && new Date(row.temporary_password_expires_at) <= new Date())) {
      throw new UnauthorizedException({ code: 'SESSION_REVOKED' });
    }
    await requireActiveDeviceSession(this.db, row.id, payload.dsi);
    // Until the initial password is replaced, only the auth routes (me / change-password) work.
    if (row.must_change_password && !(request.url ?? '').startsWith('/v1/auth/')) throw new ForbiddenException({ code: 'PASSWORD_CHANGE_REQUIRED' });
    request.user = { id: row.id, role: row.role as Role };
    return true;
  }
}
export async function requireActiveDeviceSession(
  db: DbService,
  userId: string,
  sessionId: unknown,
): Promise<void> {
  if (sessionId === undefined || sessionId === null) {
    if (process.env.NODE_ENV === 'production' && process.env.ALLOW_LEGACY_UNBOUND_SESSIONS !== 'true') {
      throw new UnauthorizedException({ code: 'DEVICE_SESSION_REQUIRED' });
    }
    return;
  }
  if (typeof sessionId !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(sessionId)) {
    throw new UnauthorizedException({ code: 'SESSION_REVOKED' });
  }
  const result = await db.query(
    'SELECT 1 FROM device_sessions WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL',
    [sessionId, userId],
  );
  if (!result.rows.length) throw new UnauthorizedException({ code: 'SESSION_REVOKED' });
}
export function requireRole(user: AuthUser, role: Role): void {
  if (user.role !== role) throw new ForbiddenException({code:'ROLE_NOT_ALLOWED'});
}
export function requireAnyRole(user: AuthUser, roles: Role[]): void {
  if (!roles.includes(user.role)) throw new ForbiddenException({code:'ROLE_NOT_ALLOWED'});
}
