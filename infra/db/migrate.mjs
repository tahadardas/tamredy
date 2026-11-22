import pg from 'pg';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL required');
const dirname = fileURLToPath(new URL('.', import.meta.url));
const migrations = join(dirname, 'migrations');
const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  await client.query('SELECT pg_advisory_lock($1)', [440916]);
  await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name text primary key, applied_at timestamptz not null default now())`);
  for (const name of readdirSync(migrations).filter(x => x.endsWith('.sql')).sort()) {
    const exists = await client.query('SELECT 1 FROM schema_migrations WHERE name=$1', [name]);
    if (exists.rowCount) continue;
    await client.query('BEGIN');
    try {
      await client.query(readFileSync(join(migrations, name), 'utf8'));
      await client.query('INSERT INTO schema_migrations(name) VALUES ($1)', [name]);
      await client.query('COMMIT');
      console.log(`applied: ${name}`);
    } catch(err) { await client.query('ROLLBACK'); throw err; }
  }
  await client.query('SELECT pg_advisory_unlock($1)', [440916]);
} finally { await client.end(); }
