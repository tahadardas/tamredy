import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { IsString, Matches, MaxLength } from 'class-validator';
import { AuthService } from './auth.service.js';

class OtpRequestDto { @IsString() @MaxLength(20) phone!: string; }
class OtpVerifyDto { @IsString() @MaxLength(20) phone!: string; @IsString() @Matches(/^\d{6}$/) code!: string; }
class LoginDto { @IsString() @MaxLength(20) phone!: string; @IsString() @MaxLength(128) password!: string; }
class RefreshDto { @IsString() @MaxLength(200) refreshToken!: string; }

/** Public endpoints (no AuthGuard). Per-phone limits live in the service;
 *  add an IP-level throttler at the gateway before exposing publicly. */
@Controller('v1/auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  @Post('login') @HttpCode(200) login(@Body() b: LoginDto) { return this.auth.login(b.phone, b.password); }
  @Post('otp/request') @HttpCode(202) request(@Body() b: OtpRequestDto) { return this.auth.requestOtp(b.phone); }
  @Post('otp/verify') @HttpCode(200) verify(@Body() b: OtpVerifyDto) { return this.auth.verifyOtp(b.phone, b.code); }
  @Post('refresh') @HttpCode(200) refresh(@Body() b: RefreshDto) { return this.auth.refresh(b.refreshToken); }
  @Post('logout') @HttpCode(200) logout(@Body() b: RefreshDto) { return this.auth.logout(b.refreshToken); }
}
