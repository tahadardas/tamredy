import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { VoiceService } from '../dist/voice/voice.service.js';
import { deliverOutbox, publishRealtimeEvents } from '../../worker/src/outbox.ts';

const migrations = new URL('../../../infra/db/migrations/', import.meta.url);

test('a committed ring and call transitions survive direct/redis loss with stable envelope IDs', async t => {
  const pg = new PGlite();
  t.after(() => pg.close());
  for (const name of ['001_core','018_dispatch_diagnostics_and_deliveries','023_outbox_delivery_leases',
    '048_tamreedy_voice_signaling','058_delivery_retries_and_marketplace_paging','061_voice_lifecycle_and_quality']) {
    const migration = readFileSync(new URL(`${name}.sql`, migrations), 'utf8')
      .replace(/CREATE INDEX idx_marketplace_approved_created[^;]*;/s,'')
      .replace(/CREATE EXTENSION[^;]*;/g,'').replaceAll('geography(Point,4326)','text')
      .replace(/CREATE INDEX[^;]*GIST[^;]*;/g,'');
    await pg.exec(migration);
  }
  const patient=randomUUID(), nurseUser=randomUUID(), nurse=randomUUID(), service=randomUUID(), beneficiary=randomUUID(), request=randomUUID();
  await pg.query(`INSERT INTO users(id,phone_e164,role) VALUES($1,'patient-fixture','PATIENT'),($2,'nurse-fixture','NURSE')`,[patient,nurseUser]);
  await pg.query('INSERT INTO nurses(id,user_id) VALUES($1,$2)',[nurse,nurseUser]);
  await pg.query(`INSERT INTO services(id,code,title_ar,price_amount) VALUES($1,'voice-fixture','تمريض اختبار',200)`,[service]);
  await pg.query(`INSERT INTO beneficiaries(id,owner_user_id,display_name,consent_status) VALUES($1,$2,'مريض اختباري','GRANTED')`,[beneficiary,patient]);
  await pg.query(`INSERT INTO care_requests(id,requester_user_id,beneficiary_id,service_id,status,location,location_source,address_text,price_amount,currency_code,commission_bps)
    VALUES($1,$2,$3,$4,'ASSIGNED','test','MANUAL_PIN','دمشق',200,'SYP_NEW',1000)`,[request,patient,beneficiary,service]);
  await pg.query(`INSERT INTO request_assignments(request_id,nurse_id,status) VALUES($1,$2,'ACTIVE')`,[request,nurse]);
  let transactionOpen=false;
  const db={query:pg.query.bind(pg), async transaction(work) {
    await pg.exec('BEGIN'); transactionOpen=true;
    try {const result=await work({query:db.query}); await pg.exec('COMMIT'); return result;}
    catch(error){await pg.exec('ROLLBACK');throw error;}
    finally {transactionOpen=false;}
  }};
  const direct=[];
  const voice=new VoiceService(db,{async sendToUser(user,type,payload){direct.push({user,type,payload,transactionOpen});throw new Error('socket lost');}},
    {async isMutuallyBlocked(){return false;}},{increment(){}});
  const key=randomUUID();
  const call=await voice.initiateCall(patient,request,key);
  assert.equal((await voice.initiateCall(patient,request,key)).id,call.id);
  const events=async()=> (await pg.query('SELECT * FROM outbox_events ORDER BY id')).rows;
  const [ring]=await events();
  assert.equal((await events()).length,1);
  assert.equal(ring.realtime_published_at,null);
  assert.equal(ring.payload.eventId,direct[0].payload.eventId);
  assert.equal(direct[0].transactionOpen,false);
  assert.equal(ring.payload.recipientUserId,nurseUser);
  assert.equal(ring.payload.targetApp,'NURSE_APP');
  const published=[];
  const transport={async publish(channel,raw){published.push({channel,...JSON.parse(raw)});return 0;}};
  const flush=()=>deliverOutbox(db,'realtime', batch=>publishRealtimeEvents(db,transport,batch));
  await assert.rejects(flush(),/No realtime subscriber/);
  assert.equal((await events())[0].realtime_published_at,null);
  await pg.exec("UPDATE outbox_events SET realtime_lease_until=now()-interval '1 second'");
  transport.publish=async (channel,raw)=>{published.push({channel,...JSON.parse(raw)});return 1;};
  assert.equal(await flush(),true);
  assert.equal(published[0].eventId,published[1].eventId);
  await voice.acceptCall(nurseUser,call.id);
  await voice.markConnected(patient,call.id);
  await voice.markConnected(patient,call.id);
  await voice.endCall(patient,call.id);
  await voice.endCall(patient,call.id);
  assert.deepEqual((await events()).map(row=>row.event_type),['call.incoming','call.accepted','call.connected','call.ended']);
  const before=published.length;
  await publishRealtimeEvents(db,transport,[ring]);
  assert.equal(published.length,before,'a delayed ring must not be republished after termination');
});
