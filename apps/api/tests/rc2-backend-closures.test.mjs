import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
import {NurseCalendarService} from '../dist/scheduling/calendar.service.js';
import {NurseEligibilityEngine} from '../dist/dispatch/nurse-eligibility.engine.js';
import {FinancialReservationsService,reconcileCommission} from '../dist/wallet/financial-reservations.service.js';
import {BillingService} from '../dist/pricing/billing.service.js';
import {ClinicalApprovalService} from '../dist/clinical-approvals/clinical-approval.service.js';
import {ClinicalApprovalRepository} from '../dist/clinical-approvals/clinical-approval.repository.js';
import {LedgerService} from '../dist/wallet/ledger.service.js';
import {readLiveLocation,validLocation} from '../../../packages/backend-policy/live-location.mjs';
const root=resolve(import.meta.dirname,'../../..');
async function buildPglite() {
  const pg = new PGlite({ extensions: { pgcrypto } });
  await pg.exec('CREATE EXTENSION IF NOT EXISTS pgcrypto;');
  const strip = (s) =>
    s
      .replace(/CREATE EXTENSION[^;]*;/gi, '')
      .replace(/geography\(Point,\s*4326\)/gi, 'double precision')
      .replace(/::geography/gi, '::double precision')
      .replace(/CREATE INDEX[^;]*USING\s+gist[^;]*;/gi, '')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/gi, '')
      .replace(/CREATE INDEX[^;]*gin_trgm_ops[^;]*;/gi, '')
      .replace(/ALTER TABLE [a-z_]+ ADD CONSTRAINT ex_[^;]*DEFERRABLE INITIALLY IMMEDIATE;/gi, '')
      .replace(/ALTER TABLE [a-z_]+ ADD CONSTRAINT ex_[^;]*USING gist[^;]*;/gi, '');

  await pg.exec('CREATE TABLE IF NOT EXISTS schema_migrations(name text PRIMARY KEY, applied_at timestamptz not null default now());');
  await pg.exec(`
    CREATE FUNCTION ST_DWithin(double precision,double precision,double precision)
      RETURNS boolean LANGUAGE sql AS $$ SELECT abs($1-$2)<=$3 $$;
    CREATE FUNCTION ST_Distance(double precision,double precision)
      RETURNS numeric LANGUAGE sql AS $$ SELECT abs($1-$2)::numeric $$;
    CREATE DOMAIN geometry AS double precision;
    CREATE DOMAIN geography AS double precision;
    CREATE FUNCTION ST_Y(geometry) RETURNS double precision LANGUAGE sql AS $$ SELECT 33.5::double precision $$;
    CREATE FUNCTION ST_X(geometry) RETURNS double precision LANGUAGE sql AS $$ SELECT 36.25::double precision $$;
    CREATE FUNCTION ST_SetSRID(double precision, integer) RETURNS double precision LANGUAGE sql AS $$ SELECT $1 $$;
    CREATE FUNCTION ST_MakePoint(double precision, double precision) RETURNS double precision LANGUAGE sql AS $$ SELECT $1 $$;
    CREATE FUNCTION geo_knn_dist(double precision, double precision) RETURNS double precision LANGUAGE sql AS $$ SELECT abs($1-$2) $$;
    CREATE OPERATOR <-> (LEFTARG = double precision, RIGHTARG = double precision, FUNCTION = geo_knn_dist);
  `);
  const migrationsDir = resolve(root, 'infra/db/migrations');
  for (const file of readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()) {
    // Skip duplicate-numbered admin_scheduled_visit_removal ONLY if superseded or run cleanly; test all sorted SQL!
    await pg.exec(strip(readFileSync(resolve(migrationsDir, file), 'utf8')));
    await pg.query('INSERT INTO schema_migrations(name) VALUES($1) ON CONFLICT DO NOTHING', [file]);
  }

  let chain = Promise.resolve();
  const db = {
    query: (sql, p = []) => pg.query(sql, p),
    poolStats: () => ({ max: 20, totalCount: 1, idleCount: 1, waitingCount: 0 }),
    transaction: (run) => {
      const next = chain.then(async () => {
        await pg.query('BEGIN');
        try {
          const r = await run({ query: (s, p = []) => pg.query(s, p) });
          await pg.query('COMMIT');
          return r;
        } catch (e) {
          await pg.query('ROLLBACK');
          throw e;
        }
      });
      chain = next.catch(() => {});
      return next;
    },
  };
  return { pg, db };
}


for (const financialModel of ['PREPAID','RECEIVABLES','HYBRID']) {
  for (const finalCommission of [500n,1000n,1500n]) {
    test(`RC2-016 ${financialModel} reconciles final commission ${finalCommission}`,()=>{
      const result=reconcileCommission({financialModel,finalCommission,reservedPrepaid:700n,reservedCredit:300n,
        prepaidBalance:700n,creditAvailable:300n});
      assert.equal(result.prepaidApplied+result.creditApplied+result.uncoveredCommission,finalCommission);
      assert.equal(result.releasedAmount,finalCommission<1000n?1000n-finalCommission:0n);
      if (financialModel==='PREPAID') assert.equal(result.creditApplied,0n);
      if (financialModel==='RECEIVABLES') assert.equal(result.prepaidApplied,0n);
      if (finalCommission===1500n) assert.ok(result.uncoveredCommission>0n);
    });
  }
}

test('RC2-021/023 shared reader uses Redis and requires explicit fallback policy',async()=>{
  const now=Date.now();let postgresReads=0;
  const db={async query(){postgresReads++;return {rows:[{latitude:33.5,longitude:36.2,accuracy_m:12,
    recorded_at:new Date(now-1000),received_at:new Date(now-1000),captured_at:new Date(now-1000),session_id:'session'}]};}};
  const redis={async hgetall(){return {latitude:'33.51',longitude:'36.25',accuracyMeters:'7',
    capturedAtEpochMs:String(now),receivedAtEpochMs:String(now),sequenceNumber:'1',sessionId:'session'};}};
  const live=await readLiveLocation({nurseId:'n',redis,db,redisEnabled:true,allowPostgresFallback:false});
  assert.equal(live.source,'redis');assert.equal(live.latitude,33.51);assert.equal(postgresReads,0);
  assert.equal(validLocation(live,30,10,now),true);
  assert.equal(validLocation({...live,capturedAt:new Date(now-31000)},30,10,now),false);
  assert.equal(validLocation({...live,accuracyMeters:11},30,10,now),false);
  const down={async hgetall(){throw new Error('redis down');}};
  await assert.rejects(readLiveLocation({nurseId:'n',redis:down,db,redisEnabled:true,allowPostgresFallback:false}));
  assert.equal(postgresReads,0);
  const fallback=await readLiveLocation({nurseId:'n',redis:down,db,redisEnabled:true,allowPostgresFallback:true});
  assert.equal(fallback.source,'postgres');assert.equal(postgresReads,1);
  const missing=await readLiveLocation({nurseId:'n',redis:{async hgetall(){return {}}},db,redisEnabled:true,allowPostgresFallback:true});
  assert.equal(missing,null);assert.equal(postgresReads,1);
});

test('RC2 backend SQL contracts on isolated PostgreSQL emulator (no real lock/PostGIS proof)',async t=>{
  const {pg,db}=await buildPglite();t.after(()=>pg.close());
  const patient=(await pg.query(`INSERT INTO users(phone_e164,role,display_name) VALUES('+963900990001','PATIENT','مريض اختبار') RETURNING id`)).rows[0].id;
  const nurseUser=(await pg.query(`INSERT INTO users(phone_e164,role,display_name) VALUES('+963900990002','NURSE','ممرض اختبار') RETURNING id`)).rows[0].id;
  const admin=(await pg.query(`INSERT INTO users(phone_e164,role,display_name) VALUES('+963900990003','ADMIN','مسؤول اختبار') RETURNING id`)).rows[0].id;
  const beneficiary=(await pg.query(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'مستفيد','GRANTED') RETURNING id`,[patient])).rows[0].id;
  const service=(await pg.query(`INSERT INTO services(code,title_ar,active,dispatch_approved,price_amount,currency_code,included_minutes,commission_bps) VALUES('RC2_TEST','رعاية منزلية',true,true,1000,'SYP_NEW',45,2000) RETURNING id`)).rows[0].id;
  const nurse=(await pg.query(`INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at) VALUES($1,true,'AVAILABLE','AVAILABLE',now()) RETURNING id`,[nurseUser])).rows[0].id;
  const session=(await pg.query(`INSERT INTO device_sessions(user_id,device_id,platform,app_kind) VALUES($1,'rc2-test','android','nurse') RETURNING id`,[nurseUser])).rows[0].id;
  await pg.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved) VALUES($1,'RC2-LIC',now()+interval '30 days',true)`,[nurse]);
  await pg.query(`INSERT INTO nurse_skills(nurse_id,service_id,approved) VALUES($1,$2,true)`,[nurse,service]);
  await pg.query(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m,recorded_at,captured_at,received_at,sequence_number,session_id,location_source) VALUES($1,0,10,now(),now(),now(),1,$2,'GPS')`,[nurse,session]);
  let sequence=0;
  const request=async(status='OFFERING',mode='INSTANT')=>{
    const id=(await pg.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,booking_mode) VALUES($1,$2,$3,0,'GPS_CONFIRMED','دمشق',$4,1000,'SYP_NEW',2000,$5) RETURNING id`,[patient,beneficiary,service,status,mode])).rows[0].id;
    await pg.query(`INSERT INTO care_request_items(request_id,service_id,quantity,unit_price,expected_minutes) VALUES($1,$2,1,1000,45)`,[id,service]);sequence++;return id;
  };
  const engine=new NurseEligibilityEngine(db);
  const instant=await request();
  await t.test('RC2-015 legacy account cannot fund a currency-specific assignment',async()=>{
    await pg.query(`INSERT INTO nurse_financial_accounts(nurse_id,financial_model,credit_limit,prepaid_balance) VALUES($1,'PREPAID',0,5000)`,[nurse]);
    const result=await engine.evaluate(nurse,instant,{context:'ASSIGN'});
    assert.ok(result.reasons.some(r=>r.code==='NURSE_FINANCIAL_ACCOUNT_REQUIRED'));
    const legacy=(await pg.query('SELECT * FROM nurse_financial_accounts WHERE nurse_id=$1',[nurse])).rows[0];
    assert.equal(Number(legacy.prepaid_balance),5000);assert.equal(legacy.reconciliation_required,true);
  });
  const account=(await pg.query(`INSERT INTO nurse_financial_currency_accounts(nurse_id,currency_code,financial_model,credit_limit,prepaid_balance) VALUES($1,'SYP_NEW','HYBRID',1000,1000) RETURNING id`,[nurse])).rows[0].id;
  await t.test('RC2-022 policy accepts fresh qualified matching-currency nurse',async()=>{
    assert.deepEqual(await engine.evaluate(nurse,instant,{context:'ASSIGN'}),{eligible:true,reasons:[]});
  });
  await t.test('RC2-021 API cannot silently bypass the authoritative location reader',async()=>{
    for (const locations of [
      {async getNurseLocation(){return null;}},
      {async getNurseLocation(){throw new Error('Redis unavailable and fallback denied');}},
    ]) {
      const guarded=new NurseEligibilityEngine(db,locations);
      const assessment=await guarded.evaluate(nurse,instant,{context:'ASSIGN'});
      assert.equal(assessment.eligible,false);
      assert.ok(assessment.reasons.some(reason=>reason.code==='LOCATION_REQUIRED'));
    }
  });
  await t.test('RC2-022 policy rejects unreviewed requests and old Redis coordinates',async()=>{
    await pg.query(`UPDATE care_requests SET clinical_approval_status='PENDING' WHERE id=$1`,[instant]);
    const result=await engine.evaluate(nurse,instant,{context:'ASSIGN'});
    assert.ok(result.reasons.some(r=>r.code==='CLINICAL_APPROVAL_REQUIRED'));
    await pg.query(`UPDATE care_requests SET clinical_approval_status='NOT_REQUIRED' WHERE id=$1`,[instant]);
    const live={latitude:33.5,longitude:36.2,accuracyMeters:5,capturedAt:new Date(Date.now()-200000).toISOString(),receivedAt:new Date().toISOString(),sessionId:session};
    const reasons=(await pg.query(`SELECT nurse_eligibility_reasons($1,$2,'OFFER',NULL,NULL,$3::jsonb) AS reasons`,[nurse,instant,JSON.stringify(live)])).rows[0].reasons;
    assert.ok(reasons.includes('LOCATION_STALE'));
  });
  const future=await request('ASSIGNED','SCHEDULED');
  const planned=new Date(Date.now()+86400000);const plannedEnd=new Date(planned.getTime()+45*60000);
  const assignment=(await pg.query(`INSERT INTO request_assignments(request_id,nurse_id,status,accepted_at,planned_start_at,planned_end_at,service_duration_minutes) VALUES($1,$2,'RESERVED',now(),$3,$4,45) RETURNING id`,[future,nurse,planned.toISOString(),plannedEnd.toISOString()])).rows[0].id;
  await t.test('RC2-012 calendar follows planned date, includes partial range overlap and snapshot duration',async()=>{
    const calendar=new NurseCalendarService(db);
    const result=await calendar.getSchedule(nurseUser,new Date(planned.getTime()+1000).toISOString(),new Date(plannedEnd.getTime()+1000).toISOString());
    assert.equal(result.visits.length,1);assert.equal(new Date(result.visits[0].plannedStartAt).getTime(),planned.getTime());
    assert.equal(Number(result.visits[0].expected_minutes),45);
    const today=await calendar.getSchedule(nurseUser,new Date(Date.now()-60000).toISOString(),new Date(Date.now()+60000).toISOString());
    assert.equal(today.visits.length,0);
  });
  await t.test('RC2-013 adding conflicting block rejects without inserting',async()=>{
    const calendar=new NurseCalendarService(db);
    await assert.rejects(calendar.addBlock(nurseUser,{startTime:planned.toISOString(),endTime:plannedEnd.toISOString()}),e=>e.getResponse().code==='CONFIRMED_VISIT_CONFLICTS_WITH_BLOCK');
    assert.equal((await pg.query('SELECT * FROM nurse_calendar_blocks')).rows.length,0);
  });
  await t.test('RC2-014 future reservation ignores a provably non-overlapping active visit',async()=>{
    const current=await request('ASSIGNED');
    await pg.query(`INSERT INTO request_assignments(request_id,nurse_id,status,planned_start_at,planned_end_at,service_duration_minutes) VALUES($1,$2,'ACTIVE',now(),now()+interval '45 minutes',45)`,[current,nurse]);
    const target=await request('OPEN_FOR_PROPOSALS','OPEN');
    const later=new Date(Date.now()+4*3600000);const end=new Date(later.getTime()+45*60000);
    const result=await engine.evaluate(nurse,target,{context:'ASSIGN',proposedStart:later,proposedEnd:end});
    assert.equal(result.eligible,true,JSON.stringify(result.reasons));
    await pg.query(`UPDATE request_assignments SET planned_start_at=NULL,planned_end_at=NULL WHERE request_id=$1`,[current]);
    const unknown=await engine.evaluate(nurse,target,{context:'ASSIGN',proposedStart:later,proposedEnd:end});
    assert.ok(unknown.reasons.some(r=>r.code==='NURSE_HAS_ACTIVE_EXECUTION'));
    await pg.query(`UPDATE request_assignments SET status='RELEASED' WHERE request_id=$1`,[current]);
  });
  await t.test('RC2-016 full final commission survives insufficient prepaid/credit',async()=>{
    const billRequest=await request('COMPLETED');
    const a=(await pg.query(`INSERT INTO request_assignments(request_id,nurse_id,status) VALUES($1,$2,'RELEASED') RETURNING id`,[billRequest,nurse])).rows[0].id;
    const visit=(await pg.query(`INSERT INTO visits(assignment_id,arrived_at,started_at,completed_at,outcome) VALUES($1,now(),now(),now(),'COMPLETED') RETURNING id`,[a])).rows[0].id;
    const invoice=(await pg.query(`INSERT INTO invoices(request_id,visit_id,status,currency_code,subtotal,discount_amount,surcharge_amount,distance_fee,tax_amount,total_amount,pricing_snapshot) VALUES($1,$2,'ISSUED','SYP_NEW',1000,0,0,0,0,1000,'{}') RETURNING id`,[billRequest,visit])).rows[0].id;
    await pg.query(`UPDATE nurse_financial_currency_accounts SET prepaid_balance=10,credit_limit=5,reserved_balance=10 WHERE id=$1`,[account]);
    const reservation=(await pg.query(`INSERT INTO financial_reservations(account_id,amount,reference_id,nurse_id,prepaid_amount,credit_amount,currency_code,currency_account_id) VALUES('RC2_TEST',10,$1,$2,10,0,'SYP_NEW',$3) RETURNING id`,[billRequest,nurse,account])).rows[0].id;
    await db.transaction(client=>new FinancialReservationsService().commitForInvoice(client,new LedgerService(),billRequest,invoice,30,'SYP_NEW'));
    const resolution=(await pg.query('SELECT * FROM commission_reconciliations WHERE reservation_id=$1',[reservation])).rows[0];
    assert.equal(Number(resolution.final_commission),30);assert.equal(Number(resolution.prepaid_applied),10);
    assert.equal(Number(resolution.credit_applied),5);assert.equal(Number(resolution.uncovered_commission),15);
    assert.equal((await pg.query('SELECT settlement_required FROM nurse_financial_currency_accounts WHERE id=$1',[account])).rows[0].settlement_required,true);
    assert.equal((await pg.query('SELECT status FROM financial_reservations WHERE id=$1',[reservation])).rows[0].status,'COMMITTED');
  });
  await t.test('RC2-017 an unbalanced invoice fails and rolls back without rounding journal',async()=>{
    const id=await request('COMPLETED');
    const a=(await pg.query(`INSERT INTO request_assignments(request_id,nurse_id,status) VALUES($1,$2,'RELEASED') RETURNING id`,[id,nurse])).rows[0].id;
    const v=(await pg.query(`INSERT INTO visits(assignment_id,started_at,completed_at,outcome) VALUES($1,now(),now(),'COMPLETED') RETURNING id`,[a])).rows[0].id;
    await pg.query(`UPDATE care_request_items SET item_status='COMPLETED',performed_quantity=1 WHERE request_id=$1`,[id]);
    const billing=new BillingService(new LedgerService(),{},{});
    const bill={timeGross:1000,gross:1000,discount:0,surcharge:0,distanceFee:0,tax:0,due:1000,commission:200,nurseEarning:799,minutes:45};
    await assert.rejects(db.transaction(c=>billing.issueInvoice(c,id,v,nurse,'SYP_NEW',bill,{})),e=>e.getResponse().code==='BILLING_INVARIANT_VIOLATION');
    assert.equal((await pg.query('SELECT * FROM invoices WHERE request_id=$1',[id])).rows.length,0);
    assert.equal((await pg.query(`SELECT * FROM financial_ledger_entries WHERE account_id='ROUNDING_ADJUSTMENTS'`)).rows.length,0);
  });
  await t.test('RC2-018 no-service settlement intentionally has no invoice and releases funds',async()=>{
    const id=await request('COMPLETED');
    const a=(await pg.query(`INSERT INTO request_assignments(request_id,nurse_id,status,reason) VALUES($1,$2,'RELEASED','PATIENT_REFUSED') RETURNING id`,[id,nurse])).rows[0].id;
    const v=(await pg.query(`INSERT INTO visits(assignment_id,started_at,completed_at,outcome) VALUES($1,now(),now(),'NOT_PERFORMED') RETURNING id`,[a])).rows[0].id;
    await pg.query(`INSERT INTO financial_reservations(account_id,amount,reference_id,nurse_id,prepaid_amount,credit_amount,currency_code,currency_account_id) VALUES('RC2_NO_SERVICE',5,$1,$2,0,5,'SYP_NEW',$3)`,[id,nurse,account]);
    await db.transaction(c=>new BillingService(new LedgerService(),{},{}).settleNoServiceVisit(c,{requestId:id,visitId:v,nurseId:nurse,currencyCode:'SYP_NEW',actorUserId:nurseUser,reason:'PATIENT_REFUSED'}));
    assert.equal((await pg.query('SELECT payment_status FROM care_requests WHERE id=$1',[id])).rows[0].payment_status,'PAID');
    assert.equal((await pg.query('SELECT * FROM invoices WHERE request_id=$1',[id])).rows.length,0);
    assert.equal((await pg.query('SELECT status FROM financial_reservations WHERE reference_id=$1',[id])).rows[0].status,'RELEASED');
  });
  await t.test('RC2-020 clinical approval preserves patient arrival constraint and expired approval rolls back',async()=>{
    const clinical=new ClinicalApprovalService(db,new ClinicalApprovalRepository(db),{});
    const futureId=await request('OPEN_FOR_PROPOSALS','OPEN');
    const deadline=new Date(Date.now()+2*3600000);
    await pg.query(`UPDATE care_requests SET clinical_approval_status='PENDING',open_duration_minutes=45,
      original_latest_acceptable_arrival_at=$2,latest_acceptable_arrival_at=$2 WHERE id=$1`,[futureId,deadline.toISOString()]);
    await pg.query(`INSERT INTO request_clinical_reviews(request_id,required_prescription,required_clinical_review) VALUES($1,false,true)`,[futureId]);
    await pg.query(`INSERT INTO request_clinical_evidence(request_id,uploaded_by,evidence_type,storage_key,original_filename,mime_type,file_size_bytes,sha256)
      VALUES($1,$2,'CLINICAL_REPORT','rc2-future-evidence','تقرير.pdf','application/pdf',10,repeat('a',64))`,[futureId,patient]);
    await clinical.decide(admin,futureId,{decision:'APPROVE',note:'موافقة طبية موثقة'});
    const approved=(await pg.query('SELECT latest_acceptable_arrival_at FROM care_requests WHERE id=$1',[futureId])).rows[0];
    assert.equal(new Date(approved.latest_acceptable_arrival_at).getTime(),deadline.getTime());
    const expired=await request('OPEN_FOR_PROPOSALS','OPEN');
    await pg.query(`UPDATE care_requests SET clinical_approval_status='PENDING',original_latest_acceptable_arrival_at=now()-interval '1 minute' WHERE id=$1`,[expired]);
    await pg.query(`INSERT INTO request_clinical_reviews(request_id,required_prescription,required_clinical_review) VALUES($1,false,true)`,[expired]);
    await pg.query(`INSERT INTO request_clinical_evidence(request_id,uploaded_by,evidence_type,storage_key,original_filename,mime_type,file_size_bytes,sha256)
      VALUES($1,$2,'CLINICAL_REPORT','rc2-expired-evidence','تقرير.pdf','application/pdf',10,repeat('b',64))`,[expired,patient]);
    await assert.rejects(clinical.decide(admin,expired,{decision:'APPROVE',note:'موافقة مشروطة'}),e=>e.getResponse().code==='ARRIVAL_WINDOW_EXPIRED_REQUIRES_RESCHEDULING');
    assert.equal((await pg.query('SELECT status FROM request_clinical_reviews WHERE request_id=$1',[expired])).rows[0].status,'PENDING');
  });

});
