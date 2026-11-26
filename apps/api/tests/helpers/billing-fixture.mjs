import { readFileSync } from 'node:fs';
import { BillingService } from '../../dist/pricing/billing.service.js';
import { DuesService, FeesService } from '../../dist/pricing/fees.service.js';
import { ReferralService } from '../../dist/pricing/referral.service.js';
import { LedgerService } from '../../dist/wallet/ledger.service.js';
import { DispatchService } from '../../dist/dispatch/dispatch.service.js';

export async function migrateBillingFixtures(pg) {
  await pg.exec('CREATE EXTENSION IF NOT EXISTS pgcrypto');
  const folder=new URL('../../../../infra/db/migrations/',import.meta.url);
  for(const file of ['042_competitive_expansion_catalog_and_items','045_health_records_and_clinical_observations',
    '047_financial_ledger_and_multi_model','055_financial_source_of_truth','065_financial_commission_snapshot_and_backfill']) {
    await pg.exec(readFileSync(new URL(file+'.sql',folder),'utf8'));
  }
  await pg.exec(`ALTER TABLE request_assignments
    ADD COLUMN planned_start_at timestamptz,
    ADD COLUMN planned_end_at timestamptz,
    ADD COLUMN service_duration_minutes integer,
    ADD COLUMN travel_buffer_before_minutes integer NOT NULL DEFAULT 30`);
}

export function configureBilling(db) {
  const ledger=new LedgerService();
  const fees=new FeesService();
  const dues=new DuesService();
  const referrals=new ReferralService();
  const billing=new BillingService(ledger,dues,referrals);
  const dispatch=new DispatchService(db,undefined,undefined,billing,fees,{configured:false});
  return {ledger,fees,dues,referrals,billing,dispatch};
}

export async function recordExecution(db,{requestId,beneficiaryId,nurseUserId,serviceId,visitTime,minutes,unitPrice=1200}) {
  await db.query(`INSERT INTO care_request_items(
    request_id,service_id,quantity,unit_price,expected_minutes,item_status,performed_quantity,clinical_requirements_snapshot)
    VALUES($1,$2,1,$3,30,'COMPLETED',1,'{}')`,[requestId,serviceId,unitPrice]);
  await db.query(`INSERT INTO clinical_visit_notes(request_id,beneficiary_id,nurse_user_id,status,clinical_notes)
    VALUES($1,$2,$3,'SUBMITTED','تم تنفيذ الخدمة')`,[requestId,beneficiaryId,nurseUserId]);
  if(visitTime) await db.query(`UPDATE visits SET arrived_at=$2::timestamptz-interval '1 minute',
    started_at=$2 WHERE assignment_id=(SELECT id FROM request_assignments WHERE request_id=$1)`,
  [requestId,visitTime]);
  else await db.query(`UPDATE visits SET arrived_at=now()-($2::integer+1)*interval '1 minute',
    started_at=now()-$2::integer*interval '1 minute'
    WHERE assignment_id=(SELECT id FROM request_assignments WHERE request_id=$1)`,[requestId,minutes]);
}
