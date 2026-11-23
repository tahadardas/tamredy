/** Integration test requires a disposable PostgreSQL database with migration applied.
 * Run manually: TEST_DATABASE_URL=... node --test apps/api/tests/concurrency.integration.mjs
 * NODE_ENV=production is not allowed for this test.
 */
import {test} from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import {randomUUID} from 'node:crypto';
const databaseUrl = process.env.TEST_DATABASE_URL;
if (databaseUrl && (process.env.NODE_ENV === 'production' || databaseUrl === process.env.DATABASE_URL)) {
  throw new Error('Concurrency tests require a disposable database separate from DATABASE_URL');
}
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

test('ten simultaneous acceptors and a cancel/accept race leave one durable outcome', { skip: !databaseUrl }, async (t) => {
  const {DispatchService} = await import('../dist/dispatch/dispatch.service.js');
  const {cancelRequest} = await import('../dist/requests/cancellation.service.js');
  const pool = new pg.Pool({connectionString:databaseUrl,max:12,statement_timeout:15000});
  const ids = {patient:randomUUID(), beneficiary:randomUUID(), service:randomUUID()};
  const requests = [randomUUID(),randomUUID()];
  const workers = Array.from({length:10}, () => ({user:randomUUID(),nurse:randomUUID()}));
  const userIds = [ids.patient,...workers.map(worker => worker.user)];
  const nurseIds = workers.map(worker => worker.nurse);
  const db = {
    query: pool.query.bind(pool),
    async transaction(run) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const result = await run(client);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    },
  };

  t.after(async () => {
    try {
      await db.transaction(async client => {
        for (const table of ['outbox_events','request_events','request_cancellations','request_offers','dispatch_jobs','request_assignments']) {
          const key = table === 'outbox_events' ? 'aggregate_id' : 'request_id';
          await client.query(`DELETE FROM ${table} WHERE ${key}=ANY($1::uuid[])`,[requests]);
        }
        await client.query('DELETE FROM care_requests WHERE id=ANY($1::uuid[])',[requests]);
        for (const table of ['nurse_locations','nurse_skills','nurse_credentials']) {
          await client.query(`DELETE FROM ${table} WHERE nurse_id=ANY($1::uuid[])`,[nurseIds]);
        }
        await client.query('DELETE FROM nurses WHERE id=ANY($1::uuid[])',[nurseIds]);
        await client.query('DELETE FROM services WHERE id=$1',[ids.service]);
        await client.query('DELETE FROM beneficiaries WHERE id=$1',[ids.beneficiary]);
        await client.query('DELETE FROM users WHERE id=ANY($1::uuid[])',[userIds]);
      });
    } finally {
      await pool.end();
    }
  });

  const location = 'ST_SetSRID(ST_MakePoint(36.25,33.50),4326)::geography';
  await db.transaction(async client => {
    await client.query(`
      INSERT INTO users(id,phone_e164,role)
      SELECT id,'test-'||id::text,CASE WHEN id=$2 THEN 'PATIENT' ELSE 'NURSE' END
      FROM unnest($1::uuid[]) AS id
    `,[userIds,ids.patient]);
    await client.query("INSERT INTO beneficiaries(id,owner_user_id,display_name,consent_status) VALUES($1,$2,'اختبار','GRANTED')",
      [ids.beneficiary,ids.patient]);
    await client.query("INSERT INTO services(id,code,title_ar,price_amount) VALUES($1,$2,'خدمة اختبارية',100)",
      [ids.service,`test-${ids.service}`]);
    await client.query(`
      INSERT INTO nurses(id,user_id,verified,availability_intent,work_status,last_heartbeat_at)
      SELECT nurse_id,user_id,true,'AVAILABLE','AVAILABLE',now() FROM unnest($1::uuid[],$2::uuid[]) pair(nurse_id,user_id)
    `,[nurseIds,workers.map(worker => worker.user)]);
    await client.query("INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved) SELECT id,'test',now()+interval '1 day',true FROM unnest($1::uuid[]) AS id",[nurseIds]);
    await client.query('INSERT INTO nurse_skills(nurse_id,service_id,approved) SELECT id,$2,true FROM unnest($1::uuid[]) AS id',[nurseIds,ids.service]);
    await client.query(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m) SELECT id,${location},20 FROM unnest($1::uuid[]) AS id`,[nurseIds]);
    await client.query(`
      INSERT INTO care_requests(id,requester_user_id,beneficiary_id,service_id,location,location_source,address_text,
        price_amount,currency_code,commission_bps,search_started_at,search_expires_at,search_radius_meters,
        search_max_heartbeat_seconds,search_max_location_seconds,search_max_accuracy_meters)
      SELECT id,$2,$3,$4,${location},'MANUAL_PIN','اختبار',100,'SYP',2000,
        now(),now()+interval '1 minute',3000,60,120,100 FROM unnest($1::uuid[]) AS id
    `,[requests,ids.patient,ids.beneficiary,ids.service]);
    await client.query(`
      INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
      SELECT r.id,n.id,1,r.search_expires_at FROM care_requests r CROSS JOIN nurses n
      WHERE r.id=ANY($1::uuid[]) AND n.id=ANY($2::uuid[])
    `,[requests,nurseIds]);
  });
  const dispatch = new DispatchService(db);
  const offers = async (request) => (await db.query(`
    SELECT n.user_id,o.id FROM request_offers o JOIN nurses n ON n.id=o.nurse_id WHERE o.request_id=$1
  `,[request])).rows;
  const first = await offers(requests[0]);
  const results = await Promise.allSettled(first.map(offer => dispatch.accept(offer.user_id,offer.id)));
  assert.equal(results.filter(result => result.status==='fulfilled').length,1);
  const winner = first[results.findIndex(result => result.status==='fulfilled')];
  assert.equal((await dispatch.accept(winner.user_id,winner.id)).replayed,true);
  assert.equal((await db.query("SELECT 1 FROM request_assignments WHERE request_id=$1 AND status='ACTIVE'",[requests[0]])).rowCount,1);

  const second = (await offers(requests[1])).find(offer => offer.user_id!==winner.user_id);
  const race = await Promise.allSettled([
    dispatch.accept(second.user_id,second.id),
    db.transaction(client => cancelRequest(client,ids.patient,requests[1],{reasonCode:'OTHER',idempotencyKey:randomUUID()})),
  ]);
  assert.equal(race[1].status,'fulfilled');
  assert.equal((await db.query('SELECT status FROM care_requests WHERE id=$1',[requests[1]])).rows[0].status,'CANCELLED');
  assert.equal((await db.query("SELECT 1 FROM request_assignments WHERE request_id=$1 AND status='ACTIVE'",[requests[1]])).rowCount,0);
  assert.equal((await db.query("SELECT 1 FROM request_offers WHERE request_id=$1 AND status='OPEN'",[requests[1]])).rowCount,0);
  assert.equal((await db.query('SELECT 1 FROM request_cancellations WHERE request_id=$1',[requests[1]])).rowCount,1);
});
