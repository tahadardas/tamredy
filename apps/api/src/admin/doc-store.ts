import { createCipheriv, createDecipheriv, createHash, hkdfSync, randomBytes } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { BadRequestException, Injectable } from '@nestjs/common';

export const MAX_FILE_BYTES = 8 * 1024 * 1024;

export type DocKind = 'LICENSE' | 'PRACTICE_CERT' | 'ID' | 'DEGREE' | 'PHOTO' | 'OTHER';
/** Each category lives in its own folder under UPLOADS_DIR. */
export const KIND_FOLDER: Record<DocKind, string> = { LICENSE: 'licenses', PRACTICE_CERT: 'practice-certificates', ID: 'ids', DEGREE: 'degrees', PHOTO: 'photos', OTHER: 'other' };
/** Arabic label used in the file name and the document title. */
export const KIND_LABEL: Record<DocKind, string> = { LICENSE: 'رخصة', PRACTICE_CERT: 'شهادة مزاولة المهنة', ID: 'هوية', DEGREE: 'شهادة علمية', PHOTO: 'صورة شخصية', OTHER: 'مستند' };
const ILLEGAL_NAME_CHARS = new RegExp('[\\\\/:*?"<>|\\u0000-\\u001f]', 'g');
/** "<person's name> - <label>.<ext>", with characters that are illegal in file names removed. */
export function docFileName(personName: string, kind: DocKind, ext: string): string {
  const clean = personName.replace(ILLEGAL_NAME_CHARS, ' ').replace(/\s+/g, ' ').trim().slice(0, 60) || 'بدون اسم';
  return `${clean} - ${KIND_LABEL[kind]}.${ext}`;
}
const fail = (code: string): never => { throw new BadRequestException({ code }); };

/** Detects the REAL type from the first bytes (the browser-supplied type is never trusted). */
export function sniff(buf: Buffer): { mime: string; ext: string } | null {
  if (buf.length > 4 && buf.subarray(0, 5).toString('latin1') === '%PDF-') return { mime: 'application/pdf', ext: 'pdf' };
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return { mime: 'image/jpeg', ext: 'jpg' };
  if (buf.length > 7 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return { mime: 'image/png', ext: 'png' };
  return null;
}

/** Encrypted file storage for staff documents. AES-256-GCM, key from DOCS_ENC_KEY (64 hex chars) or derived from JWT_SECRET.
 *  Layout on disk: iv(12) | auth tag(16) | ciphertext. Files are never served directly: only through an authenticated admin endpoint. */
@Injectable()
export class DocStore {
  private key(): Buffer {
    const k = process.env.DOCS_ENC_KEY;
    if (k && /^[0-9a-f]{64}$/i.test(k)) return Buffer.from(k, 'hex');
    const s = process.env.JWT_SECRET;
    if (!s || s.length < 32) throw new Error('JWT_SECRET (or DOCS_ENC_KEY) required for document encryption');
    return Buffer.from(hkdfSync('sha256', s, 'tamreedy-docs', 'docs-v1', 32));
  }
  private root() { return resolve(process.env.UPLOADS_DIR ?? './uploads'); }
  private path(key: string) {
    const p = resolve(this.root(), key);
    if (!p.startsWith(this.root())) throw new Error('bad storage key'); // path traversal guard
    return p;
  }

  encryptBuffer(plain: Buffer): Buffer {
    const iv = randomBytes(12), c = createCipheriv('aes-256-gcm', this.key(), iv);
    const enc = Buffer.concat([c.update(plain), c.final()]);
    return Buffer.concat([iv, c.getAuthTag(), enc]);
  }
  decryptBuffer(blob: Buffer): Buffer {
    const d = createDecipheriv('aes-256-gcm', this.key(), blob.subarray(0, 12));
    d.setAuthTag(blob.subarray(12, 28));
    return Buffer.concat([d.update(blob.subarray(28)), d.final()]);
  }
  encryptText(t: string) { return this.encryptBuffer(Buffer.from(t, 'utf8')).toString('base64'); }
  decryptText(b64: string) { return this.decryptBuffer(Buffer.from(b64, 'base64')).toString('utf8'); }

  /** Validates, then stores encrypted in the folder of its category, e.g. licenses/1001-<random>.bin.
   *  [tag] identifies the owner inside the folder (nurse number or "app"). Returns the metadata to keep in the database. */
  async save(tag: string, file: { buffer: Buffer; originalname: string }, kind: DocKind = 'OTHER') {
    if (!file?.buffer?.length) return fail('FILE_REQUIRED');
    if (file.buffer.length > MAX_FILE_BYTES) return fail('FILE_TOO_LARGE');
    const type = sniff(file.buffer);
    if (!type) return fail('FILE_TYPE_NOT_ALLOWED');
    const id = randomBytes(16).toString('hex');
    const storageKey = join(KIND_FOLDER[kind], `${tag.replace(/[^A-Za-z0-9_-]/g, '')}-${id}.bin`).split('\\').join('/');
    const p = this.path(storageKey);
    await mkdir(dirname(p), { recursive: true });
    await writeFile(p, this.encryptBuffer(file.buffer), { mode: 0o600 });
    return { storageKey, mime: type.mime, ext: type.ext, size: file.buffer.length, sha256: createHash('sha256').update(file.buffer).digest('hex') };
  }
  async read(storageKey: string): Promise<Buffer> { return this.decryptBuffer(await readFile(this.path(storageKey))); }
  async remove(storageKey: string) { await rm(this.path(storageKey), { force: true }); }
}
