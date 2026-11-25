import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readdirSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import pg from 'pg';
import test from 'node:test';

test('upgrade from migration 051 preserves historical visits, receipts and Arabic text', {
  skip: !process.env.TEST_UPGRADE_DATABASE_URL && 'Requires an empty disposable PostgreSQL upgrade database',
}, async t => {
  const url=new URL(process.env.TEST_UPGRADE_DATABASE_URL);
  assert.ok(['localhost','127.0.0.1','[::1]'].includes(url.hostname));
  assert.match(url.pathname,/^\/tamreedy_(test_)?upgrade\w*$/);
  const db=new pg.Client({connectionString:url.href});
  await db.connect();
  t.after(()=>db.end());
  const q=(sql,params)=>db.query(sql,params);
  assert.equal((await q("SELECT to_regclass('public.users') AS users")).rows[0].users,null);
  await q('CREATE TABLE schema_migrations(name text PRIMARY KEY,applied_at timestamptz NOT NULL DEFAULT now())');
  const dir=new URL('../../../infra/db/migrations/',import.meta.url);
  for(const file of readdirSync(dir).sort().filter(file=>/^\d{3}_.+\.sql$/.test(file)&&Number(file.slice(0,3))<=51)){
    await q('BEGIN');
    await q(readFileSync(new URL(file,dir),'utf8'));
    await q('INSERT INTO schema_migrations(name) VALUES($1)',[file]);
    await q('COMMIT');
  }
  const ids=(await q(`WITH p AS (
    INSERT INTO users(phone_e164,role) VALUES('+963911555001','PATIENT') RETURNING id
  ), n AS (
    INSERT INTO users(phone_e164,role) VALUES('+963911555002','NURSE') RETURNING id
  ), b AS (
    INSERT INTO beneficiaries(owner_user_id,display_name,consent_status)
    SELECT id,'سلمى الأحمد','GRANTED' FROM p RETURNING id,owner_user_id
  ), profile AS (
    INSERT INTO nurses(user_id) SELECT id FROM n RETURNING id
  ), cr AS (
    INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,
      price_amount,currency_code,commission_bps,gross_amount,amount_due,commission_amount,nurse_earning,paid_at,payment_status)
    SELECT b.owner_user_id,b.id,(SELECT id FROM services ORDER BY id LIMIT 1),
      ST_SetSRID(ST_MakePoint(36.29,33.51),4326)::geography,'MANUAL_PIN','دمشق، دمر','COMPLETED',
      1000,'SYP_NEW',2000,1000,1000,200,800,now(),'PAID' FROM b RETURNING id,beneficiary_id
  ), a AS (
    INSERT INTO request_assignments(request_id,nurse_id,status) SELECT cr.id,profile.id,'RELEASED'
    FROM cr CROSS JOIN profile RETURNING id,request_id
  ), v AS (
    INSERT INTO visits(assignment_id,completed_at) SELECT a.id,now() FROM a RETURNING id
  ), receipt AS (
    INSERT INTO cash_collections(visit_id,collector_nurse_id,amount,status)
    SELECT v.id,profile.id,1000,'CONFIRMED' FROM v CROSS JOIN profile RETURNING id
  )
  SELECT cr.id AS request_id,cr.beneficiary_id,receipt.id AS receipt_id FROM cr CROSS JOIN receipt`)).rows[0];
  const runner=fileURLToPath(new URL('../../../infra/db/migrate.mjs',import.meta.url));
  const migrate=()=>execFileSync(process.execPath,[runner],{encoding:'utf8',env:{...process.env,DATABASE_URL:url.href}});
  assert.match(migrate(),/applied: 059_/);
  assert.equal(migrate().trim(),'');
  const preserved=(await q(`SELECT b.display_name,r.address_text,c.amount::text,c.transaction_id,i.total_amount::text
    FROM care_requests r JOIN beneficiaries b ON b.id=r.beneficiary_id JOIN invoices i ON i.request_id=r.id
    JOIN cash_collections c ON c.visit_id=i.visit_id WHERE r.id=$1 AND b.id=$2 AND c.id=$3`,
  [ids.request_id,ids.beneficiary_id,ids.receipt_id])).rows[0];
  assert.deepEqual(preserved,{display_name:'سلمى الأحمد',address_text:'دمشق، دمر',amount:'1000.00',
    transaction_id:ids.receipt_id,total_amount:'1000.00'});
  assert.equal((await q('SELECT count(*)::int AS count FROM financial_unbalanced_transactions')).rows[0].count,0);
});
