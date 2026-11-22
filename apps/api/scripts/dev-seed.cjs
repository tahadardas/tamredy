/** Fake local-only development accounts. Never run against patient data. */
const {Client}=require('pg');
const jwt=require('jsonwebtoken');
const dbUrl=process.env.DATABASE_URL;
if(process.env.NODE_ENV!=='development'||!dbUrl||!/^localhost$|^127\.0\.0\.1$/.test(new URL(dbUrl).hostname)){
  throw Error('DEV SEED BLOCKED: requires NODE_ENV=development and local DATABASE_URL host');
}
if(!process.env.JWT_SECRET||process.env.JWT_SECRET.length<32)throw Error('JWT_SECRET must be at least 32 characters');
async function main(){
 const db=new Client({connectionString:dbUrl});await db.connect();
 try{
  const users={};
  await db.query('BEGIN');
  for(const [role,phone] of [['PATIENT','+9990000000001'],['NURSE','+9990000000002'],['ADMIN','+9990000000003']]){
    const r=await db.query(`INSERT INTO users(phone_e164,role,status) VALUES($1,$2,'ACTIVE')
      ON CONFLICT(phone_e164) DO UPDATE SET role=EXCLUDED.role,status='ACTIVE' RETURNING id`,[phone,role]);
    users[role]=r.rows[0].id;
  }
  const b=await db.query(`SELECT id FROM beneficiaries WHERE owner_user_id=$1 LIMIT 1`,[users.PATIENT]);
  if(!b.rowCount)await db.query(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'حالة تجريبية فقط','GRANTED')`,[users.PATIENT]);
  const s=await db.query(`INSERT INTO services(code,title_ar,active,dispatch_approved,requires_prescription,price_amount,currency_code)
    VALUES('DEV_SIMULATION_ONLY','محاكاة طلب غير طبي — للاختبار فقط',true,true,false,1200,'SYP_NEW')
    ON CONFLICT(code) DO UPDATE SET title_ar=EXCLUDED.title_ar RETURNING id`);
  const ns=await db.query(`INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at)
    VALUES($1,true,'AVAILABLE','AVAILABLE',now())
    ON CONFLICT(user_id) DO UPDATE SET verified=true,availability_intent='AVAILABLE',work_status='AVAILABLE',last_heartbeat_at=now() RETURNING id`,[users.NURSE]);
  const nurseId=ns.rows[0].id;
  await db.query(`INSERT INTO nurse_skills(nurse_id,service_id,approved) VALUES($1,$2,true)
    ON CONFLICT(nurse_id,service_id) DO UPDATE SET approved=true`,[nurseId,s.rows[0].id]);
  const cred=await db.query(`SELECT 1 FROM nurse_credentials WHERE nurse_id=$1 AND license_ref='SIMULATION-NOT-A-REAL-LICENSE'`,[nurseId]);
  if(!cred.rowCount)await db.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved,verified_at)
    VALUES($1,'SIMULATION-NOT-A-REAL-LICENSE',now()+interval '30 days',true,now())`,[nurseId]);
  await db.query(`INSERT INTO nurse_locations(nurse_id,location,accuracy_m)
    VALUES($1,ST_SetSRID(ST_MakePoint(36.264,33.503),4326)::geography,30)
    ON CONFLICT(nurse_id) DO UPDATE SET recorded_at=now(),location=EXCLUDED.location,accuracy_m=30`,[nurseId]);
  await db.query('COMMIT');
  console.log('LOCAL DEVELOPMENT ONLY — FAKE USERS, FAKE CREDENTIALS, FAKE MEDICAL SERVICE');
  for(const [role,id] of Object.entries(users)){
    console.log(role+': '+jwt.sign({},process.env.JWT_SECRET,{algorithm:'HS256',subject:id,issuer:process.env.JWT_ISSUER||'tamreedy-api',audience:process.env.JWT_AUDIENCE||'tamreedy-mobile',expiresIn:'3h'}));
  }
 }catch(e){await db.query('ROLLBACK').catch(()=>{});throw e;}finally{await db.end();}
}
main().catch(e=>{console.error(e);process.exit(1)});
