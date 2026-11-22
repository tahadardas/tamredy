/** Integration test requires a disposable PostgreSQL database with migration applied.
 * Run manually: DATABASE_URL=... node --test apps/api/tests/concurrency.integration.mjs
 * NODE_ENV=production is not allowed for this test.
 */
import {test} from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import {randomUUID} from 'node:crypto';
const databaseUrl=process.env.TEST_DATABASE_URL;
test('database partial unique indexes prevent double assignment under concurrent INSERTs', {skip:!databaseUrl}, async()=>{
 const pool=new pg.Pool({connectionString:databaseUrl,max:5});
 const one=await pool.connect(),two=await pool.connect();
 const ids={u1:randomUUID(),u2:randomUUID(),p:randomUUID(),b:randomUUID(),s:randomUUID(),n1:randomUUID(),n2:randomUUID(),r:randomUUID()};
 try {
  await one.query('BEGIN');
  await one.query(`INSERT INTO users(id,phone_e164,role) VALUES($1,$2,'PATIENT'),($3,$4,'NURSE'),($5,$6,'NURSE')`,[ids.p,'+999'+ids.p.slice(0,10),ids.u1,'+999'+ids.u1.slice(0,10),ids.u2,'+999'+ids.u2.slice(0,10)]);
  await one.query(`INSERT INTO beneficiaries(id,owner_user_id,display_name,consent_status) VALUES($1,$2,'Test','GRANTED')`,[ids.b,ids.p]);
  await one.query(`INSERT INTO services(id,code,title_ar,price_amount) VALUES($1,$2,'Test',100)`,[ids.s,'t'+ids.s]);
  await one.query(`INSERT INTO nurses(id,user_id) VALUES($1,$2),($3,$4)`,[ids.n1,ids.u1,ids.n2,ids.u2]);
  await one.query(`INSERT INTO care_requests(id,requester_user_id,beneficiary_id,service_id,location,location_source,address_text,price_amount,currency_code,commission_bps)
   VALUES($1,$2,$3,$4,ST_SetSRID(ST_MakePoint(36.2,33.5),4326)::geography,'GPS_CONFIRMED','test',100,'SYP_NEW',2000)`,[ids.r,ids.p,ids.b,ids.s]);
  await one.query('COMMIT');
  await one.query('BEGIN');
  await one.query(`INSERT INTO request_assignments(request_id,nurse_id) VALUES($1,$2)`,[ids.r,ids.n1]);
  const second=two.query(`INSERT INTO request_assignments(request_id,nurse_id) VALUES($1,$2)`,[ids.r,ids.n2]).then(()=>null,e=>e);
  await one.query('COMMIT');
  const error=await second;
  assert.equal(error?.code,'23505');
 } finally {
  await one.query('ROLLBACK').catch(()=>{});
  // Clean test fixtures in FK-safe order, including optional inserted assignment.
  await one.query('DELETE FROM request_assignments WHERE request_id=$1',[ids.r]).catch(()=>{});
  await one.query('DELETE FROM care_requests WHERE id=$1',[ids.r]).catch(()=>{});
  await one.query('DELETE FROM nurses WHERE id=ANY($1::uuid[])',[[ids.n1,ids.n2]]).catch(()=>{});
  await one.query('DELETE FROM services WHERE id=$1',[ids.s]).catch(()=>{});
  await one.query('DELETE FROM beneficiaries WHERE id=$1',[ids.b]).catch(()=>{});
  await one.query('DELETE FROM users WHERE id=ANY($1::uuid[])',[[ids.p,ids.u1,ids.u2]]).catch(()=>{});
  one.release();two.release();await pool.end();
 }
});
