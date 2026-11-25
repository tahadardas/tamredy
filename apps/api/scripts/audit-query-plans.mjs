/** Run on a disposable/staging database, never automatically against production.
 * Usage: TEST_DATABASE_URL=postgres://... AUDIT_USER_ID=<existing-user-uuid> node apps/api/scripts/audit-query-plans.mjs
 */
import pg from 'pg';
const url=process.env.TEST_DATABASE_URL;
if(!url)throw new Error('TEST_DATABASE_URL is mandatory; use staging or a disposable database');
if(process.env.NODE_ENV==='production')throw new Error('Refusing to run performance audit in NODE_ENV=production');
const client=new pg.Client({connectionString:url,statement_timeout:10000,query_timeout:12000});
await client.connect();
try{
  const indexes=await client.query(`SELECT tablename,indexname,indexdef FROM pg_indexes
    WHERE schemaname='public' AND tablename IN
    ('care_requests','nurses','nurse_locations','request_offers','request_assignments',
     'services','beneficiaries','nurse_credentials','nurse_skills','financial_ledger_entries')
    ORDER BY tablename,indexname`);
  console.log(`Existing tracked indexes: ${indexes.rowCount}`);
  for(const row of indexes.rows)console.log(`${row.tablename} / ${row.indexname}`);
  const expected=['idx_requests_owner_created_id','idx_requests_created_id','idx_requests_status_created_id',
    'idx_nurse_locations_gist','idx_credentials_nurse_expiry','idx_skills_service_approved_nurse',
    'idx_assignments_nurse_history','uq_open_assignment_per_request',
    'uq_executing_assignment_per_nurse','idx_ledger_transaction','idx_marketplace_approved_created'];
  const found=new Set(indexes.rows.map(r=>r.indexname));
  const missing=expected.filter(x=>!found.has(x));
  if(missing.length){console.error('Missing index(es):',missing.join(', '));process.exitCode=1;}
  if(process.env.AUDIT_USER_ID){
    if(!/^[a-f0-9-]{36}$/i.test(process.env.AUDIT_USER_ID))throw new Error('AUDIT_USER_ID must be UUID');
    const plan=await client.query(`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      SELECT cr.id,cr.status,cr.created_at,s.title_ar,b.display_name
      FROM care_requests cr
      JOIN services s ON s.id=cr.service_id JOIN beneficiaries b ON b.id=cr.beneficiary_id
      WHERE cr.requester_user_id=$1 ORDER BY cr.created_at DESC,cr.id DESC LIMIT 21`,[process.env.AUDIT_USER_ID]);
    console.log('STAGING PLAN:',JSON.stringify(plan.rows[0]['QUERY PLAN'],null,2));
  }else{
    console.log('Set AUDIT_USER_ID to print a representative EXPLAIN ANALYZE plan');
  }
}finally{await client.end();}
