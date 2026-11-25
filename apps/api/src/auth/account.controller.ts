import { Body, Controller, Get, HttpCode, HttpException, Param, ParseUUIDPipe, Post, Request, UseGuards } from '@nestjs/common';
import { IsString, MaxLength } from 'class-validator';
import { randomUUID } from 'node:crypto';
import { AuthGuard, AuthRequest } from './auth.guard.js';
import { permissionsFor } from './permissions.js';
import { AuthService, defaultPasswordFor, hashPassword, verifyPassword } from './auth.service.js';
import { DbService } from '../db/db.service.js';

class ChangePasswordDto { @IsString() @MaxLength(128) currentPassword!: string; @IsString() @MaxLength(128) newPassword!: string; }

/** "Who am I" and password change. These are the only routes usable while a password change is still required. */
@Controller('v1/auth') @UseGuards(AuthGuard)
export class AccountController {
  constructor(private readonly db: DbService, private readonly auth: AuthService) {}

  @Get('me') async me(@Request() r: AuthRequest) {
    const u = (await this.db.query('SELECT id,role,display_name,phone_e164,must_change_password FROM users WHERE id=$1', [r.user!.id])).rows[0];
    return { ...u, mustChangePassword: u.must_change_password, permissions: permissionsFor(u.role) };
  }

  @Get('sessions') async sessions(@Request() r: AuthRequest) {
    const s = await this.db.query(`
      SELECT id, device_id, device_name, platform, app_kind, trusted, revoked_at, last_seen_at, created_at
      FROM device_sessions
      WHERE user_id = $1
      ORDER BY last_seen_at DESC
    `, [r.user!.id]).catch(() => ({ rows: [] }));
    return s.rows;
  }

  @Post('sessions/:id/revoke') @HttpCode(200) async revokeSession(@Request() r: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    await this.db.transaction(async c => {
      await c.query('UPDATE device_sessions SET revoked_at=coalesce(revoked_at,now()) WHERE id=$1 AND user_id=$2', [id, r.user!.id]);
      await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE device_session_id=$1 AND user_id=$2', [id, r.user!.id]);
    });
    return { ok: true };
  }

  @Post('change-password') @HttpCode(200) async change(@Request() r: AuthRequest, @Body() d: ChangePasswordDto) {
    const staff = r.user!.role === 'ADMIN' || r.user!.role === 'CLINICAL_REVIEWER';
    const sec = (await this.db.query(`SELECT value FROM app_settings WHERE key='security'`)).rows[0]?.value;
    const min = staff ? Number(sec?.passwordMinLength ?? 12) : 8;
    return this.db.transaction(async c => {
      const u = (await c.query('SELECT id,role,phone_e164,password_hash,temporary_password_expires_at FROM users WHERE id=$1 FOR UPDATE', [r.user!.id])).rows[0];
      if (u.temporary_password_expires_at && new Date(u.temporary_password_expires_at) <= new Date()) {
        throw new HttpException({ code: 'WRONG_PASSWORD' }, 400);
      }
      if (!verifyPassword(d.currentPassword, u.password_hash)) throw new HttpException({ code: 'WRONG_PASSWORD' }, 400);
      const weak = d.newPassword.length < min || d.newPassword === d.currentPassword || d.newPassword === await defaultPasswordFor(this.db)
        || u.phone_e164.replace(/\D/g, '').includes(d.newPassword) || /^(.)\1+$/.test(d.newPassword);
      if (weak) throw new HttpException({ code: 'WEAK_PASSWORD', min }, 400);
      await c.query('UPDATE users SET password_hash=$2,must_change_password=false,auth_version=gen_random_uuid(),temporary_password_expires_at=NULL,failed_logins=0,locked_until=NULL WHERE id=$1', [u.id, hashPassword(d.newPassword)]);
      await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [u.id]); // every other session ends
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id) VALUES($1,'user.password_changed','user',$1)`, [u.id]);
      return this.auth.issue(c, u.id, u.role, randomUUID(), r.user!.deviceSessionId);
    });
  }
}
