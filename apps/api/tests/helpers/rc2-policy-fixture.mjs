import {readFileSync} from 'node:fs';
/** Expands older deliberately scoped fixtures with the actual RC2 schema/policy. */
export async function installRc2PolicyFixture(pg) {
  await pg.exec(`
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS planned_start_at timestamptz;
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS planned_end_at timestamptz;
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS service_duration_minutes integer;
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS travel_buffer_before_minutes integer NOT NULL DEFAULT 30;
    ALTER TABLE request_assignments ADD COLUMN IF NOT EXISTS travel_buffer_after_minutes integer NOT NULL DEFAULT 30;
    CREATE TABLE IF NOT EXISTS nurse_calendar_blocks(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      nurse_id uuid REFERENCES nurses(id),start_time timestamptz,end_time timestamptz);
    ALTER TABLE care_requests ADD COLUMN IF NOT EXISTS booking_mode text NOT NULL DEFAULT 'INSTANT';
    ALTER TABLE care_requests ADD COLUMN IF NOT EXISTS latest_acceptable_arrival_at timestamptz;
    ALTER TABLE care_requests ADD COLUMN IF NOT EXISTS open_expires_at timestamptz;
    CREATE TABLE IF NOT EXISTS device_sessions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid REFERENCES users(id),device_id text,app_kind text,revoked_at timestamptz);
    ALTER TABLE nurse_locations ADD COLUMN IF NOT EXISTS captured_at timestamptz;
    ALTER TABLE nurse_locations ADD COLUMN IF NOT EXISTS received_at timestamptz;
    ALTER TABLE nurse_locations ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES device_sessions(id);
    UPDATE nurse_locations SET captured_at=recorded_at,received_at=recorded_at;
    INSERT INTO device_sessions(user_id,device_id,app_kind)
      SELECT n.user_id,'rc2-fixture-'||n.id::text,'nurse' FROM nurses n
      WHERE NOT EXISTS(SELECT 1 FROM device_sessions ds WHERE ds.user_id=n.user_id);
    UPDATE nurse_locations l SET session_id=(SELECT ds.id FROM device_sessions ds JOIN nurses n ON n.user_id=ds.user_id
      WHERE n.id=l.nurse_id ORDER BY ds.id LIMIT 1);
  `);
  const folder=new URL('../../../../infra/db/migrations/',import.meta.url);
  const schedule=readFileSync(new URL('054_scheduling_reservations.sql',folder),'utf8');
  await pg.exec(schedule.slice(schedule.indexOf('CREATE OR REPLACE FUNCTION nurse_has_schedule_conflict')));
  for (const name of ['071_rc2_currency_accounts','072_rc2_shared_eligibility']) {
    if (!(await pg.query(`SELECT 1 FROM information_schema.tables WHERE table_name='nurse_financial_currency_accounts'`)).rows.length || name.startsWith('072'))
      await pg.exec(readFileSync(new URL(name+'.sql',folder),'utf8'));
  }
  // Synthetic test accounts receive explicit currency allocations, never a
  // production backfill of unproven legacy balances.
  await pg.exec(`INSERT INTO nurse_financial_currency_accounts(nurse_id,currency_code,financial_model,credit_limit,prepaid_balance)
    SELECT n.nurse_id,c.currency_code,n.financial_model,n.credit_limit,n.prepaid_balance
    FROM nurse_financial_accounts n CROSS JOIN (SELECT DISTINCT currency_code FROM care_requests) c
    ON CONFLICT(nurse_id,currency_code) DO NOTHING`);
}
