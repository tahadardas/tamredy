import {test} from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { requiredMigrations, missingMigrations } from '../../../packages/backend-policy/schema.mjs';
import { featureCapabilities, bookingCapabilityError, ordersState } from '../../../packages/backend-policy/capabilities.mjs';
import { ReadinessService } from '../dist/capabilities/readiness.service.js';
import { FeatureCapabilitiesService } from '../dist/capabilities/feature-capabilities.service.js';

test('release manifest requires every migration including an interior missing migration',()=>{
  assert.deepEqual([...requiredMigrations],readdirSync(new URL('../../../infra/db/migrations/',import.meta.url)).filter(n=>n.endsWith('.sql')).sort());
  assert.deepEqual(missingMigrations(requiredMigrations.filter((_,i)=>i!==5)),[requiredMigrations[5]]);
});
test('missing orders settings fail closed; optional feature gates do not auto enable',()=>{
  assert.equal(ordersState(null).accepting,false);
  assert.equal(ordersState({}).status,'unavailable');
  assert.equal(ordersState({accepting:true}).accepting,true);
  const caps=featureCapabilities({});
  assert.equal(bookingCapabilityError('SCHEDULED',caps),'SCHEDULED_VISITS_DISABLED');
  assert.equal(caps.openDispatchEnabled,false);
  assert.equal(caps.liveLocationRedisEnabled,false);
});
function probe(overrides={}) {
  const db={poolStats:()=>({}),async query(sql){
    if(sql==='SELECT 1')return {rows:[{}]};
    if(sql.includes('schema_migrations'))return {rows:requiredMigrations.map(name=>({name}))};
    if(sql.includes('FROM outbox_events'))return {rows:[{pending_realtime:0,pending_push:0,oldest_realtime:null,oldest_push:null,dead_letter_count:0}]};
    if(sql.includes('worker_heartbeats'))return {rows:[{last_seen:new Date()}]};
    if(sql.includes('app_settings'))return {rows:[{value:{accepting:true}}]};
    throw new Error('unexpected SQL');
  },...overrides};
  return new ReadinessService(db,{async healthStatus(){return {enabled:true,connected:true};}},new FeatureCapabilitiesService(db));
}
test('readiness rejects database, monitor, missing migration, heartbeat and backlog failures',async()=>{
  const previous={PUSH_ENABLED:process.env.PUSH_ENABLED,VOICE_ENABLED:process.env.VOICE_ENABLED};
  process.env.PUSH_ENABLED='false';process.env.VOICE_ENABLED='false';
  try {
    assert.equal((await probe().report()).status,'ready');
    const base=probe;
    for(const [pattern,result,code] of [
      ['schema_migrations',{rows:requiredMigrations.slice(1).map(name=>({name}))},'MIGRATION_COMPATIBILITY_ERROR'],
      ['worker_heartbeats',{rows:[{last_seen:null}]},'WORKER_UNAVAILABLE'],
      ['FROM outbox_events',{rows:[{pending_realtime:1,pending_push:0,oldest_realtime:new Date(Date.now()-300000),dead_letter_count:0}]},'OUTBOX_UNHEALTHY'],
    ]){
      const original=probe();
      const db=original.db;
      const query=db.query.bind(db);
      db.query=async(sql)=>sql.includes(pattern)?result:query(sql);
      await assert.rejects(original.report(),e=>e.getStatus()===503&&e.getResponse().failures.includes(code));
    }
    const unavailable=probe();
    const query=unavailable.db.query.bind(unavailable.db);
    unavailable.db.query=async(sql)=>{if(sql.includes('FROM outbox_events'))throw new Error('schema query failed');return query(sql);};
    await assert.rejects(unavailable.report(),e=>e.getResponse().checks.outbox.status==='unknown'&&e.getResponse().failures.includes('OUTBOX_MONITOR_UNAVAILABLE'));
    await assert.rejects(probe({async query(){throw new Error('db down');}}).report(),e=>e.getResponse().code==='DATABASE_UNAVAILABLE');
  }finally{
    for(const [key,value]of Object.entries(previous)){if(value===undefined)delete process.env[key];else process.env[key]=value;}
  }
});

test('actual PostgreSQL outbox monitor counts required channels, expiry and dead letters',async()=>{
  const {PGlite}=await import('@electric-sql/pglite');
  const {OUTBOX_HEALTH_SQL}=await import('../dist/capabilities/readiness-queries.js');
  const db=new PGlite();
  try{
    await db.exec(`CREATE TABLE outbox_events(created_at timestamptz DEFAULT now(),payload jsonb DEFAULT '{}',
      realtime_published_at timestamptz,realtime_dead_at timestamptz,push_published_at timestamptz,push_dead_at timestamptz);
      INSERT INTO outbox_events(payload,realtime_published_at) VALUES
        ('{"skipPush":true}',now()),
        ('{"expiresAt":"2000-01-01T00:00:00Z"}',now()),
        ('{}',now());
      INSERT INTO outbox_events(payload,push_dead_at,realtime_published_at) VALUES('{}',now(),now());`);
    const row=(await db.query(OUTBOX_HEALTH_SQL)).rows[0];
    assert.equal(row.pending_push,1);
    assert.equal(row.pending_realtime,0);
    assert.equal(row.dead_letter_count,1);
  }finally{await db.close();}
});
