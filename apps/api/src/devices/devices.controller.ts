import { Body, Controller, Delete, ForbiddenException, HttpCode, Post, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';

class DeviceDto {
  @IsString() @MinLength(20) @MaxLength(4096) token!: string;
  @IsIn(['android', 'ios', 'web']) platform!: 'android' | 'ios' | 'web';
  @IsOptional() @IsString() @MaxLength(120) deviceId?: string;
  @IsOptional() @IsIn(['PATIENT_APP', 'NURSE_APP']) appType?: 'PATIENT_APP' | 'NURSE_APP';
}

class TokenDto {
  @IsOptional() @IsString() @MinLength(20) @MaxLength(4096) token?: string;
  @IsOptional() @IsString() @MaxLength(120) deviceId?: string;
  @IsOptional() @IsIn(['PATIENT_APP', 'NURSE_APP']) appType?: 'PATIENT_APP' | 'NURSE_APP';
}

/**
 * FCM device registration with strict role/app isolation.
 * A token belongs to one (user, role, appType, deviceId) binding; switching accounts
 * on the same device+app deactivates previous user tokens for that device+app.
 */
@Controller('v1/devices')
@UseGuards(AuthGuard)
export class DevicesController {
  constructor(private readonly db: DbService) {}

  @Post()
  @HttpCode(204)
  async register(@Request() r: AuthRequest, @Body() dto: DeviceDto) {
    requireAnyRole(r.user!, ['PATIENT', 'NURSE']);
    const role = r.user!.role;
    const expectedApp = role === 'NURSE' ? 'NURSE_APP' : 'PATIENT_APP';
    if (dto.appType && dto.appType !== expectedApp) {
      throw new ForbiddenException({ code: 'ROLE_APP_MISMATCH' });
    }
    const appType = dto.appType ?? expectedApp;
    const deviceId = dto.deviceId?.trim() || null;
    const sessionId = r.user!.deviceSessionId ?? null;

    await this.db.transaction(async c => {
      if (deviceId) {
        await c.query(
          `UPDATE device_tokens
           SET active_status = 'LOGOUT', updated_at = now()
           WHERE device_id = $1 AND app_type = $2 AND user_id <> $3 AND token <> $4 AND active_status = 'ACTIVE'`,
          [deviceId, appType, r.user!.id, dto.token],
        );
      }

      await c.query(
        `INSERT INTO device_tokens(user_id, token, platform, device_id, app_type, role, session_id, active_status, last_seen_at, updated_at)
         VALUES($1, $2, $3, $4, $5, $6, $7, 'ACTIVE', now(), now())
         ON CONFLICT(token) DO UPDATE SET
           user_id = EXCLUDED.user_id,
           platform = EXCLUDED.platform,
           device_id = COALESCE(EXCLUDED.device_id, device_tokens.device_id),
           app_type = EXCLUDED.app_type,
           role = EXCLUDED.role,
           session_id = COALESCE(EXCLUDED.session_id, device_tokens.session_id),
           active_status = 'ACTIVE',
           last_seen_at = now(),
           updated_at = now()`,
        [r.user!.id, dto.token, dto.platform, deviceId, appType, role, sessionId],
      );
    });
  }

  @Delete()
  @HttpCode(204)
  async unregister(@Request() r: AuthRequest, @Body() dto: TokenDto) {
    requireAnyRole(r.user!, ['PATIENT', 'NURSE']);
    if (dto.token) {
      await this.db.query(
        `UPDATE device_tokens SET active_status = 'LOGOUT', updated_at = now()
         WHERE token = $1 AND user_id = $2`,
        [dto.token, r.user!.id],
      );
      return;
    }
    if (dto.deviceId) {
      const appType = dto.appType ?? (r.user!.role === 'NURSE' ? 'NURSE_APP' : 'PATIENT_APP');
      await this.db.query(
        `UPDATE device_tokens SET active_status = 'LOGOUT', updated_at = now()
         WHERE user_id = $1 AND device_id = $2 AND app_type = $3`,
        [r.user!.id, dto.deviceId, appType],
      );
    }
  }
}
