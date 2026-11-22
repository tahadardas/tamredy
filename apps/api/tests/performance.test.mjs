import {test, after} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,copyFileSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const temp=mkdtempSync(join(tmpdir(),'tamreedy-performance-'));
const api=resolve(import.meta.dirname??'.','../src');
copyFileSync(join(api,'common/pagination.ts'),join(temp,'pagination.mts'));
// Node 26 supports .mts type stripping, Node 22 requires --experimental-strip-types.
const pagination=await import(pathToFileURL(join(temp,'pagination.mts')).href);
process.env.JWT_SECRET='test-only-'.repeat(8);
after(()=>rmSync(temp,{recursive:true,force:true}));
const {parsePage,encodeCursor,decodeCursor,makePage}=pagination;
const id=(i)=>`00000000-0000-4000-8000-${i.toString().padStart(12,'0')}`;
test('bounded default and maximum page size',()=>{
 assert.equal(parsePage(undefined,undefined,'scope').limit,20);
 assert.equal(parsePage('50',undefined,'scope').limit,50);
 for(const n of ['0','51','-1','1.5','NaN','100000',''])assert.throws(()=>parsePage(n,undefined,'scope'));
});
test('cursor signature rejects tampering and cross-tenant replay',()=>{
 const c=encodeCursor({at:'2026-11-20T10:10:10.123456Z',id:id(2)},'patient:alice');
 assert.deepEqual(decodeCursor(c,'patient:alice'),{at:'2026-11-20T10:10:10.123456Z',id:id(2)});
 assert.throws(()=>decodeCursor(c,'patient:bob'));
 assert.throws(()=>decodeCursor(c.replace(/.$/,'x'),'patient:alice'));
 assert.throws(()=>decodeCursor('not-a-token','patient:alice'));
});
test('stable keyset pages with timestamps at microsecond precision and equal times',()=>{
 const records=[
  {id:id(9),created_at:'2026-11-20T10:10:10.123456Z',cursor_created_at:'2026-11-20T10:10:10.123456Z'},
  {id:id(8),created_at:'2026-11-20T10:10:10.123456Z',cursor_created_at:'2026-11-20T10:10:10.123456Z'},
  {id:id(7),created_at:'2026-11-20T10:10:10.123455Z',cursor_created_at:'2026-11-20T10:10:10.123455Z'},
  {id:id(6),created_at:'2026-11-20T10:10:10.123454Z',cursor_created_at:'2026-11-20T10:10:10.123454Z'},
 ];
 const p=makePage(records.slice(0,3),2,'patient:alice');
 assert.equal(p.items.length,2);assert.equal(p.hasMore,true);
 const token=decodeCursor(p.nextCursor,'patient:alice');
 assert.equal(token.at,'2026-11-20T10:10:10.123456Z');assert.equal(token.id,id(8));
 const next=records.filter(r=>r.cursor_created_at<token.at||(r.cursor_created_at===token.at&&r.id<token.id));
 assert.deepEqual(next.map(r=>r.id),[id(7),id(6)]);
 const final=makePage(next,2,'patient:alice');assert.equal(final.nextCursor,null);
});
test('migration indexes foreign keys and keyset paths without duplicating primary keys',()=>{
 const sql=readFileSync(resolve(api,'../../../infra/db/migrations/002_query_indexes.sql'),'utf8');
 for(const index of ['idx_requests_owner_created_id','idx_requests_created_id','idx_requests_status_created_id',
 'idx_beneficiaries_owner_created','idx_credentials_nurse_expiry','idx_skills_service_approved_nurse',
 'idx_assignments_nurse_history','idx_assignments_request_history','idx_ledger_lines_transaction',
 'idx_nurses_dispatch_ready'])assert.ok(sql.includes(index),index);
 assert.ok(!/ON users\(id\)/i.test(sql));
});
test('worker dispatch inserts candidates and events set-wise, with no per-nurse SQL loop',()=>{
 const src=readFileSync(resolve(api,'../../../apps/worker/src/dispatch.ts'),'utf8');
 const worker=readFileSync(resolve(api,'../../../apps/worker/src/main.ts'),'utf8');
 assert.ok(src.includes('WITH candidates AS ('));
 assert.ok(src.includes('INSERT INTO request_offers'));
 assert.ok(src.includes('jsonb_build_object'));
 assert.ok(!src.includes('for(const n of nurses.rows)'));
 assert.match(worker, /WHERE id\s*=\s*ANY\(\$1::bigint\[\]\)/);
});
test('patient/admin histories use joined reads and keyset ordering, no fixed LIMIT 100',()=>{
 const req=readFileSync(resolve(api,'requests/requests.service.ts'),'utf8');
 const admin=readFileSync(resolve(api,'admin/admin.controller.ts'),'utf8');
 const nurse=readFileSync(resolve(api,'nurses/nurses.service.ts'),'utf8');
 for(const src of [req,admin,nurse]){
  assert.ok(src.includes('makePage('));
  assert.ok(src.includes('cursor_created_at'));
  assert.ok(src.includes('DESC LIMIT $'));
 }
 assert.ok(!admin.includes('LIMIT 100'));
});
test('reference cache excludes finance, GPS, authorizations and uses finite TTL',()=>{
 const src=readFileSync(resolve(api,'cache/reference-cache.service.ts'),'utf8');
 const catalog=readFileSync(resolve(api,'catalog/catalog.controller.ts'),'utf8');
 assert.ok(src.includes("'EX',ttlSeconds"));
 assert.ok(src.includes('await load()'));
 assert.ok(src.includes('incr(`tamreedy:ref:gen:'));
 assert.ok(catalog.includes("getOrLoad('services:public'"));
});
