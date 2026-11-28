import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { expireVoiceCalls } from '../src/voice-lifecycle.ts';

test('ring timeout emits independent private envelopes with real role and monotonic terminal session version',async t=>{
 const db=new PGlite();t.after(()=>db.close());
 await db.exec(`CREATE TABLE users(id uuid PRIMARY KEY,role text);
 CREATE TABLE care_requests(id uuid PRIMARY KEY);
 CREATE TABLE outbox_events(id bigserial PRIMARY KEY,event_type text,aggregate_id uuid,payload jsonb);`);
 const migrations=new URL('../../../infra/db/migrations/',import.meta.url);
 for(const name of ['048_tamreedy_voice_signaling','061_voice_lifecycle_and_quality']) await db.exec(readFileSync(new URL(name+'.sql',migrations),'utf8'));
 const caller='11111111-1111-4111-8111-111111111111',receiver='22222222-2222-4222-8222-222222222222',request='33333333-3333-4333-8333-333333333333';
 await db.query("INSERT INTO users VALUES($1,'NURSE'),($2,'PATIENT')",[caller,receiver]);
 await db.query('INSERT INTO care_requests VALUES($1)',[request]);
 await db.query(`INSERT INTO voice_call_sessions(request_id,caller_user_id,receiver_user_id,call_status,room_token,ring_expires_at,session_version)
 VALUES($1,$2,$3,'RINGING','synthetic-room',now()-interval '10 seconds',5)`,[request,caller,receiver]);
 assert.equal(await expireVoiceCalls(db),true);
 const rows=(await db.query('SELECT payload FROM outbox_events ORDER BY id')).rows;
 assert.equal(rows.length,2);
 for(const {payload} of rows) {
   assert.equal(payload.eventType,'call.missed');assert.equal(payload.sessionVersion,6);
   assert.ok(payload.eventId);assert.ok(payload.createdAt);assert.equal(payload.requestId,request);
   assert.equal(payload.recipientUserId,payload.recipientRole==='NURSE'?caller:receiver);
   assert.equal(payload.targetApp,payload.recipientRole==='NURSE'?'NURSE_APP':'PATIENT_APP');
 }
 assert.notEqual(rows[0].payload.eventId,rows[1].payload.eventId);
 assert.equal(await expireVoiceCalls(db),false);
});
