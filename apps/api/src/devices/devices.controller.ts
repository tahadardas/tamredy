import { Body, Controller, Delete, HttpCode, Post, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';

class DeviceDto {
  @IsString() @MinLength(20) @MaxLength(4096) token!: string;
  @IsIn(['android', 'ios', 'web']) platform!: 'android' | 'ios' | 'web';
}
class TokenDto { @IsString() @MinLength(20) @MaxLength(4096) token!: string; }

/** FCM device registration. A token belongs to exactly one user: a new login on the same device takes it over. */
@Controller('v1/devices') @UseGuards(AuthGuard)
export class DevicesController {
  constructor(private readonly db: DbService) {}
  @Post() @HttpCode(204) async register(@Request() r: AuthRequest, @Body() dto: DeviceDto) {
    requireAnyRole(r.user!, ['PATIENT', 'NURSE']);
    await this.db.query(`INSERT INTO device_tokens(user_id,token,platform) VALUES($1,$2,$3)
      ON CONFLICT(token) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform,last_seen_at=now()`, [r.user!.id, dto.token, dto.platform]);
  }
  @Delete() @HttpCode(204) async unregister(@Request() r: AuthRequest, @Body() dto: TokenDto) {
    await this.db.query('DELETE FROM device_tokens WHERE token=$1 AND user_id=$2', [dto.token, r.user!.id]);
  }
}
