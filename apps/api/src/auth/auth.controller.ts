import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { IsIn, IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { AuthService } from './auth.service.js';
import { VerificationChannel } from './verification-provider.js';
import { Throttle } from '@nestjs/throttler';

class OtpRequestDto {
  @IsString() @MaxLength(20) phone!: string;
  @IsOptional() @IsIn(['SMS', 'WHATSAPP', 'TEST']) channel?: VerificationChannel;
}
class OtpVerifyDto {
  @IsString() @MaxLength(20) phone!: string;
  @IsString() @Matches(/^\d{6}$/) code!: string;
  @IsOptional() @IsString() @MaxLength(100) deviceId?: string;
  @IsOptional() @IsString() @MaxLength(100) deviceName?: string;
  @IsOptional() @IsString() @MaxLength(20) platform?: string;
}
class LoginDto {
  @IsString() @MaxLength(20) phone!: string;
  @IsString() @MaxLength(128) password!: string;
  @IsOptional() @IsString() @MaxLength(100) deviceId?: string;
  @IsOptional() @IsString() @MaxLength(100) deviceName?: string;
  @IsOptional() @IsString() @MaxLength(20) platform?: string;
}
class RefreshDto {
  @IsString() @MaxLength(200) refreshToken!: string;
  @IsOptional() @IsString() @MaxLength(100) deviceId?: string;
}
class LogoutDto {
  @IsOptional() @IsString() @MaxLength(200) refreshToken?: string;
  @IsOptional() @IsString() @MaxLength(100) deviceId?: string;
}

/** Public endpoints (no AuthGuard). Per-phone limits live in the service;
 *  add an IP-level throttler at the gateway before exposing publicly. */
@Controller('v1/auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('login') @HttpCode(200) login(@Body() b: LoginDto) {
    return this.auth.login(b.phone, b.password, { deviceId: b.deviceId, deviceName: b.deviceName, platform: b.platform });
  }
  @Throttle({ default: { limit: 3, ttl: 600_000 } })
  @Post('otp/request') @HttpCode(202) request(@Body() b: OtpRequestDto) { return this.auth.requestOtp(b.phone, b.channel); }
  @Throttle({ default: { limit: 8, ttl: 600_000 } })
  @Post('otp/verify') @HttpCode(200) verify(@Body() b: OtpVerifyDto) {
    return this.auth.verifyOtp(b.phone, b.code, { deviceId: b.deviceId, deviceName: b.deviceName, platform: b.platform });
  }
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('refresh') @HttpCode(200) refresh(@Body() b: RefreshDto) {
    return this.auth.refresh(b.refreshToken, b.deviceId);
  }
  @Post('logout') @HttpCode(200) logout(@Body() b: LogoutDto) {
    return this.auth.logout(b.refreshToken ?? '');
  }
}
