import test from 'node:test';
import assert from 'node:assert/strict';
import { isPrivateEventEnvelope, validHighFrequencyEvent } from '../dist/realtime/private-event.js';
import { buildNotificationPayload } from '../dist/notifications/notification-routing.js';
import { PGlite } from '@electric-sql/pglite';
import { VoiceService } from '../dist/voice/voice.service.js';

for(const role of ['PATIENT','NURSE']) {
  test(`call transitions carry server recipient ${role} and session version`,async()=>{
    const delivered=[];
    const call={id:'call-a',request_id:'request-a',session_version:8,connected_at:new Date(),caller_user_id:'caller',receiver_user_id:'receiver',call_status:'ACCEPTED'};
    const client={query:async(sql)=>sql.includes('SELECT role')?{rowCount:1,rows:[{role}]}:{rowCount:1,rows:[call]}};
    const db={transaction:async work=>work(client)};
    const voice=new VoiceService(db,{sendToUser:async(...args)=>delivered.push(args)},{},{increment(){}});
    await voice.markConnected('caller','call-a');
    const [user,type,payload]=delivered[0];
    assert.equal(user,'receiver');assert.equal(type,'call.connected');
    assert.equal(payload.recipientRole,role);assert.equal(payload.requestId,'request-a');
    assert.equal(payload.sessionVersion,8);assert.equal(isPrivateEventEnvelope(payload,user,type),true);
  });
}
test('private envelope rejects missing identity, role, app, creation timestamp and wrong event type',()=>{
 const valid=buildNotificationPayload({eventType:'request.assigned',recipientUserId:'patient',recipientRole:'PATIENT'});
 assert.equal(isPrivateEventEnvelope(valid,'patient','request.assigned'),true);
 for(const key of ['eventId','recipientUserId','recipientRole','targetApp','createdAt','eventType']) {
   const invalid={...valid};delete invalid[key];assert.equal(isPrivateEventEnvelope(invalid,'patient','request.assigned'),false,key);
 }
 assert.equal(isPrivateEventEnvelope(valid,'another','request.assigned'),false);
});
test('signal ingestion rejects malformed frames before entering database transaction',async()=>{
 let entered=false;
 const voice=new VoiceService({transaction(){entered=true;throw Error('unexpected');}},{},{},{increment(){}});
 await assert.rejects(voice.relaySignal('sender','call',{eventId:'invalid',sequenceNumber:0,eventType:'SDP_OFFER',data:{}}),error=>error.getResponse().code==='INVALID_CALL_SIGNAL');
 assert.equal(entered,false);
});

test('high frequency streams require explicit sequencing and signal kind',()=>{
 const signal=buildNotificationPayload({eventType:'call.signal',recipientUserId:'nurse',recipientRole:'NURSE',callId:'call',extra:{signalType:'SDP_OFFER',sequenceNumber:1,data:{sdp:'offer'}}});
 assert.equal(validHighFrequencyEvent(signal),true);
 assert.equal(validHighFrequencyEvent({...signal,sequenceNumber:0}),false);
 assert.equal(validHighFrequencyEvent({...signal,signalType:'call.signal'}),false);
 const tracking=buildNotificationPayload({eventType:'tracking.updated',recipientUserId:'patient',recipientRole:'PATIENT',requestId:'request',assignmentId:'assignment',extra:{sequenceNumber:3,latitude:33.5,longitude:36.3,capturedAt:new Date().toISOString()}});
 assert.equal(validHighFrequencyEvent(tracking),true);
 assert.equal(validHighFrequencyEvent({...tracking,latitude:180}),false);
});

test('shared HTTP/socket signal ingestion persists once, replays same key and rejects payload or sequence conflicts',async t=>{
 const pg=new PGlite();t.after(()=>pg.close());
 const caller='11111111-1111-4111-8111-111111111111',receiver='22222222-2222-4222-8222-222222222222',call='33333333-3333-4333-8333-333333333333';
 await pg.exec(`CREATE TABLE voice_call_sessions(id uuid PRIMARY KEY,caller_user_id uuid,receiver_user_id uuid,call_status text);
 CREATE TABLE voice_call_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),session_id uuid,actor_user_id uuid,event_type text,event_data jsonb,event_id uuid,sequence_number integer);
 CREATE UNIQUE INDEX event_identity ON voice_call_events(event_id) WHERE event_id IS NOT NULL;`);
 await pg.query("INSERT INTO voice_call_sessions VALUES($1,$2,$3,'ACCEPTED')",[call,caller,receiver]);
 const db={query:(sql,p)=>pg.query(sql,p),transaction:async work=>{
   await pg.exec('BEGIN');try{const value=await work({query:(sql,p)=>pg.query(sql,p)});await pg.exec('COMMIT');return value;}catch(error){await pg.exec('ROLLBACK');throw error;}
 }};
 const deliveries=[];
 const voice=new VoiceService(db,{sendToUser:async(...args)=>deliveries.push(args)},{},{increment(){}});
 const frame={eventId:'44444444-4444-4444-8444-444444444444',sequenceNumber:1,eventType:'SDP_OFFER',data:{type:'offer',sdp:'synthetic-test-sdp'}};
 const first=await voice.relaySignal(caller,call,frame);assert.equal(first.relayed,true);
 const duplicate=await voice.relaySignal(caller,call,{...frame,data:{sdp:'synthetic-test-sdp',type:'offer'}});
 assert.equal(duplicate.duplicate,true);assert.equal(duplicate.sequenceNumber,1);
 assert.equal(deliveries.length,1);assert.equal(deliveries[0][2].signalType,'SDP_OFFER');
 assert.equal((await pg.query('SELECT count(*)::integer AS n FROM voice_call_events')).rows[0].n,1);
 await assert.rejects(voice.relaySignal(caller,call,{...frame,data:{sdp:'different'}}),error=>error.getResponse().code==='CALL_SIGNAL_IDEMPOTENCY_CONFLICT');
 await assert.rejects(voice.relaySignal(caller,call,{...frame,eventId:'55555555-5555-4555-8555-555555555555'}),error=>error.getResponse().code==='CALL_SIGNAL_OUT_OF_ORDER');
 await pg.query("UPDATE voice_call_sessions SET call_status='ENDED' WHERE id=$1",[call]);
 await assert.rejects(voice.relaySignal(caller,call,{...frame,eventId:'66666666-6666-4666-8666-666666666666',sequenceNumber:2}),error=>error.getResponse().code==='CALL_TERMINAL');
});
