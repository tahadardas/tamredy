import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {NurseCalendarService} from '../dist/scheduling/calendar.service.js';
import {DispatchService} from '../dist/dispatch/dispatch.service.js';
import {NurseEligibilityEngine} from '../dist/dispatch/nurse-eligibility.engine.js';
import {AssignmentOrchestrator} from '../dist/dispatch/assignment.orchestrator.js';

const url=process.env.TEST_DATABASE_URL;
function deferred(){let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};}
test('RC2-013 nurse-row lock serializes calendar blocks with atomic acceptance in both orders',{
  skip:!url&&'Requires explicit isolated PostgreSQL with all migrations',
},async t=>{
  const parsed=new URL(url);
  assert.ok(['127.0.0.1','localhost','[::1]'].includes(parsed.hostname));
  assert.match(parsed.pathname,/^\/tamreedy_test_\w+$/);
  const pool=new pg.Pool({connectionString:url,max:6,statement_timeout:10000});
  t.after(()=>pool.end());
  function database(barrier){return {query:pool.query.bind(pool),async transaction(run){
    const client=await pool.connect();
    try{
      await client.query('BEGIN');
      const q={async query(sql,params){
        const result=await client.query(sql,params);
        if(barrier&&/SELECT (?:id|\*) FROM nurses WHERE id=.*FOR UPDATE/i.test(sql)){
          barrier.acquired.resolve();await barrier.release.promise;
        }
        return result;
      }};
      const result=await run(q);await client.query('COMMIT');return result;
    }catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}
  }};}
  const db=database();
  for(const first of ['block','accept'])await t.test(first+' acquires the shared nurse lock first',async()=>{
    const tag=randomUUID();
    const patient=(await pool.query(`INSERT INTO users(phone_e164,role) VALUES($1,'PATIENT') RETURNING id`,['rc2-p-'+tag])).rows[0].id;
    const nurseUser=(await pool.query(`INSERT INTO users(phone_e164,role) VALUES($1,'NURSE') RETURNING id`,['rc2-n-'+tag])).rows[0].id;
    const beneficiary=(await pool.query(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'اختبار تزامن','GRANTED') RETURNING id`,[patient])).rows[0].id;
    const service=(await pool.query(`INSERT INTO services(code,title_ar,price_amount,dispatch_approved) VALUES($1,'خدمة اختبار التزامن',100,true) RETURNING id`,[tag])).rows[0].id;
    const nurse=(await pool.query(`INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at) VALUES($1,true,'AVAILABLE','AVAILABLE',now()) RETURNING id`,[nurseUser])).rows[0].id;
    const session=(await pool.query(`INSERT INTO device_sessions(user_id,device_id,app_kind) VALUES($1,$2,'nurse') RETURNING id`,[nurseUser,tag])).rows[0].id;
    await pool.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,approved,expires_at) VALUES($1,$2,true,now()+interval '1 year')`,[nurse,tag]);
    await pool.query(`INSERT INTO nurse_skills(nurse_id,service_id,approved) VALUES($1,$2,true)`,[nurse,service]);
    await pool.query(`INSERT INTO nurse_financial_currency_accounts(nurse_id,currency_code,financial_model,credit_limit) VALUES($1,'SYP_NEW','RECEIVABLES',100000)`,[nurse]);
    await pool.query(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m,captured_at,received_at,sequence_number,session_id,location_source)
      VALUES($1,ST_SetSRID(ST_MakePoint(36.25,33.50),4326)::geography,5,now(),now(),1,$2,'GPS')`,[nurse,session]);
    const request=(await pool.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,price_amount,currency_code,commission_bps)
      VALUES($1,$2,$3,ST_SetSRID(ST_MakePoint(36.25,33.50),4326)::geography,'MANUAL_PIN','اختبار',100,'SYP_NEW',2000) RETURNING id`,[patient,beneficiary,service])).rows[0].id;
    const offer=(await pool.query(`INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at) VALUES($1,$2,1,now()+interval '5 minutes') RETURNING id`,[request,nurse])).rows[0].id;
    const barrier={acquired:deferred(),release:deferred()};
    const held=database(barrier);
    const calendar=new NurseCalendarService(first==='block'?held:db);
    const dispatchDb=first==='accept'?held:db;
    const eligibility=new NurseEligibilityEngine(dispatchDb);
    const dispatch=new DispatchService(dispatchDb,eligibility,new AssignmentOrchestrator(eligibility));
    const block=()=>calendar.addBlock(nurseUser,{startTime:new Date(Date.now()-60000).toISOString(),endTime:new Date(Date.now()+45*60000).toISOString()});
    const accept=()=>dispatch.accept(nurseUser,offer);
    const leading=(first==='block'?block:accept)();
    await barrier.acquired.promise;
    let trailingSettled=false;
    const trailing=(first==='block'?accept:block)();
    trailing.then(()=>trailingSettled=true,()=>trailingSettled=true);
    await new Promise(resolve=>setTimeout(resolve,50));
    assert.equal(trailingSettled,false,'conflicting writer must wait for the same real PostgreSQL row lock');
    barrier.release.resolve();
    const results=await Promise.allSettled([leading,trailing]);
    assert.equal(results[0].status,'fulfilled');
    assert.equal(results[1].status,'rejected');
    assert.equal(results[1].reason.getStatus(),409);
    const counts=(await pool.query(`SELECT
      (SELECT count(*)::int FROM nurse_calendar_blocks WHERE nurse_id=$1) AS blocks,
      (SELECT count(*)::int FROM request_assignments WHERE request_id=$2 AND status='ACTIVE') AS assignments`,[nurse,request])).rows[0];
    assert.deepEqual(counts,first==='block'?{blocks:1,assignments:0}:{blocks:0,assignments:1});
  });
});
