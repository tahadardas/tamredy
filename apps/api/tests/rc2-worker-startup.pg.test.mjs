import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import pg from 'pg';
const url=process.env.TEST_DATABASE_URL;
test('RC2-027 worker stops before polling when release migration manifest is unavailable',{
  skip:!url&&'Requires explicitly configured isolated PostgreSQL',
},async()=>{
  const parsed=new URL(url);
  assert.ok(['127.0.0.1','localhost','[::1]'].includes(parsed.hostname));
  assert.match(parsed.pathname,/^\/tamreedy_test_\w+$/);
  const admin=new pg.Client({connectionString:url});
  await admin.connect();
  const name='tamreedy_test_worker_'+randomUUID().replaceAll('-','');
  try{await admin.query('CREATE DATABASE '+name);}finally{await admin.end();}
  parsed.pathname='/'+name;
  const worker=fileURLToPath(new URL('../../worker/dist/main.js',import.meta.url));
  const result=spawnSync(process.execPath,[worker],{encoding:'utf8',timeout:20000,windowsHide:true,cwd:tmpdir(),env:{
    ...process.env,DATABASE_URL:parsed.href,NODE_ENV:'test',REDIS_URL:'',
    DOTENV_CONFIG_PATH:join(tmpdir(),name+'.no-env'),
    FCM_SERVICE_ACCOUNT_JSON:'',FCM_SERVICE_ACCOUNT_FILE:'',LIVE_LOCATION_REDIS_ENABLED:'false',
  }});
  assert.equal(result.error,undefined);
  assert.equal(result.status,1);
  assert.match(result.stderr,/MIGRATION_COMPATIBILITY_ERROR/);
  assert.doesNotMatch(result.stdout,/worker.started/);
  // The isolated database is retained for inspection; no reset or historical deletion.
});
