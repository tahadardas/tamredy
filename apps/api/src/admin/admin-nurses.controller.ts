import { BadRequestException, Body, Controller, Delete, Get, Param, Patch, Post, Put, Query, Request, Res, StreamableFile, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { IsArray, IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from '../auth/auth.guard.js';
import { defaultPasswordFor, hashPassword } from '../auth/auth.service.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';
import { DocStore, MAX_FILE_BYTES, KIND_LABEL, docFileName } from './doc-store.js';
import { checkRegion } from './regions.controller.js';

const PHONE = /^\+[1-9]\d{7,14}$/;
class CreateNurseDto {
  @Matches(PHONE) phone!: string;
  @IsString() @MinLength(2) @MaxLength(80) displayName!: string;
  @IsOptional() @IsString() @MinLength(6) @MaxLength(128) password?: string;
  @IsOptional() @IsUUID() governorateId?: string;
  @IsOptional() @IsUUID() areaId?: string;
  @IsOptional() @IsString() @MaxLength(80) specialty?: string;
  @IsOptional() @IsString() @MaxLength(30) nationalId?: string;
  @IsOptional() @IsString() @MaxLength(500) notes?: string;
  @IsOptional() @IsInt() @Min(1) @Max(99_999_999) nurseNo?: number;
}
class UpdateNurseDto {
  @IsOptional() @Matches(PHONE) phone?: string;
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) displayName?: string;
  @IsOptional() @IsUUID() governorateId?: string;
  @IsOptional() @IsUUID() areaId?: string;
  @IsOptional() @IsString() @MaxLength(80) specialty?: string;
  @IsOptional() @IsString() @MaxLength(30) nationalId?: string;
  @IsOptional() @IsString() @MaxLength(500) notes?: string;
  @IsOptional() @IsInt() @Min(1) @Max(99_999_999) nurseNo?: number;
}
class StatusDto { @IsIn(['ACTIVE', 'SUSPENDED']) status!: 'ACTIVE' | 'SUSPENDED'; }
class SkillsDto { @IsArray() @IsUUID('all', { each: true }) serviceIds!: string[]; }
class UploadDto {
  @IsIn(['LICENSE', 'PRACTICE_CERT', 'ID', 'DEGREE', 'PHOTO', 'OTHER']) kind!: 'LICENSE' | 'PRACTICE_CERT' | 'ID' | 'DEGREE' | 'PHOTO' | 'OTHER';
  @IsOptional() @IsString() @MaxLength(80) title?: string;
  /** For kind=LICENSE: the licence number + expiry open an approval request in the credentials queue. */
  @IsOptional() @IsString() @MaxLength(80) licenseRef?: string;
  @IsOptional() @IsDateString() expiresAt?: string;
}
type Upload = { buffer: Buffer; originalname: string; size: number };

const ADMINS = ['ADMIN', 'CLINICAL_REVIEWER'] as const;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const maskId = (v: string | null) => (v ? `••••${v.slice(-3)}` : null);

/** Nurse administration: add / edit / suspend / delete, number, skills, and encrypted documents. */
@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminNursesController {
  constructor(private readonly db: DbService, private readonly docs: DocStore) {}

  private audit(c: { query: (s: string, p?: unknown[]) => Promise<any> }, actor: string, action: string, id: string, detail: unknown = {}) {
    return c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,$2,'nurse',$3,$4::jsonb)`, [actor, action, id, JSON.stringify(detail)]);
  }

  @Get('nurses/manage') async list(@Request() r: AuthRequest, @Query('q') q?: string, @Query('status') status?: string, @Query('governorate') gov?: string, @Query('area') area?: string) {
    requireAnyRole(r.user!, [...ADMINS]);
    const rows = (await this.db.query(`SELECT n.id,n.nurse_no,u.display_name,u.phone_e164,u.status AS account_status,n.verified,n.work_status,coalesce(a.name_ar,n.area) AS area,g.name_ar AS governorate,n.governorate_id,n.area_id,n.specialty,n.created_at,
        (SELECT count(*)::int FROM nurse_documents d WHERE d.nurse_id=n.id AND d.deleted_at IS NULL) AS documents,
        (SELECT review_status FROM nurse_credentials c WHERE c.nurse_id=n.id ORDER BY c.submitted_at DESC LIMIT 1) AS license_status,
        (SELECT count(*)::int FROM nurse_skills k JOIN services s ON s.id=k.service_id WHERE k.nurse_id=n.id AND k.approved) AS skills,
        (SELECT round(avg(vr.stars)::numeric,1) FROM visit_reviews vr JOIN visits v ON v.id=vr.visit_id JOIN request_assignments a ON a.id=v.assignment_id WHERE a.nurse_id=n.id AND vr.reviewer_role='PATIENT') AS rating
      FROM nurses n JOIN users u ON u.id=n.user_id LEFT JOIN governorates g ON g.id=n.governorate_id LEFT JOIN areas a ON a.id=n.area_id
      WHERE u.status<>'DELETED' AND ($1::text IS NULL OR u.status=$1) AND ($3::uuid IS NULL OR n.governorate_id=$3) AND ($4::uuid IS NULL OR n.area_id=$4)
        AND ($2::text IS NULL OR coalesce(u.display_name,'') ILIKE '%'||$2||'%' OR u.phone_e164 ILIKE '%'||$2||'%' OR n.nurse_no::text=$2)
      ORDER BY n.nurse_no DESC LIMIT 200`, [status && ['ACTIVE', 'SUSPENDED'].includes(status) ? status : null, q?.trim() || null, UUID_RE.test(gov ?? '') ? gov : null, UUID_RE.test(area ?? '') ? area : null])).rows;
    return { items: rows };
  }

  @Get('nurses/:id/profile') async profile(@Request() r: AuthRequest, @Param('id') id: string) {
    requireAnyRole(r.user!, [...ADMINS]);
    const n = (await this.db.query(`SELECT n.id,n.nurse_no,n.area,n.governorate_id,n.area_id,n.specialty,n.notes,n.verified,n.work_status,n.national_id_enc,u.id AS user_id,u.display_name,u.phone_e164,u.status AS account_status
      FROM nurses n JOIN users u ON u.id=n.user_id WHERE n.id=$1 AND u.status<>'DELETED'`, [id])).rows[0];
    if (!n) missing();
    let nid: string | null = null;
    try { nid = n.national_id_enc ? this.docs.decryptText(n.national_id_enc) : null; } catch { nid = null; }
    const { national_id_enc: _e, ...rest } = n;
    const [skills, creds, docs] = await Promise.all([
      this.db.query(`SELECT s.id,s.title_ar,coalesce(k.approved,false) AS approved FROM services s LEFT JOIN nurse_skills k ON k.service_id=s.id AND k.nurse_id=$1 ORDER BY s.sort_order,s.title_ar`, [id]),
      this.db.query(`SELECT id,license_ref,doc_kind,expires_at,review_status,review_reason,approved,document_id,submitted_at FROM nurse_credentials WHERE nurse_id=$1 ORDER BY submitted_at DESC`, [id]),
      this.db.query(`SELECT id,kind,title,original_name,mime,size_bytes,expires_at,created_at FROM nurse_documents WHERE nurse_id=$1 AND deleted_at IS NULL ORDER BY created_at DESC`, [id]),
    ]);
    return { ...rest, nationalIdMasked: maskId(nid), skills: skills.rows, credentials: creds.rows, documents: docs.rows };
  }

  @Post('nurses/manage') async create(@Request() r: AuthRequest, @Body() d: CreateNurseDto) {
    requireRole(r.user!, 'ADMIN');
    const password = d.password ?? await defaultPasswordFor(this.db);
    return this.db.transaction(async c => {
      if ((await c.query('SELECT 1 FROM users WHERE phone_e164=$1', [d.phone])).rowCount) conflict('PHONE_ALREADY_REGISTERED');
      if (d.nurseNo && (await c.query('SELECT 1 FROM nurses WHERE nurse_no=$1', [d.nurseNo])).rowCount) conflict('NURSE_NO_TAKEN');
      await checkRegion(c, d.governorateId, d.areaId);
      const u = (await c.query(`INSERT INTO users(phone_e164,role,display_name,password_hash,must_change_password,created_by) VALUES($1,'NURSE',$2,$3,true,$4) RETURNING id`,
        [d.phone, d.displayName, hashPassword(password), r.user!.id])).rows[0];
      const n = (await c.query(`INSERT INTO nurses(user_id,nurse_no,governorate_id,area_id,specialty,national_id_enc,notes) VALUES($1,coalesce($2,nextval('nurse_no_seq')),$3,$4,$5,$6,$7) RETURNING id,nurse_no`,
        [u.id, d.nurseNo ?? null, d.governorateId ?? null, d.areaId ?? null, d.specialty ?? null, d.nationalId ? this.docs.encryptText(d.nationalId) : null, d.notes ?? null])).rows[0];
      await this.audit(c, r.user!.id, 'nurse.created', n.id, { phone: d.phone, nurseNo: n.nurse_no });
      return { id: n.id, nurseNo: n.nurse_no, temporaryPassword: password, note: 'Shown once.' };
    });
  }

  @Patch('nurses/:id/profile') async update(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: UpdateNurseDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const n = (await c.query('SELECT n.id,n.user_id FROM nurses n JOIN users u ON u.id=n.user_id WHERE n.id=$1 AND u.status<>\'DELETED\' FOR UPDATE OF n', [id])).rows[0];
      if (!n) missing();
      if (d.phone && (await c.query('SELECT 1 FROM users WHERE phone_e164=$1 AND id<>$2', [d.phone, n.user_id])).rowCount) conflict('PHONE_ALREADY_REGISTERED');
      if (d.nurseNo && (await c.query('SELECT 1 FROM nurses WHERE nurse_no=$1 AND id<>$2', [d.nurseNo, id])).rowCount) conflict('NURSE_NO_TAKEN');
      await checkRegion(c, d.governorateId, d.areaId);
      if (d.phone !== undefined || d.displayName !== undefined)
        await c.query('UPDATE users SET phone_e164=coalesce($2,phone_e164),display_name=coalesce($3,display_name) WHERE id=$1', [n.user_id, d.phone ?? null, d.displayName ?? null]);
      await c.query(`UPDATE nurses SET governorate_id=coalesce($2,governorate_id),area_id=coalesce($7,area_id),specialty=coalesce($3,specialty),notes=coalesce($4,notes),nurse_no=coalesce($5,nurse_no),
        national_id_enc=coalesce($6,national_id_enc),updated_at=now() WHERE id=$1`,
        [id, d.governorateId ?? null, d.specialty ?? null, d.notes ?? null, d.nurseNo ?? null, d.nationalId ? this.docs.encryptText(d.nationalId) : null, d.areaId ?? null]);
      await this.audit(c, r.user!.id, 'nurse.updated', id, { fields: Object.keys(d).filter(k => k !== 'nationalId') });
      return { id };
    });
  }

  @Post('nurses/:id/status') async status(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: StatusDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const n = (await c.query('SELECT user_id FROM nurses WHERE id=$1', [id])).rows[0];
      if (!n) missing();
      await c.query('UPDATE users SET status=$2 WHERE id=$1', [n.user_id, d.status]);
      if (d.status === 'SUSPENDED') {
        await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [n.user_id]);
        await c.query(`UPDATE nurses SET availability_intent='OFFLINE',work_status='SUSPENDED',updated_at=now() WHERE id=$1`, [id]);
      } else await c.query(`UPDATE nurses SET work_status='OFFLINE',updated_at=now() WHERE id=$1 AND work_status='SUSPENDED'`, [id]);
      await this.audit(c, r.user!.id, `nurse.${d.status.toLowerCase()}`, id);
      return { id, status: d.status };
    });
  }

  /** Recovery: sets the initial password again (must be changed at next login) and ends all sessions. */
  @Post('nurses/:id/reset-password') async resetPassword(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'ADMIN');
    const password = await defaultPasswordFor(this.db);
    return this.db.transaction(async c => {
      const n = (await c.query(`SELECT n.user_id FROM nurses n JOIN users u ON u.id=n.user_id WHERE n.id=$1 AND u.status<>'DELETED'`, [id])).rows[0];
      if (!n) missing();
      await c.query('UPDATE users SET password_hash=$2,must_change_password=true,failed_logins=0,locked_until=NULL WHERE id=$1', [n.user_id, hashPassword(password)]);
      await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [n.user_id]);
      await this.audit(c, r.user!.id, 'nurse.password_reset', id);
      return { id, temporaryPassword: password };
    });
  }

  /** "Delete" keeps every record (visits, money, audit) but the nurse can no longer log in, appear, or receive requests. */
  @Delete('nurses/:id/profile') async remove(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const n = (await c.query(`SELECT n.user_id,n.work_status FROM nurses n WHERE n.id=$1 FOR UPDATE`, [id])).rows[0];
      if (!n) missing();
      if (['RESERVED', 'EN_ROUTE', 'IN_SERVICE'].includes(n.work_status)) conflict('NURSE_ON_ACTIVE_VISIT');
      await c.query(`UPDATE users SET status='DELETED',phone_e164='deleted-'||id::text WHERE id=$1`, [n.user_id]); // frees the phone number
      await c.query('UPDATE refresh_tokens SET revoked_at=coalesce(revoked_at,now()) WHERE user_id=$1', [n.user_id]);
      await c.query('DELETE FROM device_tokens WHERE user_id=$1', [n.user_id]);
      await c.query(`UPDATE nurses SET availability_intent='OFFLINE',work_status='OFFLINE',updated_at=now() WHERE id=$1`, [id]);
      await this.audit(c, r.user!.id, 'nurse.deleted', id);
      return { id, deleted: true };
    });
  }

  /** Which services this nurse may perform (needed before she can receive requests). */
  @Put('nurses/:id/skills') async skills(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: SkillsDto) {
    requireAnyRole(r.user!, [...ADMINS]);
    return this.db.transaction(async c => {
      if (!(await c.query('SELECT 1 FROM nurses WHERE id=$1', [id])).rowCount) missing();
      await c.query('DELETE FROM nurse_skills WHERE nurse_id=$1 AND NOT (service_id=ANY($2::uuid[]))', [id, d.serviceIds]);
      for (const s of d.serviceIds) await c.query('INSERT INTO nurse_skills(nurse_id,service_id,approved) VALUES($1,$2,true) ON CONFLICT(nurse_id,service_id) DO UPDATE SET approved=true', [id, s]);
      await this.audit(c, r.user!.id, 'nurse.skills_set', id, { count: d.serviceIds.length });
      return { id, skills: d.serviceIds.length };
    });
  }

  // ---------------- documents (encrypted at rest) ----------------
  @Post('nurses/:id/documents') @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_FILE_BYTES, files: 1 } }))
  async upload(@Request() r: AuthRequest, @Param('id') id: string, @UploadedFile() file: Upload, @Body() d: UploadDto) {
    requireAnyRole(r.user!, [...ADMINS]);
    if (!file) throw new BadRequestException({ code: 'FILE_REQUIRED' });
    const isCredential = d.kind === 'LICENSE' || d.kind === 'PRACTICE_CERT';
    if (isCredential && (!d.licenseRef || !d.expiresAt)) throw new BadRequestException({ code: 'LICENSE_FIELDS_TOGETHER' }); // a licence without number+expiry could never reach the approval queue
    const owner = (await this.db.query('SELECT n.nurse_no,u.display_name FROM nurses n JOIN users u ON u.id=n.user_id WHERE n.id=$1', [id])).rows[0];
    if (!owner) missing();
    const saved = await this.docs.save(String(owner.nurse_no), file, d.kind); // validates type from real bytes, size, then encrypts into the folder of its category
    try {
      return await this.db.transaction(async c => {
        const doc = (await c.query(`INSERT INTO nurse_documents(nurse_id,kind,title,original_name,mime,size_bytes,sha256,storage_key,expires_at,uploaded_by)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
          [id, d.kind, d.title ?? KIND_LABEL[d.kind], docFileName(owner.display_name ?? '', d.kind, saved.ext), saved.mime, saved.size, saved.sha256, saved.storageKey, d.expiresAt ?? null, r.user!.id])).rows[0];
        let credentialId: string | null = null;
        if (isCredential)
          credentialId = (await c.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,document_id,doc_kind) VALUES($1,$2,$3,$4,$5) RETURNING id`, [id, d.licenseRef, d.expiresAt, doc.id, d.kind])).rows[0].id; // enters the approval queue, never auto-approved
        await this.audit(c, r.user!.id, 'nurse.document_uploaded', id, { docId: doc.id, kind: d.kind, size: saved.size });
        return { id: doc.id, kind: d.kind, size: saved.size, queuedForApproval: !!credentialId, credentialId };
      });
    } catch (e) { await this.docs.remove(saved.storageKey); throw e; }
  }

  @Get('documents/:docId/download') async download(@Request() r: AuthRequest, @Param('docId') docId: string, @Res({ passthrough: true }) res: { set: (h: Record<string, string>) => void }) {
    requireAnyRole(r.user!, [...ADMINS]);
    const d = (await this.db.query('SELECT id,nurse_id,original_name,mime,storage_key FROM nurse_documents WHERE id=$1 AND deleted_at IS NULL', [docId])).rows[0];
    if (!d) missing();
    const buf = await this.docs.read(d.storage_key);
    await this.db.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,'nurse.document_viewed','nurse',$2,$3::jsonb)`, [r.user!.id, d.nurse_id, JSON.stringify({ docId })]);
    res.set({ 'Content-Type': d.mime, 'Content-Disposition': `inline; filename*=UTF-8''${encodeURIComponent(d.original_name)}`, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    return new StreamableFile(buf);
  }

  @Delete('documents/:docId') async removeDoc(@Request() r: AuthRequest, @Param('docId') docId: string) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const d = (await c.query('SELECT id,nurse_id,storage_key FROM nurse_documents WHERE id=$1 AND deleted_at IS NULL FOR UPDATE', [docId])).rows[0];
      if (!d) missing();
      if ((await c.query(`SELECT 1 FROM nurse_credentials WHERE document_id=$1 AND approved`, [docId])).rowCount) conflict('DOCUMENT_BACKS_APPROVED_LICENSE');
      await c.query('UPDATE nurse_documents SET deleted_at=now() WHERE id=$1', [docId]);
      await this.audit(c, r.user!.id, 'nurse.document_deleted', d.nurse_id, { docId });
      await this.docs.remove(d.storage_key);
      return { id: docId };
    });
  }
}
