import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {NestFactory} from '@nestjs/core';
import {ValidationPipe} from '@nestjs/common';
import jwt from 'jsonwebtoken';
import pg from 'pg';

const url=process.env.TEST_DATABASE_URL;
test('RC3 financial policy, genuine HTTP onboarding and settlement stay in the same currency', {
  skip:!url&&'Requires isolated PostgreSQL with RC3 migrations',
},async t=>{
  const parsed=new URL(url);
  assert.ok(['127.0.0.1','localhost','[::1]'].includes(parsed.hostname));
  assert.match(parsed.pathname,/^\/tamreedy_test_\w+$/);
  const settings=['DATABASE_URL','JWT_SECRET','NODE_ENV','REALTIME_ENABLED','REDIS_URL','LIVE_LOCATION_REDIS_ENABLED',
    'GUARDIAN_NIGHT_POLICY_ENABLED','LOCATION_POSTGRES_FALLBACK_ENABLED'];
  const original=Object.fromEntries(settings.map(key=>[key,process.env[key]]));
  t.after(()=>{for(const key of settings)if(original[key]===undefined)delete process.env[key];else process.env[key]=original[key];});
  Object.assign(process.env,{DATABASE_URL:parsed.href,JWT_SECRET:randomBytes(48).toString('hex'),NODE_ENV:'test',
    REALTIME_ENABLED:'false',REDIS_URL:'',LIVE_LOCATION_REDIS_ENABLED:'false',
    LOCATION_POSTGRES_FALLBACK_ENABLED:'true',GUARDIAN_NIGHT_POLICY_ENABLED:'false'});
  const {AppModule}=await import('../dist/app.module.js');
  const {DbService}=await import('../dist/db/db.service.js');
  const {LedgerService}=await import('../dist/wallet/ledger.service.js');
  const app=await NestFactory.create(AppModule,{logger:false,abortOnError:false});
  app.useGlobalPipes(new ValidationPipe({whitelist:true,forbidNonWhitelisted:true,transform:true,transformOptions:{enableImplicitConversion:true}}));
  await app.listen(0,'127.0.0.1');
  t.after(()=>app.close());
  const pool=new pg.Pool({connectionString:url});
  const q=(sql,args=[])=>pool.query(sql,args);
  t.after(async()=>{
    try { await q("UPDATE app_settings SET value='null'::jsonb WHERE key='nurse_financial_default_policy'"); }
    finally { await pool.end(); }
  });
  const base=await app.getUrl();
  const tag=randomUUID();
  const phone=(offset)=>'+999'+(5000000000n+BigInt('0x'+tag.slice(0,8))%4000000000n+BigInt(offset)).toString();
  const admin=(await q(`INSERT INTO users(phone_e164,role) VALUES($1,'ADMIN') RETURNING id`,[phone(0)])).rows[0].id;
  function bearer(user,session) {
    return jwt.sign(session?{dsi:session,sgen:1}:{},process.env.JWT_SECRET,{
      subject:user,issuer:process.env.JWT_ISSUER??'tamreedy-api',audience:process.env.JWT_AUDIENCE??'tamreedy-mobile',expiresIn:'5m'});
  }
  async function request(path,method,body,expected,token=bearer(admin),key=randomUUID()) {
    const response=await fetch(base+path,{method,headers:{authorization:'Bearer '+token,'content-type':'application/json','idempotency-key':key},
      ...(body === undefined?{}:{body:JSON.stringify(body)})});
    const value=await response.json();
    assert.equal(response.status,expected,String(value.code??value.message??''));
    return value;
  }
  await request('/v1/admin/system-settings/nurse_financial_default_policy','PUT',{enabled:false},200);
  const unconfigured=await request('/v1/admin/nurses/manage','POST',{phone:phone(1),displayName:'ممرض اختبار أول'},201);
  assert.equal(unconfigured.financialStatus,'FINANCIAL_SETUP_REQUIRED');
  const policy={currencyCode:'SYP_NEW',financialModel:'RECEIVABLES',creditLimit:'100'};
  await request('/v1/admin/system-settings/nurse_financial_default_policy','PUT',policy,200);
  const created=await request('/v1/admin/nurses/manage','POST',{phone:phone(2),displayName:'ممرض اختبار ثان'},201);
  assert.equal(created.financialStatus,'FINANCIAL_CONFIGURED');
  const pending=(await q(`INSERT INTO nurse_applications(phone_e164,display_name,doc_kind,license_ref,expires_at,accepted_terms_at)
    VALUES($1,'ممرض اعتماد اختباري','LICENSE',$2,current_date+365,now()) RETURNING id`,[phone(3),tag])).rows[0].id;
  const approved=await request('/v1/admin/applications/'+pending+'/approve','POST',undefined,201);
  assert.equal(approved.financialStatus,'FINANCIAL_CONFIGURED');
  const nurse=approved.nurseId;
  const financialPath='/v1/admin/nurses/'+nurse+'/financial-accounts';
  const read=()=>request(financialPath,'GET',undefined,200);
  const initial=(await read()).items;
  assert.equal(initial.length,1);
  assert.equal(initial[0].credit_limit,'100.00');
  assert.equal(initial[0].prepaid_balance,'0.00');
  assert.equal(initial[0].reserved_balance,'0.00');
  await request(financialPath,'POST',{currencyCode:'USD',financialModel:'PREPAID',creditLimit:'0.00'},201);
  const nurseUser=(await q('SELECT user_id FROM nurses WHERE id=$1',[nurse])).rows[0].user_id;
  // Simulate completed password rotation for this isolated synthetic account.
  await q('UPDATE users SET must_change_password=false,temporary_password_expires_at=NULL WHERE id=$1',[nurseUser]);
  const session=(await q(`INSERT INTO device_sessions(user_id,device_id,app_kind) VALUES($1,$2,'nurse') RETURNING id`,[nurseUser,tag])).rows[0].id;
  const token=bearer(nurseUser,session);
  const patient=(await q(`INSERT INTO users(phone_e164,role) VALUES($1,'PATIENT') RETURNING id`,[phone(4)])).rows[0].id;
  const beneficiary=(await q(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status)
    VALUES($1,'مستفيد اختباري','GRANTED') RETURNING id`,[patient])).rows[0].id;
  const service=(await q(`INSERT INTO services(code,title_ar,price_amount,commission_bps,dispatch_approved,active)
    VALUES($1,'خدمة اختبار مالية',102,3000,true,true) RETURNING id`,[tag])).rows[0].id;
  await request('/v1/admin/nurses/'+nurse+'/skills','PUT',{serviceIds:[service]},200);
  await request('/v1/nurse/me/availability','PUT',{availability:'AVAILABLE'},200,token);
  const location='ST_SetSRID(ST_MakePoint(36.25,33.50),4326)::geography';
  await q(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m,captured_at,received_at,sequence_number,session_id,location_source)
    VALUES($1,${location},5,now(),now(),1,$2,'GPS')`,[nurse,session]);
  const order=(await q(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,
    address_text,price_amount,currency_code,commission_bps) VALUES($1,$2,$3,${location},'MANUAL_PIN','اختبار',102,'SYP_NEW',3000)
    RETURNING id`,[patient,beneficiary,service])).rows[0].id;
  await q(`INSERT INTO commission_tiers(min_reputation,min_reviews,commission_bps) VALUES(4,0,2500)`);
  const commission=async(baseBps)=> (await q('SELECT * FROM resolve_nurse_commission($1,$2,102)',[nurse,baseBps])).rows[0];
  const resolved=await commission(3000);
  assert.equal(resolved.applied_bps,2500);
  assert.equal(resolved.reservation_amount,'26');
  assert.equal((await commission(0)).reservation_amount,'0');
  const readiness=await request('/v1/nurse/me/readiness?requestId='+order,'GET',undefined,200,token);
  assert.deepEqual(readiness.requestEligibility.reasons,[]);
  const offer=(await q(`INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
    VALUES($1,$2,1,now()+interval '5 minutes') RETURNING id`,[order,nurse])).rows[0].id;
  const offered=await request('/v1/nurse/me/offers','GET',undefined,200,token);
  assert.ok(offered.some(row=>row.id===offer));
  const accepted=await request('/v1/nurse/offers/'+offer+'/accept','POST',undefined,201,token);
  const booked=(await q('SELECT commission_policy_snapshot FROM request_assignments WHERE id=$1',[accepted.assignmentId])).rows[0];
  assert.equal(booked.commission_policy_snapshot.appliedCommissionBps,2500);
  assert.equal(booked.commission_policy_snapshot.tierId,resolved.tier_id);
  assert.equal(booked.commission_policy_snapshot.reservationAmount,'26.00');

  const db=app.get(DbService),ledger=app.get(LedgerService);
  await db.transaction(async c=>{
    await ledger.postTransaction(c,{transactionType:'TEST_CASH_POSITION',referenceType:'NURSE',referenceId:nurse,
      idempotencyKey:'rc3-fixture:'+tag,currencyCode:'SYP_NEW',legs:[
        {accountId:'CASH_HELD_BY_NURSE:'+nurse,debitAmount:'150.00',creditAmount:0},
        {accountId:'CASH_CLEARING',debitAmount:0,creditAmount:'150.00'},
      ]});
    await c.query('SELECT recompute_nurse_financial_eligibility($1,$2)',[nurse,'SYP_NEW']);
  });
  const ledgerPosition=(await read()).items.find(a=>a.currency_code==='SYP_NEW');
  assert.equal(ledgerPosition.settlement_required,true);
  const settlePath='/v1/admin/dues/'+nurse+'/settle';
  const settlement={currencyCode:'SYP_NEW',direction:'FROM_NURSE',amount:100};
  const key=randomUUID();
  await request(settlePath,'POST',{...settlement,amount:151},409);
  await request(settlePath,'POST',settlement,201,bearer(admin),key);
  await request(settlePath,'POST',settlement,201,bearer(admin),key);
  const positions=(await read()).items;
  const primary=positions.find(a=>a.currency_code==='SYP_NEW'),secondary=positions.find(a=>a.currency_code==='USD');
  assert.equal(primary.balance,'50.00');
  assert.equal(primary.settlement_required,false);
  assert.equal(primary.reserved_balance,'26.00');
  assert.equal(primary.prepaid_balance,'0.00');
  assert.equal(Number(secondary.balance),0);
  assert.equal(secondary.prepaid_balance,'0.00');
  const settled=(await q(`SELECT id FROM financial_transactions WHERE idempotency_key=$1`,['nurse-settlement:'+admin+':'+key])).rows[0].id;
  await db.transaction(c=>ledger.reverseTransaction(c,settled,'rc3-reversal:'+tag,admin));
  assert.equal((await read()).items.find(a=>a.currency_code==='SYP_NEW').settlement_required,true);
  const status=(await q('SELECT availability_intent,work_status FROM nurses WHERE id=$1',[nurse])).rows[0];
  assert.equal(status.availability_intent,'AVAILABLE');
  assert.equal((await q('SELECT status FROM request_assignments WHERE id=$1',[accepted.assignmentId])).rows[0].status,'ACTIVE');
});
