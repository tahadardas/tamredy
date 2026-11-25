import { BadRequestException, Body, Controller, Get, HttpCode, HttpException, Param, Post, Query, Request, Res, StreamableFile, UploadedFiles, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileFieldsInterceptor } from '@nestjs/platform-express';
import { IsDateString, IsIn, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from './auth.guard.js';
import { generatePassword, hashPassword } from './auth.service.js';
import { DbService } from '../db/db.service.js';
import { DocStore, MAX_FILE_BYTES, KIND_LABEL, docFileName, type DocKind } from '../admin/doc-store.js';
import { checkRegion } from '../admin/regions.controller.js';
import { conflict, missing } from '../common/errors.js';

const PHONE = /^\+[1-9]\d{7,14}$/;
const HOURLY_PER_IP_CAP = 6, HOURLY_GLOBAL_CAP = 100;
type Upload = { buffer: Buffer; originalname: string; size: number };

class ApplyDto {
  @Matches(PHONE) phone!: string;
  @IsString() @MinLength(2) @MaxLength(80) displayName!: string;
  @IsUUID() governorateId!: string;
  @IsUUID() areaId!: string;
  @IsOptional() @IsString() @MaxLength(80) specialty?: string;
  @IsOptional() @IsString() @MaxLength(30) nationalId?: string;
  @IsIn(['LICENSE', 'PRACTICE_CERT']) docKind!: 'LICENSE' | 'PRACTICE_CERT';
  @IsString() @MinLength(1) @MaxLength(80) licenseRef!: string;
  @IsDateString() expiresAt!: string;
  /** The applicant accepts legal responsibility for the data and the images. Multipart sends it as a string. */
  @IsIn(['true']) acceptTerms!: string;
}
class InterviewDto { @IsDateString() interviewAt!: string; @IsOptional() @IsString() @MaxLength(500) note?: string; }
class RejectDto { @IsString() @MinLength(2) @MaxLength(500) reason!: string; }

/** Public: a nurse applies to join. NO account is created here; staff create it when they approve the application. */
@Controller('v1/auth')
export class ApplicationsPublicController {
  private readonly hits = new Map<string, number[]>();
  constructor(private readonly db: DbService, private readonly docs: DocStore) {}

  private async gate(ip: string) {
    const cfg = (await this.db.query(`SELECT value FROM app_settings WHERE key='registration'`)).rows[0]?.value;
    if (cfg && cfg.nurses === false) throw new HttpException({ code: 'REGISTRATION_CLOSED' }, 403);
    const now = Date.now(), recent = (this.hits.get(ip) ?? []).filter(t => now - t < 3_600_000);
    if (recent.length >= HOURLY_PER_IP_CAP) throw new HttpException({ code: 'TOO_MANY_REGISTRATIONS' }, 429);
    const n = (await this.db.query(`SELECT count(*)::int AS n FROM nurse_applications WHERE created_at>now()-interval '1 hour'`)).rows[0].n;
    if (n >= HOURLY_GLOBAL_CAP) throw new HttpException({ code: 'TOO_MANY_REGISTRATIONS' }, 429);
    this.hits.set(ip, [...recent, now]);
  }

  @Post('nurse-applications') @HttpCode(201)
  @UseInterceptors(FileFieldsInterceptor([{ name: 'idPhoto', maxCount: 1 }, { name: 'document', maxCount: 1 }], { limits: { fileSize: MAX_FILE_BYTES, files: 2 } }))
  async apply(@Request() req: { ip?: string }, @UploadedFiles() files: { idPhoto?: Upload[]; document?: Upload[] }, @Body() d: ApplyDto) {
    const idPhoto = files?.idPhoto?.[0], document = files?.document?.[0];
    if (!idPhoto || !document) throw new BadRequestException({ code: 'FILE_REQUIRED' });
    if (new Date(d.expiresAt) <= new Date()) throw new BadRequestException({ code: 'LICENSE_EXPIRED' });
    await this.gate(req.ip ?? 'unknown');
    if ((await this.db.query('SELECT 1 FROM users WHERE phone_e164=$1', [d.phone])).rowCount) conflict('PHONE_ALREADY_REGISTERED');
    if ((await this.db.query(`SELECT 1 FROM nurse_applications WHERE phone_e164=$1 AND status IN ('PENDING','INTERVIEW')`, [d.phone])).rowCount) conflict('APPLICATION_ALREADY_OPEN');
    await checkRegion(this.db, d.governorateId, d.areaId);
    // Validate + encrypt both files (real type from bytes) into the folder of each category.
    const savedId = await this.docs.save('app', idPhoto, 'ID');
    let savedDoc: Awaited<ReturnType<DocStore['save']>> | undefined;
    try {
      savedDoc = await this.docs.save('app', document, d.docKind);
      return await this.db.transaction(async c => {
        const a = (await c.query(`INSERT INTO nurse_applications(phone_e164,display_name,governorate_id,area_id,specialty,national_id_enc,doc_kind,license_ref,expires_at,accepted_terms_at)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,now()) RETURNING id`,
          [d.phone, d.displayName.trim(), d.governorateId, d.areaId, d.specialty ?? null, d.nationalId ? this.docs.encryptText(d.nationalId) : null, d.docKind, d.licenseRef.trim(), d.expiresAt])).rows[0];
        for (const [kind, s] of [['ID', savedId], [d.docKind, savedDoc!]] as [DocKind, typeof savedId][])
          await c.query(`INSERT INTO application_documents(application_id,kind,original_name,mime,size_bytes,sha256,storage_key) VALUES($1,$2,$3,$4,$5,$6,$7)`,
            [a.id, kind, docFileName(d.displayName, kind, s.ext), s.mime, s.size, s.sha256, s.storageKey]);
        return { id: a.id, status: 'PENDING' };
      });
    } catch (e) {
      await this.docs.remove(savedId.storageKey);
      if (savedDoc) await this.docs.remove(savedDoc.storageKey);
      throw e;
    }
  }
}

/** Staff: review applications, schedule the interview, approve (creates the account) or reject. */
@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminApplicationsController {
  constructor(private readonly db: DbService, private readonly docs: DocStore) {}

  private audit(c: { query: (s: string, p?: unknown[]) => Promise<any> }, actor: string, action: string, id: string, detail: unknown = {}) {
    return c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,$2,'nurse_application',$3,$4::jsonb)`, [actor, action, id, JSON.stringify(detail)]);
  }

  @Get('applications') async list(@Request() r: AuthRequest, @Query('status') status?: string) {
    requireAnyRole(r.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    const st = ['PENDING', 'INTERVIEW', 'APPROVED', 'REJECTED'].includes(status ?? '') ? status : null;
    const rows = (await this.db.query(`SELECT a.id,a.display_name,a.phone_e164,a.specialty,a.doc_kind,a.license_ref,a.expires_at,a.status,a.interview_at,a.staff_note,a.created_at,a.nurse_id,
        g.name_ar AS governorate,ar.name_ar AS area,
        (SELECT coalesce(json_agg(json_build_object('id',d.id,'kind',d.kind,'name',d.original_name) ORDER BY d.kind),'[]'::json) FROM application_documents d WHERE d.application_id=a.id) AS documents
      FROM nurse_applications a LEFT JOIN governorates g ON g.id=a.governorate_id LEFT JOIN areas ar ON ar.id=a.area_id
      WHERE ($1::text IS NULL OR a.status=$1) ORDER BY (a.status IN ('PENDING','INTERVIEW')) DESC, a.created_at DESC LIMIT 200`, [st])).rows;
    return { items: rows.map((x: any) => ({ ...x, docKindLabel: KIND_LABEL[x.doc_kind as DocKind] })) };
  }

  @Get('application-documents/:docId/download') async download(@Request() r: AuthRequest, @Param('docId') docId: string, @Res({ passthrough: true }) res: { set: (h: Record<string, string>) => void }) {
    requireAnyRole(r.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    const d = (await this.db.query('SELECT id,application_id,original_name,mime,storage_key FROM application_documents WHERE id=$1', [docId])).rows[0];
    if (!d) missing();
    const buf = await this.docs.read(d.storage_key);
    await this.db.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'application.document_viewed','nurse_application',$2,$3::jsonb)`, [r.user!.id, d.application_id, JSON.stringify({ docId })]);
    res.set({ 'Content-Type': d.mime, 'Content-Disposition': `inline; filename*=UTF-8''${encodeURIComponent(d.original_name)}`, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    return new StreamableFile(buf);
  }

  @Post('applications/:id/interview') async interview(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: InterviewDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const a = (await c.query('SELECT status FROM nurse_applications WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!a) missing();
      if (!['PENDING', 'INTERVIEW'].includes(a.status)) conflict('APPLICATION_ALREADY_DECIDED');
      await c.query(`UPDATE nurse_applications SET status='INTERVIEW',interview_at=$2,staff_note=coalesce($3,staff_note) WHERE id=$1`, [id, d.interviewAt, d.note ?? null]);
      await this.audit(c, r.user!.id, 'application.interview_scheduled', id, { at: d.interviewAt });
      return { id, status: 'INTERVIEW' };
    });
  }

  @Post('applications/:id/reject') async reject(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: RejectDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const a = (await c.query('SELECT status FROM nurse_applications WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!a) missing();
      if (!['PENDING', 'INTERVIEW'].includes(a.status)) conflict('APPLICATION_ALREADY_DECIDED');
      await c.query(`UPDATE nurse_applications SET status='REJECTED',staff_note=$2,decided_by=$3,decided_at=now() WHERE id=$1`, [id, d.reason, r.user!.id]);
      await this.audit(c, r.user!.id, 'application.rejected', id, { reason: d.reason });
      return { id, status: 'REJECTED' };
    });
  }

  /** Approval = the licence is accepted: the login account is created now (initial password, must be changed at first login). */
  @Post('applications/:id/approve') async approve(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'ADMIN');
    const password = generatePassword(20);
    return this.db.transaction(async c => {
      const a = (await c.query('SELECT * FROM nurse_applications WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!a) missing();
      if (!['PENDING', 'INTERVIEW'].includes(a.status)) conflict('APPLICATION_ALREADY_DECIDED');
      if (new Date(a.expires_at) <= new Date()) conflict('LICENSE_EXPIRED');
      if ((await c.query('SELECT 1 FROM users WHERE phone_e164=$1', [a.phone_e164])).rowCount) conflict('PHONE_ALREADY_REGISTERED');
      const u = (await c.query(`INSERT INTO users(phone_e164,role,display_name,password_hash,must_change_password,created_by,temporary_password_expires_at)
        VALUES($1,'NURSE',$2,$3,true,$4,statement_timestamp()+interval '30 minutes') RETURNING id`,
        [a.phone_e164, a.display_name, hashPassword(password), r.user!.id])).rows[0];
      const n = (await c.query(`INSERT INTO nurses(user_id,verified,governorate_id,area_id,specialty,national_id_enc) VALUES($1,true,$2,$3,$4,$5) RETURNING id,nurse_no`,
        [u.id, a.governorate_id, a.area_id, a.specialty, a.national_id_enc])).rows[0];
      const docs = (await c.query('SELECT * FROM application_documents WHERE application_id=$1', [id])).rows;
      let credDoc: string | null = null;
      for (const d of docs) {
        const row = (await c.query(`INSERT INTO nurse_documents(nurse_id,kind,title,original_name,mime,size_bytes,sha256,storage_key,expires_at,uploaded_by)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
          [n.id, d.kind, KIND_LABEL[d.kind as DocKind], d.original_name, d.mime, d.size_bytes, d.sha256, d.storage_key, d.kind === a.doc_kind ? a.expires_at : null, r.user!.id])).rows[0];
        if (d.kind === a.doc_kind) credDoc = row.id;
      }
      await c.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,document_id,doc_kind,approved,review_status,verified_at,verified_by) VALUES($1,$2,$3,$4,$5,true,'APPROVED',now(),$6)`,
        [n.id, a.license_ref, a.expires_at, credDoc, a.doc_kind, r.user!.id]);
      await c.query(`UPDATE nurse_applications SET status='APPROVED',nurse_id=$2,decided_by=$3,decided_at=now() WHERE id=$1`, [id, n.id, r.user!.id]);
      await this.audit(c, r.user!.id, 'application.approved', id, { nurseId: n.id, nurseNo: n.nurse_no });
      return { id, status: 'APPROVED', nurseId: n.id, nurseNo: n.nurse_no, account: { phone: a.phone_e164, name: a.display_name, defaultPassword: password } };
    });
  }
}
