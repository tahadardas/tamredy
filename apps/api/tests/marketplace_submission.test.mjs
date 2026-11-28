import {installRc2PolicyFixture} from './helpers/rc2-policy-fixture.mjs';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { MarketplaceEligibilityService } from '../dist/marketplace/marketplace-eligibility.service.js';
import { NurseEligibilityEngine } from '../dist/dispatch/nurse-eligibility.engine.js';
import { ProposalsService } from '../dist/marketplace/proposals.service.js';

test('submitting readiness commits the offer and patient event using the production schema', async t => {
  const database = new PGlite({ extensions: { pgcrypto } });
  t.after(() => database.close());
  await database.exec('CREATE EXTENSION IF NOT EXISTS pgcrypto');
  const migrations = new URL('../../../infra/db/migrations/', import.meta.url);
  for (const name of ['001_core','003_admin_reads_audit','006_pricing_promos_rewards','007_fees_tiers_dues_referrals','009_nurse_admin_documents_settings',
    '021_open_dispatch_and_cancellation_foundation','027_scheduled_visits','042_competitive_expansion_catalog_and_items',
    '043_tamreedy_connect_and_trust','044_smart_scheduling_and_recurring','047_financial_ledger_and_multi_model',
    '050_smart_booking_and_open_marketplace','055_financial_source_of_truth','056_clinical_approval_gate']) {
    const sql = await readFile(new URL(name + '.sql', migrations), 'utf8');
    await database.exec(sql.replace(/CREATE EXTENSION[^;]*;/g,'').replace(/geography\(Point,\s*4326\)/g,'text')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/g,''));
  }
  await database.exec(`ALTER TABLE care_requests
    ADD COLUMN search_max_heartbeat_seconds integer,
    ADD COLUMN search_max_location_seconds integer,
    ADD COLUMN search_max_accuracy_meters integer;
    CREATE FUNCTION st_distance(text,text) RETURNS double precision LANGUAGE sql IMMUTABLE AS 'SELECT 0::double precision';`);
  const db = { query: database.query.bind(database), transaction: database.transaction.bind(database) };
  const user = async (phone, role) => (await db.query('INSERT INTO users(phone_e164,role) VALUES($1,$2) RETURNING id',[phone,role])).rows[0].id;
  const patient = await user('+963911111111','PATIENT');
  const nurseUser = await user('+963922222222','NURSE');
  const nurse = (await db.query('INSERT INTO nurses(user_id,verified) VALUES($1,true) RETURNING id',[nurseUser])).rows[0].id;
  await db.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved,review_status)
    VALUES($1,'TEST-LICENSE',now()+interval '1 year',true,'APPROVED')`,[nurse]);
  const beneficiary = (await db.query("INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'مستفيد','GRANTED') RETURNING id",[patient])).rows[0].id;
  const service = (await db.query("INSERT INTO services(code,title_ar,price_amount) VALUES('TEST','زيارة',100) RETURNING id")).rows[0].id;
  await db.query('INSERT INTO nurse_skills(nurse_id,service_id,approved) VALUES($1,$2,true)',[nurse,service]);
  const request = async status => (await db.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,
    address_text,price_amount,currency_code,commission_bps,status,open_expires_at)
    VALUES($1,$2,$3,'33,36','MANUAL_PIN','دمشق',100,'SYP',2000,$4,now()+interval '1 hour') RETURNING id`,
  [patient,beneficiary,service,status])).rows[0].id;
  const open = await request('OPEN_FOR_PROPOSALS');
  await db.query('INSERT INTO care_request_items(request_id,service_id,unit_price,expected_minutes) VALUES($1,$2,100,45)',[open,service]);
  await db.query(`INSERT INTO nurse_financial_accounts(nurse_id,financial_model,credit_limit) VALUES($1,'RECEIVABLES',10000)`,[nurse]);
  await installRc2PolicyFixture(database);
  const proposals = new ProposalsService(db,new MarketplaceEligibilityService(new NurseEligibilityEngine(db)));
  const busy = await request('ASSIGNED');
  await db.query('INSERT INTO request_assignments(request_id,nurse_id) VALUES($1,$2)',[busy,nurse]);
  await assert.rejects(proposals.submitProposal(nurseUser,open,{arrivalMinutes:20}), {response:{code:'NURSE_HAS_ACTIVE_EXECUTION'}});
  await db.query("UPDATE request_assignments SET status='RELEASED' WHERE request_id=$1",[busy]);
  const result = await proposals.submitProposal(nurseUser,open,{arrivalMinutes:20,note:'جاهز للزيارة'});
  assert.equal(result.status,'PENDING');
  assert.equal(result.estimated_service_minutes,45);
  assert.equal(result.note,'جاهز للزيارة');
  const events = (await db.query("SELECT payload FROM outbox_events WHERE event_type='marketplace.proposal.created'")).rows;
  assert.equal(events.length,1);
  assert.equal(events[0].payload.proposalId,result.id);
  assert.equal(events[0].payload.recipientUserId,patient);
});
