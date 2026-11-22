import { BadRequestException, Body, Controller, Get, Param, Post, Query, Request, UseGuards } from '@nestjs/common';
import { IsDateString, IsIn, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { defaultPasswordFor, generatePassword, hashPassword } from '../auth/auth.service.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';

class CreateUserDto {
  @Matches(/^\+[1-9]\d{7,14}$/) phone!: string;
  @IsIn(['PATIENT', 'NURSE', 'ADMIN', 'CLINICAL_REVIEWER']) role!: 'PATIENT' | 'NURSE' | 'ADMIN' | 'CLINICAL_REVIEWER';
  @IsString() @MinLength(2) @MaxLength(80) displayName!: string;
  @IsOptional() @IsString() @MinLength(8) @MaxLength(128) password?: string;
  /** PATIENT: first beneficiary, created with consent confirmed by staff. */
  @IsOptional() @IsString() @MaxLength(80) beneficiaryName?: string;
  /** NURSE: licence submitted for the normal approval queue (never auto-approved). */
  @IsOptional() @IsString() @MaxLength(80) licenseRef?: string;
  @IsOptional() @IsDateString() licenseExpiresAt?: string;
}
class StatusDto { @IsIn(['ACTIVE', 'SUSPENDED']) status!: 'ACTIVE' | 'SUSPENDED'; }

/** Manual account provisioning by an administrator (interim until SMS/OTP onboarding exists).
 *  Passwords are shown exactly once in the response and stored only as scrypt hashes. */
@Controller('v1/admin/users') @UseGuards(AuthGuard)
export class AdminUsersController {
  constructor(private readonly db: DbService) {}

  @Post() async create(@Request() r: AuthRequest, @Body() dto: CreateUserDto) {
    requireRole(r.user!, 'ADMIN');
    if (dto.role === 'NURSE' && !!dto.licenseRef !== !!dto.licenseExpiresAt) throw new BadRequestException({ code: 'LICENSE_FIELDS_TOGETHER' });
    const staff = dto.role === 'ADMIN' || dto.role === 'CLINICAL_REVIEWER';
    const password = dto.password ?? (staff ? generatePassword() : await defaultPasswordFor(this.db)); // staff accounts never get a guessable default
    return this.db.transaction(async c => {
      const exists = await c.query('SELECT 1 FROM users WHERE phone_e164=$1', [dto.phone]);
      if (exists.rowCount) conflict('PHONE_ALREADY_REGISTERED');
      const u = (await c.query(`INSERT INTO users(phone_e164,role,display_name,password_hash,must_change_password,created_by)
        VALUES($1,$2,$3,$4,true,$5) RETURNING id`, [dto.phone, dto.role, dto.displayName, hashPassword(password), r.user!.id])).rows[0];
      if (dto.role === 'PATIENT' && dto.beneficiaryName)
        await c.query(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,$2,'GRANTED')`, [u.id, dto.beneficiaryName]);
      if (dto.role === 'NURSE') {
        const n = (await c.query('INSERT INTO nurses(user_id) VALUES($1) RETURNING id', [u.id])).rows[0];
        if (dto.licenseRef) await c.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at) VALUES($1,$2,$3)`, [n.id, dto.licenseRef, dto.licenseExpiresAt]);
      }
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'user.created','user',$2,$3::jsonb)`,
        [r.user!.id, u.id, JSON.stringify({ role: dto.role, consentConfirmedByStaff: !!dto.beneficiaryName })]);
      return { id: u.id, phone: dto.phone, role: dto.role, temporaryPassword: password, note: 'Shown once. Share securely; the user should change it.' };
    });
  }

  @Get() async list(@Request() r: AuthRequest, @Query('role') role?: string) {
    requireRole(r.user!, 'ADMIN');
    if (role && !['PATIENT', 'NURSE', 'ADMIN', 'CLINICAL_REVIEWER'].includes(role)) throw new BadRequestException({ code: 'INVALID_ROLE' });
    const q = await this.db.query(`SELECT id,phone_e164,role,status,display_name,created_at,locked_until FROM users
      WHERE ($1::text IS NULL OR role=$1) ORDER BY created_at DESC LIMIT 100`, [role ?? null]);
    return { items: q.rows };
  }

  @Post(':id/status') async status(@Request() r: AuthRequest, @Param('id') id: string, @Body() dto: StatusDto) {
    requireRole(r.user!, 'ADMIN');
    if (id === r.user!.id) conflict('CANNOT_CHANGE_OWN_STATUS');
    return this.db.transaction(async c => {
      const u = await c.query('UPDATE users SET status=$2 WHERE id=$1 RETURNING id,status', [id, dto.status]);
      if (!u.rowCount) missing();
      if (dto.status === 'SUSPENDED') {
        await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [id]);
        await c.query(`UPDATE nurses SET work_status='SUSPENDED',availability_intent='OFFLINE' WHERE user_id=$1`, [id]);
      }
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id) VALUES($1,$2,'user',$3)`, [r.user!.id, `user.${dto.status.toLowerCase()}`, id]);
      return u.rows[0];
    });
  }

  @Post(':id/reset-password') async reset(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'ADMIN');
    const target = (await this.db.query('SELECT role FROM users WHERE id=$1', [id])).rows[0];
    if (!target) missing();
    const password = target.role === 'ADMIN' || target.role === 'CLINICAL_REVIEWER' ? generatePassword() : await defaultPasswordFor(this.db);
    return this.db.transaction(async c => {
      const u = await c.query(`UPDATE users SET password_hash=$2,must_change_password=true,failed_logins=0,locked_until=NULL WHERE id=$1 RETURNING id`, [id, hashPassword(password)]);
      if (!u.rowCount) missing();
      await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id) VALUES($1,'user.password_reset','user',$2)`, [r.user!.id, id]);
      return { id, temporaryPassword: password };
    });
  }
}
