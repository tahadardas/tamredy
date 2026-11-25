import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import test from 'node:test';
import {DbService} from '../dist/db/db.service.js';
import {RequestsService} from '../dist/requests/requests.service.js';
import {PromoService} from '../dist/pricing/promo.service.js';
import {FeesService,DuesService} from '../dist/pricing/fees.service.js';
import {NurseEligibilityEngine} from '../dist/dispatch/nurse-eligibility.engine.js';
import {AssignmentOrchestrator} from '../dist/dispatch/assignment.orchestrator.js';
import {DispatchService} from '../dist/dispatch/dispatch.service.js';
import {BillingService} from '../dist/pricing/billing.service.js';
import {LedgerService} from '../dist/wallet/ledger.service.js';
import {ReferralService} from '../dist/pricing/referral.service.js';
import {RequestItemsService} from '../dist/requests/request-items.service.js';
import {MarketplaceService} from '../dist/marketplace/marketplace.service.js';
import {MarketplaceEligibilityService} from '../dist/marketplace/marketplace-eligibility.service.js';
import {HealthRecordsService} from '../dist/health-records/health-records.service.js';
import {cancelRequest} from '../dist/requests/cancellation.service.js';

test('PostgreSQL preserves assignment, lifecycle, billing and recovery invariants', {
  skip: !process.env.TEST_DATABASE_URL && 'Requires an explicitly configured disposable PostgreSQL database',
}, async t => {
  const url = new URL(process.env.TEST_DATABASE_URL);
  assert.ok(['127.0.0.1','localhost','[::1]'].includes(url.hostname));
  assert.match(url.pathname,/^\/tamreedy_(?:test|stabilization)\w*$/);
  process.env.DATABASE_URL = url.href;
  process.env.JWT_SECRET ??= 'local-integration-only-'.repeat(4);
  const db = new DbService();
  t.after(()=>db.onModuleDestroy());
  const tag=randomUUID();
  const q=(sql,params)=>db.query(sql,params);
  const createUser=async role=>(await q('INSERT INTO users(phone_e164,role) VALUES($1,$2) RETURNING id',
    [`+963${BigInt('0x'+randomUUID().replaceAll('-',''))%10000000000n}`,role])).rows[0].id;
  const patient=await createUser('PATIENT');
  const beneficiary=(await q(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status)
    VALUES($1,'أحمد الحسن','GRANTED') RETURNING id,display_name`,[patient])).rows[0];
  assert.equal(beneficiary.display_name,'أحمد الحسن');
  const service=(await q(`INSERT INTO services(code,title_ar,price_amount,active,dispatch_approved,included_minutes,rounding_step)
    VALUES($1,'زيارة اختبار عربية',1000,true,true,30,1) RETURNING id`,[tag])).rows[0].id;
  const nurseEntries=[];
  for(let i=0;i<2;i++){
    const user=await createUser('NURSE');
    const nurse=(await q(`INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at)
      VALUES($1,true,'AVAILABLE','AVAILABLE',now()) RETURNING id`,[user])).rows[0].id;
    await q(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved)
      VALUES($1,$2,now()+interval '1 year',true)`,[nurse,`${tag}-${i}`]);
    await q('INSERT INTO nurse_skills(nurse_id,service_id,approved) VALUES($1,$2,true)',[nurse,service]);
    await q(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m)
      VALUES($1,ST_SetSRID(ST_MakePoint(36.29,33.51),4326)::geography,15)`,[nurse]);
    nurseEntries.push({user,nurse});
  }
  const requests=new RequestsService(db,new PromoService());
  const eligibility=new NurseEligibilityEngine(db);
  const ledger=new LedgerService();
  const billing=new BillingService(ledger,new DuesService(),new ReferralService());
  const dispatch=new DispatchService(db,eligibility,new AssignmentOrchestrator(eligibility),billing,new FeesService(),{configured:false});
  const input={beneficiaryId:beneficiary.id,items:[{serviceId:service,quantity:1},{serviceId:service,quantity:1}],
    latitude:33.51,longitude:36.29,locationSource:'MANUAL_PIN',addressText:'دمشق، المزة',nonEmergencyConfirmed:true};
  const request=await requests.create(patient,input,tag);
  assert.equal((await requests.create(patient,input,tag)).id,request.id);
  const items=(await requests.findOne(patient,request.id)).items;
  assert.equal(items.length,1);
  assert.equal(items[0].quantity,2);
  await assert.rejects(q("UPDATE care_requests SET status='COMPLETED',version=version+1 WHERE id=$1",[request.id]),{code:'23514'});
  const offers=await Promise.all(nurseEntries.map(async entry=>(await q(`INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
    VALUES($1,$2,1,now()+interval '5 minutes') RETURNING id`,[request.id,entry.nurse])).rows[0].id));
  const decisions=await Promise.allSettled(offers.map((offer,i)=>dispatch.accept(nurseEntries[i].user,offer)));
  const winnerIndex=decisions.findIndex(decision=>decision.status==='fulfilled');
  assert.equal(decisions.filter(decision=>decision.status==='fulfilled').length,1,
    JSON.stringify(decisions.map(decision=>decision.status==='rejected'?decision.reason.message:decision.status)));
  assert.equal((await q("SELECT count(*)::int AS count FROM request_assignments WHERE request_id=$1 AND status='ACTIVE'",[request.id])).rows[0].count,1);
  const winner=nurseEntries[winnerIndex];
  const assignment=decisions[winnerIndex].value.assignmentId;
  const health=new HealthRecordsService(db);
  const administrator=await createUser('ADMIN');
  await assert.rejects(health.getBeneficiaryProfile(administrator,beneficiary.id,request.id),
    error=>error.getResponse?.().code==='HEALTH_RECORD_ACCESS_DENIED');
  await assert.rejects(health.getNurseFormConfig(request.id,nurseEntries[1-winnerIndex].user),
    error=>error.getResponse?.().code==='REQUEST_NOT_FOUND');
  await health.getBeneficiaryProfile(winner.user,beneficiary.id,request.id);
  assert.equal((await q(`SELECT count(*)::int AS count FROM health_record_access_audit
    WHERE request_id=$1 AND actor_user_id=$2 AND action='VIEW_PROFILE'`,[request.id,winner.user])).rows[0].count,1);
  await dispatch.transition(winner.user,assignment,'depart');
  await q("UPDATE nurse_locations SET accuracy_m=200 WHERE nurse_id=$1",[winner.nurse]);
  await assert.rejects(dispatch.transition(winner.user,assignment,'arrive'),
    error=>error.getResponse?.().code==='ARRIVAL_GEOFENCE_FAILED');
  await dispatch.transition(winner.user,assignment,'arrive',{geofenceOverrideReason:'إشارة الموقع ضعيفة داخل المبنى'});
  assert.equal((await q(`SELECT count(*)::int AS count FROM request_events
    WHERE request_id=$1 AND event_type='visit.arrival.geofence_override'`,[request.id])).rows[0].count,1);
  await q("UPDATE nurse_locations SET accuracy_m=15 WHERE nurse_id=$1",[winner.nurse]);
  await dispatch.transition(winner.user,assignment,'start');
  await assert.rejects(dispatch.transition(winner.user,assignment,'complete'),
    error=>error.getResponse?.().code==='CLINICAL_VISIT_NOTE_REQUIRED');
  await q(`INSERT INTO clinical_visit_notes(request_id,beneficiary_id,nurse_user_id,status,clinical_notes)
    VALUES($1,$2,$3,'SUBMITTED','تمت الخدمة')`,[request.id,beneficiary.id,winner.user]);
  await new RequestItemsService(db).recordOutcome(winner.user,request.id,items[0].id,
    {status:'COMPLETED',performedQuantity:2,actualMinutes:1,note:'تم التنفيذ'});
  await dispatch.transition(winner.user,assignment,'complete');
  assert.equal((await dispatch.transition(winner.user,assignment,'complete')).replayed,true);
  const collect=(amount,key)=>db.transaction(c=>billing.collectCash(c,winner.user,request.id,amount,key));
  const concurrent=await Promise.all([collect(750,'first'),collect(750,'first')]);
  assert.equal(concurrent.filter(response=>response.replayed).length,1);
  const partial=concurrent.find(response=>!response.replayed);
  assert.equal(partial.status,'PARTIALLY_PAID');
  assert.equal((await collect(750,'first')).replayed,true);
  await assert.rejects(collect(751,'first'),error=>error.getResponse?.().code==='FINANCIAL_IDEMPOTENCY_KEY_REUSED');
  assert.equal((await collect(1250,'second')).status,'PAID');
  const reconciled=(await q(`SELECT i.total_amount::text,i.paid_amount::text,count(c.id)::int AS receipts
    FROM invoices i JOIN cash_collections c ON c.visit_id=i.visit_id WHERE i.request_id=$1 GROUP BY i.id`,[request.id])).rows[0];
  assert.deepEqual(reconciled,{total_amount:'2000.00',paid_amount:'2000.00',receipts:2});
  assert.equal((await q('SELECT count(*)::int AS count FROM financial_unbalanced_transactions')).rows[0].count,0);
  const nursePosition=await new DuesService().balance(db,winner.nurse);
  assert.equal(nursePosition.balance,400);
  await assert.rejects(q(`UPDATE financial_ledger_entries SET debit_amount=10
    WHERE transaction_id IN (SELECT transaction_id FROM cash_collections WHERE visit_id=
      (SELECT visit_id FROM invoices WHERE request_id=$1))`,[request.id]),{code:'55000'});

  const market=new MarketplaceService(db,new MarketplaceEligibilityService(eligibility));
  const opened=[];
  for(let i=0;i<3;i++) opened.push(await requests.create(patient,{...input,bookingMode:'OPEN'},`${tag}-${i}`));
  for(const sortBy of ['oldest','newest','nearest','highest_earning','arrival_time']){
    const seen=[];
    let cursor;
    do {
      const page=await market.listOpenRequests(winner.user,{serviceId:service,limit:1,sortBy,cursor});
      seen.push(...page.requests.map(row=>row.id));
      cursor=page.nextCursor??undefined;
      assert.ok(seen.length<=opened.length);
    } while(cursor);
    assert.deepEqual(new Set(seen),new Set(opened.map(row=>row.id)),sortBy);
    assert.equal(seen.length,opened.length,sortBy);
  }

  const reserve=(requestId,start,end)=>q(`INSERT INTO request_assignments(
    request_id,nurse_id,status,planned_start_at,planned_end_at,service_duration_minutes
  ) VALUES($1,$2,'RESERVED',$3,$4,30)`,[requestId,winner.nurse,start,end]);
  const start=new Date(Date.now()+86_400_000).toISOString();
  const after=minutes=>new Date(Date.parse(start)+minutes*60_000).toISOString();
  await reserve(opened[0].id,start,after(30));
  await assert.rejects(reserve(opened[1].id,after(89),after(119)),{code:'23P01'});
  await reserve(opened[2].id,after(90),after(120));

  const other=nurseEntries[1-winnerIndex];
  const financial=await requests.create(patient,input,`${tag}-financial`);
  await q(`INSERT INTO nurse_financial_accounts(nurse_id,financial_model,credit_limit,prepaid_balance)
    VALUES($1,'RECEIVABLES',399,0)`,[other.nurse]);
  let assessment=await eligibility.evaluate(other.nurse,financial.id,{context:'ASSIGN'});
  assert.ok(assessment.reasons.some(reason=>reason.code==='FINANCIAL_LIMIT_REACHED'));
  await q("UPDATE nurse_financial_accounts SET financial_model='PREPAID',prepaid_balance=399 WHERE nurse_id=$1",[other.nurse]);
  assessment=await eligibility.evaluate(other.nurse,financial.id,{context:'ASSIGN'});
  assert.ok(assessment.reasons.some(reason=>reason.code==='INSUFFICIENT_PREPAID_BALANCE'));
  await q(`UPDATE nurse_financial_accounts SET financial_model='HYBRID',prepaid_balance=250,credit_limit=150
    WHERE nurse_id=$1`,[other.nurse]);
  const financeOffer=(await q(`INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
    VALUES($1,$2,1,now()+interval '5 minutes') RETURNING id`,[financial.id,other.nurse])).rows[0].id;
  await dispatch.accept(other.user,financeOffer);
  const reservation=(await q(`SELECT prepaid_amount::text,credit_amount::text,status
    FROM financial_reservations WHERE reference_id=$1`,[financial.id])).rows[0];
  assert.deepEqual(reservation,{prepaid_amount:'250.00',credit_amount:'150.00',status:'HELD'});
  await db.transaction(c=>cancelRequest(c,patient,financial.id,{reasonCode:'OTHER',reasonNote:'إلغاء اختبار',
    idempotencyKey:`${tag}-cancel`}));
  assert.equal((await q("SELECT status FROM financial_reservations WHERE reference_id=$1",[financial.id])).rows[0].status,'RELEASED');
  assert.equal((await q("SELECT reserved_balance::text FROM nurse_financial_accounts WHERE nurse_id=$1",[other.nurse])).rows[0].reserved_balance,'0.00');

  await q('UPDATE services SET requires_prescription=true WHERE id=$1',[service]);
  const clinical=await requests.create(patient,{...input,prescriptionConfirmed:true},`${tag}-clinical`);
  assert.equal(clinical.clinicalApprovalStatus,'PENDING');
  assert.equal((await q('SELECT 1 FROM dispatch_jobs WHERE request_id=$1',[clinical.id])).rowCount,0);
  const denied=await eligibility.evaluate(winner.nurse,clinical.id,{context:'OFFER'});
  assert.ok(denied.reasons.some(reason=>reason.code==='CLINICAL_APPROVAL_REQUIRED'));

  await q('UPDATE nurse_credentials SET expires_at=now()-interval \'1 day\' WHERE nurse_id=$1',[winner.nurse]);
  const expired=await eligibility.evaluate(winner.nurse,clinical.id,{context:'OFFER'});
  assert.ok(expired.reasons.some(reason=>reason.code==='LICENSE_MISSING_OR_EXPIRED'));
});
