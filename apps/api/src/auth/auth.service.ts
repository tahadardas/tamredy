import { createHmac, randomBytes, randomInt, randomUUID, timingSafeEqual, createHash, scryptSync } from 'node:crypto';
import { Injectable, UnauthorizedException, HttpException, ForbiddenException, Optional } from '@nestjs/common';
import jwt from 'jsonwebtoken';
import { DbService } from '../db/db.service.js';
import { invalid } from '../common/errors.js';
import { VerificationProvider, VerificationChannel } from './verification-provider.js';

export const OTP_TTL_SECONDS = 300;
export const OTP_MAX_ATTEMPTS = 5;
export const OTP_MAX_PER_WINDOW = 3;
export const ACCESS_TTL_SECONDS = 900;
export const REFRESH_TTL_DAYS = 180; // 6 months sliding window for trusted devices
const PHONE = /^\+[1-9]\d{7,14}$/;

/** Real SMS delivery must be a licensed gateway; nothing is sent in this build. */
export abstract class SmsProvider { abstract send(phone: string, text: string): Promise<void>; }
@Injectable()
export class DevConsoleSms extends SmsProvider {
  async send(phone: string, text: string): Promise<void> {
    if (process.env.NODE_ENV !== 'development') throw new HttpException({ code: 'SMS_PROVIDER_NOT_CONFIGURED' }, 503);
    console.log(`[DEV SMS to ${phone}] ${text}`); // development only; never enabled elsewhere
  }
}

function secret(): string {
  const s = process.env.JWT_SECRET;
  if (!s || s.length < 32) throw new Error('JWT_SECRET >=32 characters required');
  return s;
}
export const hashCode = (phone: string, code: string) => createHmac('sha256', secret()).update(`otp:${phone}:${code}`).digest('hex');
export const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');
/** Interim mode until an SMS gateway exists: 'password' (default) or 'otp'. */
export const authMode = () => (process.env.AUTH_MODE ?? 'password') === 'otp' ? 'otp' : 'password';
export const MAX_FAILED_LOGINS = 5;
export const LOCK_MINUTES = 15;
const SCRYPT_N = 16384;
export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  return `scrypt$${SCRYPT_N}$${salt.toString('base64')}$${scryptSync(password, salt, 32, { N: SCRYPT_N }).toString('base64')}`;
}
export function verifyPassword(password: string, stored: string | null): boolean {
  const [alg, n, salt, hash] = (stored ?? '').split('$');
  if (alg !== 'scrypt' || !n || !salt || !hash) { scryptSync(password, 'x', 32, { N: SCRYPT_N }); return false; } // keep timing similar
  const a = scryptSync(password, Buffer.from(salt, 'base64'), 32, { N: Number(n) });
  const b = Buffer.from(hash, 'base64');
  return a.length === b.length && timingSafeEqual(a, b);
}
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
/** Initial password for accounts created by staff (editable in settings, default 123456). The user must change it at first login. */
export async function defaultPasswordFor(db: { query: (s: string, p?: unknown[]) => Promise<any> }): Promise<string> {
  const v = (await db.query(`SELECT value->>'defaultPassword' AS p FROM app_settings WHERE key='security'`).catch(() => ({ rows: [] }))).rows[0]?.p;
  return typeof v === 'string' && v.length >= 6 ? v : '123456';
}
export const generatePassword = (len = 10) => Array.from({ length: len }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
const safeEq = (a: string, b: string) => a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

@Injectable()
export class AuthService {
  constructor(
    private readonly db: DbService,
    private readonly sms: SmsProvider,
    @Optional() private readonly verificationProvider?: VerificationProvider,
  ) {}

  /** Upserts device session for trusted persistent logins. */
  async upsertDeviceSession(
    c: { query: (sql: string, p?: unknown[]) => Promise<any> },
    userId: string,
    deviceId?: string,
    deviceName?: string,
    platform?: string,
    appKind?: string,
  ): Promise<string | undefined> {
    if (!deviceId) return undefined;
    try {
      const res = await c.query(`
        INSERT INTO device_sessions(user_id, device_id, device_name, platform, app_kind, last_seen_at)
        VALUES($1, $2, $3, coalesce($4, 'android'), $5, now())
        ON CONFLICT (user_id, device_id)
        DO UPDATE SET
          device_name = coalesce(EXCLUDED.device_name, device_sessions.device_name),
          platform = coalesce(EXCLUDED.platform, device_sessions.platform),
          app_kind = coalesce(EXCLUDED.app_kind, device_sessions.app_kind),
          revoked_at = NULL,
          last_seen_at = now()
        RETURNING id
      `, [userId, deviceId, deviceName ?? null, platform ?? 'android', appKind ?? null]);
      return res.rows[0]?.id;
    } catch {
      if (process.env.NODE_ENV === 'production') throw new Error('DEVICE_SESSION_PERSISTENCE_FAILED');
      // Development-only compatibility while a local migration is pending.
      return undefined;
    }
  }

  /** Interim login for staff-provisioned accounts (AUTH_MODE=password). */
  async login(phone: string, password: string, deviceMeta?: { deviceId?: string; deviceName?: string; platform?: string }) {
    if (authMode() !== 'password') throw new HttpException({ code: 'AUTH_MODE_OTP' }, 404);
    if (!PHONE.test(phone) || typeof password !== 'string' || password.length < 6 || password.length > 128) throw new UnauthorizedException({ code: 'LOGIN_INVALID' });
    return this.db.transaction(async c => {
      const u = (await c.query('SELECT id,role,status,password_hash,failed_logins,locked_until,must_change_password,temporary_password_expires_at FROM users WHERE phone_e164=$1 FOR UPDATE', [phone])).rows[0];
      const ok = verifyPassword(password, u?.password_hash ?? null);
      if (!u || u.status !== 'ACTIVE') throw new UnauthorizedException({ code: 'LOGIN_INVALID' });
      if (u.locked_until && new Date(u.locked_until) > new Date()) throw new HttpException({ code: 'ACCOUNT_LOCKED' }, 429);
      if (!ok) {
        const locked = u.failed_logins + 1 >= MAX_FAILED_LOGINS;
        await c.query(`UPDATE users SET failed_logins=$2,locked_until=CASE WHEN $3::boolean THEN now()+($4||' minutes')::interval END WHERE id=$1`,
          [u.id, locked ? 0 : u.failed_logins + 1, locked, String(LOCK_MINUTES)]);
        await c.query('COMMIT'); await c.query('BEGIN');
        throw new UnauthorizedException({ code: 'LOGIN_INVALID' });
      }
      if (u.temporary_password_expires_at && new Date(u.temporary_password_expires_at) <= new Date()) {
        throw new UnauthorizedException({ code: 'LOGIN_INVALID' });
      }
      await c.query('UPDATE users SET failed_logins=0,locked_until=NULL WHERE id=$1', [u.id]);
      const dsi = await this.upsertDeviceSession(c, u.id, deviceMeta?.deviceId, deviceMeta?.deviceName, deviceMeta?.platform, u.role);
      return { ...(await this.issue(c, u.id, u.role, randomUUID(), dsi)), mustChangePassword: !!u.must_change_password };
    });
  }

  /** Starts a login. Always answers the same way so phone numbers cannot be enumerated. */
  async requestOtp(phone: string, channel: VerificationChannel = 'SMS'): Promise<{ expiresInSeconds: number; channel: VerificationChannel }> {
    if (authMode() !== 'otp') throw new HttpException({ code: 'OTP_DISABLED_PASSWORD_MODE' }, 404);
    if (!PHONE.test(phone)) invalid('phone must be E.164, e.g. +963911111111');
    const recent = await this.db.query(`SELECT count(*)::int AS n FROM otp_challenges WHERE phone_e164=$1 AND created_at>now()-interval '10 minutes'`, [phone]);
    if (recent.rows[0].n >= OTP_MAX_PER_WINDOW) throw new HttpException({ code: 'OTP_RATE_LIMITED' }, 429);
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    await this.db.query(`INSERT INTO otp_challenges(phone_e164,code_hash,expires_at) VALUES($1,$2,now()+($3||' seconds')::interval)`,
      [phone, hashCode(phone, code), String(OTP_TTL_SECONDS)]);
    if (this.verificationProvider) {
      await this.verificationProvider.sendOtp(phone, code, 'auth');
    } else {
      await this.sms.send(phone, `رمز تمريضي: ${code}`);
    }
    return { expiresInSeconds: OTP_TTL_SECONDS, channel };
  }

  async verifyOtp(phone: string, code: string, deviceMeta?: { deviceId?: string; deviceName?: string; platform?: string }) {
    if (authMode() !== 'otp') throw new HttpException({ code: 'OTP_DISABLED_PASSWORD_MODE' }, 404);
    if (!PHONE.test(phone) || !/^\d{6}$/.test(code)) throw new UnauthorizedException({ code: 'OTP_INVALID' });
    return this.db.transaction(async c => {
      const ch = await c.query(`SELECT id,code_hash,attempts FROM otp_challenges WHERE phone_e164=$1 AND consumed_at IS NULL AND expires_at>now()
        ORDER BY created_at DESC LIMIT 1 FOR UPDATE`, [phone]);
      const row = ch.rows[0];
      if (!row || row.attempts >= OTP_MAX_ATTEMPTS) throw new UnauthorizedException({ code: 'OTP_INVALID' });
      if (!safeEq(row.code_hash, hashCode(phone, code))) {
        await c.query('UPDATE otp_challenges SET attempts=attempts+1 WHERE id=$1', [row.id]);
        await c.query('COMMIT'); await c.query('BEGIN'); // persist the failed attempt, then reject
        throw new UnauthorizedException({ code: 'OTP_INVALID' });
      }
      await c.query('UPDATE otp_challenges SET consumed_at=now() WHERE id=$1', [row.id]);
      // First login creates a PATIENT account. Nurse/admin accounts are provisioned by staff.
      await c.query(`INSERT INTO users(phone_e164,role) VALUES($1,'PATIENT') ON CONFLICT (phone_e164) DO NOTHING`, [phone]);
      const u = (await c.query('SELECT id,role,status FROM users WHERE phone_e164=$1', [phone])).rows[0];
      if (u.status !== 'ACTIVE') throw new ForbiddenException({ code: 'ACCOUNT_INACTIVE' });
      if (!['PATIENT', 'NURSE'].includes(u.role)) throw new ForbiddenException({ code: 'MFA_REQUIRED' });
      const dsi = await this.upsertDeviceSession(c, u.id, deviceMeta?.deviceId, deviceMeta?.deviceName, deviceMeta?.platform, u.role);
      return this.issue(c, u.id, u.role, randomUUID(), dsi);
    });
  }

  async refresh(refreshToken: string, deviceId?: string) {
    const h = hashToken(refreshToken ?? '');
    return this.db.transaction(async c => {
      const owner = (await c.query('SELECT user_id FROM refresh_tokens WHERE token_hash=$1', [h])).rows[0];
      if (!owner) throw new UnauthorizedException({ code: 'REFRESH_INVALID' });
      const u = (await c.query(
        'SELECT id,role,status,auth_version,temporary_password_expires_at FROM users WHERE id=$1 FOR UPDATE',
        [owner.user_id],
      )).rows[0];
      if (!u || u.status !== 'ACTIVE') throw new UnauthorizedException({ code: 'ACCOUNT_INACTIVE' });
      if (u.temporary_password_expires_at && new Date(u.temporary_password_expires_at) <= new Date()) {
        throw new UnauthorizedException({ code: 'REFRESH_EXPIRED' });
      }

      const r = (await c.query(`
        SELECT rt.*
        FROM refresh_tokens rt
        WHERE rt.token_hash = $1
        FOR UPDATE
      `, [h])).rows[0];

      if (!r) throw new UnauthorizedException({ code: 'REFRESH_INVALID' });

      // Check if associated device session was revoked
      if (r.device_session_id) {
        const ds = (await c.query('SELECT revoked_at, device_id FROM device_sessions WHERE id=$1 AND user_id=$2', [r.device_session_id, r.user_id])).rows[0];
        if (!ds || ds.revoked_at || !deviceId || deviceId !== ds.device_id) throw new UnauthorizedException({ code: 'SESSION_REVOKED' });
      }

      if (r.used_at || r.revoked_at) {
        // Replay of an already-rotated or revoked token: assume theft and kill the whole family and device session.
        await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE family_id=$1', [r.family_id]);
        if (r.device_session_id) {
          await c.query('UPDATE device_sessions SET revoked_at=coalesce(revoked_at,now()) WHERE id=$1', [r.device_session_id]).catch(() => {});
        }
        await c.query('COMMIT'); await c.query('BEGIN');
        throw new UnauthorizedException({ code: 'REFRESH_REUSED' });
      }

      if (new Date(r.expires_at) <= new Date()) throw new UnauthorizedException({ code: 'REFRESH_EXPIRED' });

      // Sliding session update: extend device session last_seen_at
      let dsi = r.device_session_id;
      if (deviceId && !dsi) {
        dsi = (await this.upsertDeviceSession(c, u.id, deviceId, undefined, undefined, u.role)) ?? dsi;
      } else if (dsi) {
        await c.query('UPDATE device_sessions SET last_seen_at=now() WHERE id=$1', [dsi]).catch(() => {});
      }

      const nextRefreshToken = randomBytes(32).toString('base64url');
      const nextHash = hashToken(nextRefreshToken);

      await c.query('UPDATE refresh_tokens SET used_at=now(), replaced_by_hash=$2 WHERE id=$1', [r.id, nextHash]);

      await c.query(`INSERT INTO refresh_tokens(user_id,family_id,token_hash,expires_at,device_session_id)
        VALUES($1,$2,$3,now()+($4||' days')::interval,$5)`,
        [u.id, r.family_id, nextHash, String(REFRESH_TTL_DAYS), dsi]);

      const accessToken = jwt.sign({ dsi, av: u.auth_version }, secret(), {
        algorithm: 'HS256', subject: u.id, expiresIn: ACCESS_TTL_SECONDS,
        issuer: process.env.JWT_ISSUER ?? 'tamreedy-api', audience: process.env.JWT_AUDIENCE ?? 'tamreedy-mobile',
      });
      return { accessToken, refreshToken: nextRefreshToken, expiresInSeconds: ACCESS_TTL_SECONDS, role: u.role };
    });
  }

  async logout(refreshToken: string) {
    const h = hashToken(refreshToken ?? '');
    await this.db.transaction(async c => {
      const r = (await c.query('SELECT user_id, family_id, device_session_id FROM refresh_tokens WHERE token_hash=$1', [h])).rows[0];
      if (r) {
        await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE family_id=$1', [r.family_id]);
        if (r.device_session_id) {
          await c.query('UPDATE device_sessions SET revoked_at=coalesce(revoked_at,now()) WHERE id=$1', [r.device_session_id]).catch(() => {});
          await c.query(`UPDATE device_tokens SET active_status='REVOKED', updated_at=now() WHERE session_id=$1`, [r.device_session_id]).catch(() => {});
        }
      }
    });
    return { ok: true };
  }

  async issue(
    c: { query: (sql: string, p?: unknown[]) => Promise<any> },
    userId: string,
    role: string,
    family: string,
    deviceSessionId?: string,
  ) {
    const refreshToken = randomBytes(32).toString('base64url');
    await c.query(`INSERT INTO refresh_tokens(user_id,family_id,token_hash,expires_at,device_session_id)
      VALUES($1,$2,$3,now()+($4||' days')::interval,$5)`,
      [userId, family, hashToken(refreshToken), String(REFRESH_TTL_DAYS), deviceSessionId ?? null]);
    const { auth_version: av } = (await c.query('SELECT auth_version FROM users WHERE id=$1', [userId])).rows[0];
    const accessToken = jwt.sign({ dsi: deviceSessionId, av }, secret(), {
      algorithm: 'HS256', subject: userId, expiresIn: ACCESS_TTL_SECONDS,
      issuer: process.env.JWT_ISSUER ?? 'tamreedy-api', audience: process.env.JWT_AUDIENCE ?? 'tamreedy-mobile',
    });
    return { accessToken, refreshToken, expiresInSeconds: ACCESS_TTL_SECONDS, role };
  }
}
