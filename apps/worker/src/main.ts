import pg from 'pg';
import { readFileSync } from 'node:fs';
import Redis from 'ioredis';
import 'dotenv/config';
import { FcmClient, loadServiceAccount, pushBatch } from './push.js';
import { processBroadcast, runWinback } from './marketing.js';
const dbUrl=process.env.DATABASE_URL;
if(!dbUrl)throw new Error('DATABASE_URL required');
const pool=new pg.Pool({connectionString:dbUrl,max:10,statement_timeout:10000});
const redis=process.env.REDIS_URL?new Redis(process.env.REDIS_URL):undefined;
const sa=loadServiceAccount(process.env.FCM_SERVICE_ACCOUNT_FILE?readFileSync(process.env.FCM_SERVICE_ACCOUNT_FILE,'utf8'):process.env.FCM_SERVICE_ACCOUNT_JSON);
const fcm=sa?new FcmClient(sa):undefined; // push is a no-op until FCM is configured
const defaultWaves=[{radius:3000,seconds:15,limit:8},{radius:6000,seconds:15,limit:12},{radius:10000,seconds:20,limit:20}];
async function loadWaves(c:pg.PoolClient){ // admin-editable (app_settings.dispatch); falls back to safe defaults if missing/invalid
 try{
  const r=await c.query(`SELECT value FROM app_settings WHERE key='dispatch'`);
  const w=r.rows[0]?.value?.waves;
  if(Array.isArray(w)&&w.length>=1&&w.length<=5&&w.every((x:any)=>x.radiusM>0&&x.seconds>0&&x.limit>0))return w.map((x:any)=>({radius:Number(x.radiusM),seconds:Number(x.seconds),limit:Number(x.limit)}));
 }catch{}
 return defaultWaves;
}
async function doDispatch() {
 const c=await pool.connect();
 try {
  await c.query('BEGIN');
  const due=await c.query(`SELECT request_id,next_wave FROM dispatch_jobs WHERE next_run_at<=now()
    ORDER BY next_run_at LIMIT 1 FOR UPDATE SKIP LOCKED`);
  if(!due.rowCount){await c.query('COMMIT');return false;}
  const {request_id:requestId,next_wave:wave}=due.rows[0];
  const rr=await c.query('SELECT * FROM care_requests WHERE id=$1 FOR UPDATE',[requestId]);
  const request=rr.rows[0];
  if(!request||request.status!=='OFFERING'){await c.query('DELETE FROM dispatch_jobs WHERE request_id=$1',[requestId]);await c.query('COMMIT');return true;}
  const waveConfig=await loadWaves(c);
  if(wave>waveConfig.length){
   await c.query(`UPDATE care_requests SET status='UNFULFILLED',version=version+1,updated_at=now() WHERE id=$1`,[requestId]);
   await c.query('DELETE FROM dispatch_jobs WHERE request_id=$1',[requestId]);
   await c.query(`UPDATE request_offers SET status='EXPIRED' WHERE request_id=$1 AND status='OPEN'`,[requestId]);
   await c.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('request.unfulfilled',$1,$2::jsonb)`,[requestId,JSON.stringify({requestId,recipientUserId:request.requester_user_id})]);
   await c.query('COMMIT');return true;
  }
  const cfg=waveConfig[wave-1]!;
  // One set-based SQL statement for all candidates and their outbox events.
  // Before this optimization the worker did 1 SELECT + 2 INSERTs per nurse (N+1).
  // The SELECT and inserts are still guarded by the locked dispatch job + request.
  await c.query(`WITH candidates AS (
      SELECT n.id,n.user_id FROM nurses n
      JOIN nurse_locations nl ON nl.nurse_id=n.id
      JOIN nurse_skills ns ON ns.nurse_id=n.id AND ns.service_id=$2 AND ns.approved=true
      JOIN care_requests req ON req.id=$1
      WHERE n.verified=true AND n.work_status='AVAILABLE' AND n.availability_intent='AVAILABLE'
        AND n.last_heartbeat_at>now()-interval '60 seconds'
        AND nl.recorded_at>now()-interval '120 seconds' AND nl.accuracy_m<=150
        AND EXISTS(SELECT 1 FROM nurse_credentials nc
                   WHERE nc.nurse_id=n.id AND nc.approved=true AND nc.expires_at>now())
        AND NOT EXISTS(SELECT 1 FROM request_offers existing
                       WHERE existing.request_id=req.id AND existing.nurse_id=n.id)
        AND NOT EXISTS(SELECT 1 FROM request_assignments a
                       WHERE a.nurse_id=n.id AND a.status='ACTIVE')
        AND ST_DWithin(nl.location,req.location,$3::double precision)
      ORDER BY ST_Distance(nl.location,req.location),n.id LIMIT $4
    ), inserted AS (
      INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
      SELECT $1,id,$5,now()+($6::integer * interval '1 second') FROM candidates
      ON CONFLICT(request_id,nurse_id) DO NOTHING
      RETURNING id,nurse_id,expires_at
    ), emitted AS (
      INSERT INTO outbox_events(event_type,aggregate_id,payload)
      SELECT 'offer.created',$1,
        jsonb_build_object('requestId',$1,'offerId',i.id,'recipientUserId',n.user_id,'expiresAt',i.expires_at)
      FROM inserted i JOIN nurses n ON n.id=i.nurse_id
      RETURNING id
    ) SELECT count(*)::integer AS emitted_count FROM emitted`,
    [requestId,request.service_id,cfg.radius,cfg.limit,wave,cfg.seconds]);
  await c.query(`UPDATE dispatch_jobs SET next_wave=$2,next_run_at=now()+($3||' seconds')::interval,updated_at=now() WHERE request_id=$1`,[requestId,wave+1,String(cfg.seconds)]);
  await c.query('COMMIT');return true;
 }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
}
async function flushOutbox() {
 if(!redis)return false;
 const c=await pool.connect();
 try{
  await c.query('BEGIN');
  const rows=await c.query(`SELECT * FROM outbox_events WHERE published_at IS NULL ORDER BY id LIMIT 10 FOR UPDATE SKIP LOCKED`);
  const publishedIds:string[]=[];
  for(const event of rows.rows){
   // One Redis publish per recipient event is intentional; NO DB query in this loop.
   // Delivery may be duplicated after process crash, clients must deduplicate by event ID.
   await redis.publish('tamreedy:events',JSON.stringify({eventId:event.id,type:event.event_type,payload:event.payload}));
   publishedIds.push(String(event.id));
  }
  // Best-effort push after publishing; failures never block the outbox (REST stays the source of truth).
  if(fcm) await pushBatch(pool,fcm,rows.rows).catch(e=>console.error('push error',e));
  if(publishedIds.length) await c.query('UPDATE outbox_events SET published_at=now() WHERE id=ANY($1::bigint[])',[publishedIds]);
  await c.query('COMMIT');return (rows.rowCount??0)>0;
 }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
}
async function loop(){
 let stopping=false;
 let lastWinback=0;
 process.on('SIGINT',()=>{stopping=true});process.on('SIGTERM',()=>{stopping=true});
 while(!stopping){
  try{
    const a=await doDispatch(),b=await flushOutbox(),m=await processBroadcast(pool,fcm);
    // Win-back campaign (only does anything while switched on in the marketing page): checked every 6 hours.
    if(Date.now()-lastWinback>6*3600_000){lastWinback=Date.now();const n=await runWinback(pool).catch(e=>{console.error('winback error',e);return 0;});if(n)console.log(`winback: ${n} patients`);}
    if(!a&&!b&&!m) await new Promise(resolve=>setTimeout(resolve,500));
  }catch(e){console.error('worker error',e);await new Promise(resolve=>setTimeout(resolve,1200));}
 }
 await redis?.quit();await pool.end();
}
void loop();
