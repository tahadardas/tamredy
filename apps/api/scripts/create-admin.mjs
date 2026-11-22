// One-time bootstrap of the first ADMIN account.
//   pnpm --filter @tamreedy/api build
//   DATABASE_URL=... ADMIN_PHONE=+963... ADMIN_PASSWORD='at least 12 chars' node apps/api/scripts/create-admin.mjs
import pg from 'pg';
import { hashPassword } from '../dist/auth/auth.service.js';

const { DATABASE_URL, ADMIN_PHONE, ADMIN_PASSWORD } = process.env;
if (!DATABASE_URL || !/^\+[1-9]\d{7,14}$/.test(ADMIN_PHONE ?? '') || (ADMIN_PASSWORD ?? '').length < 12) {
  console.error('Need DATABASE_URL, ADMIN_PHONE (E.164) and ADMIN_PASSWORD (>=12 chars).');
  process.exit(1);
}
const db = new pg.Client({ connectionString: DATABASE_URL });
await db.connect();
try {
  const r = await db.query(`INSERT INTO users(phone_e164,role,display_name,password_hash,status) VALUES($1,'ADMIN','المشرف العام',$2,'ACTIVE')
    ON CONFLICT (phone_e164) DO NOTHING RETURNING id`, [ADMIN_PHONE, hashPassword(ADMIN_PASSWORD)]);
  console.log(r.rowCount ? `admin created: ${r.rows[0].id}` : 'a user with this phone already exists; nothing changed');
} finally { await db.end(); }
