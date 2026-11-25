import { BadRequestException, Body, Controller, Get, HttpCode, HttpException, Post, Request, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { IsDateString, IsIn, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength } from 'class-validator';
import { randomUUID } from 'node:crypto';
import { AuthGuard, AuthRequest, requireRole } from './auth.guard.js';
import { AuthService, hashPassword } from './auth.service.js';
import { DbService } from '../db/db.service.js';
import { DocStore, MAX_FILE_BYTES, KIND_LABEL, docFileName } from '../admin/doc-store.js';
import { checkRegion } from '../admin/regions.controller.js';
import { conflict, missing } from '../common/errors.js';

const PHONE = /^\+[1-9]\d{7,14}$/;
const HOURLY_GLOBAL_CAP = 200, HOURLY_PER_IP_CAP = 8;
class RegisterDto {
  @Matches(PHONE) phone!: string;
  @IsString() @MinLength(2) @MaxLength(80) displayName!: string;
  @IsString() @MinLength(8) @MaxLength(128) password!: string;
  @IsOptional() @IsString() @MinLength(1) @MaxLength(100) deviceId?: string;
  @IsOptional() @IsString() @MaxLength(20) platform?: string;
}
class NurseDocDto {
  @IsIn(['LICENSE', 'PRACTICE_CERT', 'ID', 'DEGREE', 'PHOTO']) kind!: 'LICENSE' | 'PRACTICE_CERT' | 'ID' | 'DEGREE' | 'PHOTO';
  @IsOptional() @IsString() @MaxLength(80) licenseRef?: string;
  @IsOptional() @IsDateString() expiresAt?: string;
}
type Upload = { buffer: Buffer; originalname: string; size: number };

/** Public sign-up. Phone ownership is NOT verified until SMS/OTP exists, so: per-IP and global hourly caps,
 *  an admin switch per audience, and nurses stay unverified until staff approve their licence. */
@Controller('v1/auth')
export class RegistrationController {
  private readonly hits = new Map<string, number[]>();
  constructor(private readonly db: DbService, private readonly auth: AuthService) {}

  private async gate(ip: string, who: 'patients' | 'nurses') {
    const cfg = (await this.db.query(`SELECT value FROM app_settings WHERE key='registration'`)).rows[0]?.value;
    if (cfg && cfg[who] === false) throw new HttpException({ code: 'REGISTRATION_CLOSED' }, 403);
    const now = Date.now(), recent = (this.hits.get(ip) ?? []).filter(t => now - t < 3_600_000);
    if (recent.length >= HOURLY_PER_IP_CAP) throw new HttpException({ code: 'TOO_MANY_REGISTRATIONS' }, 429);
    const n = (await this.db.query(`SELECT count(*)::int AS n FROM users WHERE created_at>now()-interval '1 hour' AND created_by IS NULL`)).rows[0].n;
    if (n >= HOURLY_GLOBAL_CAP) throw new HttpException({ code: 'TOO_MANY_REGISTRATIONS' }, 429);
    this.hits.set(ip, [...recent, now]);
  }

  @Post('register') @HttpCode(201) async patient(@Request() req: { ip?: string }, @Body() d: RegisterDto) {
    await this.gate(req.ip ?? 'unknown', 'patients');
    return this.db.transaction(async c => {
      if ((await c.query('SELECT 1 FROM users WHERE phone_e164=$1', [d.phone])).rowCount) conflict('PHONE_ALREADY_REGISTERED');
      const u = (await c.query(`INSERT INTO users(phone_e164,role,display_name,password_hash) VALUES($1,'PATIENT',$2,$3) RETURNING id`, [d.phone, d.displayName.trim(), hashPassword(d.password)])).rows[0];
      // The patient is their own first beneficiary and consents for themselves.
      await c.query(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,$2,'GRANTED')`, [u.id, d.displayName.trim()]);
      const session=await this.auth.upsertDeviceSession(c,u.id,d.deviceId,undefined,d.platform,'PATIENT');
      return this.auth.issue(c, u.id, 'PATIENT', randomUUID(),session);
    });
  }
}

/** The nurse's own onboarding: submit documents, then watch the approval status. */
@Controller('v1/nurse/me') @UseGuards(AuthGuard)
export class NurseOnboardingController {
  constructor(private readonly db: DbService, private readonly docs: DocStore) {}

  private async nurseId(userId: string) {
    const n = (await this.db.query('SELECT id FROM nurses WHERE user_id=$1', [userId])).rows[0];
    if (!n) missing();
    return n.id as string;
  }

  @Get('onboarding') async status(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    const id = await this.nurseId(r.user!.id);
    const [n, creds, docs] = await Promise.all([
      this.db.query('SELECT n.verified,n.nurse_no,u.display_name FROM nurses n JOIN users u ON u.id=n.user_id WHERE n.id=$1', [id]),
      this.db.query('SELECT license_ref,expires_at,review_status,review_reason FROM nurse_credentials WHERE nurse_id=$1 ORDER BY submitted_at DESC LIMIT 1', [id]),
      this.db.query('SELECT id,kind,original_name,created_at FROM nurse_documents WHERE nurse_id=$1 AND deleted_at IS NULL ORDER BY created_at DESC', [id]),
    ]);
    return { verified: n.rows[0].verified, nurseNo: n.rows[0].nurse_no, name: n.rows[0].display_name, license: creds.rows[0] ?? null, documents: docs.rows };
  }

  @Post('documents') @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_FILE_BYTES, files: 1 } }))
  async upload(@Request() r: AuthRequest, @UploadedFile() file: Upload, @Body() d: NurseDocDto) {
    requireRole(r.user!, 'NURSE');
    if (!file) throw new BadRequestException({ code: 'FILE_REQUIRED' });
    const isCredential = d.kind === 'LICENSE' || d.kind === 'PRACTICE_CERT';
    if (isCredential && (!d.licenseRef || !d.expiresAt)) throw new BadRequestException({ code: 'LICENSE_FIELDS_TOGETHER' });
    const id = await this.nurseId(r.user!.id);
    if (Number((await this.db.query('SELECT count(*)::int AS n FROM nurse_documents WHERE nurse_id=$1 AND deleted_at IS NULL', [id])).rows[0].n) >= 12) conflict('TOO_MANY_DOCUMENTS');
    const who = (await this.db.query('SELECT n.nurse_no,u.display_name FROM nurses n JOIN users u ON u.id=n.user_id WHERE n.id=$1', [id])).rows[0];
    const saved = await this.docs.save(String(who.nurse_no), file, d.kind);
    try {
      return await this.db.transaction(async c => {
        const doc = (await c.query(`INSERT INTO nurse_documents(nurse_id,kind,title,original_name,mime,size_bytes,sha256,storage_key,expires_at,uploaded_by)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`, [id, d.kind, KIND_LABEL[d.kind], docFileName(who.display_name ?? '', d.kind, saved.ext), saved.mime, saved.size, saved.sha256, saved.storageKey, isCredential ? d.expiresAt : null, r.user!.id])).rows[0];
        if (isCredential) {
          await c.query(`DELETE FROM nurse_credentials WHERE nurse_id=$1 AND NOT approved AND review_status IN ('PENDING','NEEDS_INFO')`, [id]); // replace an unreviewed submission
          await c.query('INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,document_id,doc_kind) VALUES($1,$2,$3,$4,$5)', [id, d.licenseRef, d.expiresAt, doc.id, d.kind]);
        }
        return { id: doc.id, kind: d.kind };
      });
    } catch (e) { await this.docs.remove(saved.storageKey); throw e; }
  }
}
