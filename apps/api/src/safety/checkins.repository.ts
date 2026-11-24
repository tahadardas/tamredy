import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { SafetyCheckinResponseDto } from './safety.dto.js';

@Injectable()
export class CheckinsRepository {
  constructor(private readonly db: DbService) {}

  async pending(owner: string, session: string) {
    return (await this.db.query(`SELECT c.id,c.created_at,c.remind_at,c.deadline_at,c.snoozed_at
      FROM safety_checkins c JOIN safety_sessions s ON s.id=c.session_id
      JOIN request_assignments a ON a.id=s.assignment_id JOIN nurses n ON n.id=a.nurse_id
      WHERE c.session_id=$1 AND n.user_id=$2 AND c.state='PENDING' AND c.deadline_at>clock_timestamp()`, [session, owner])).rows[0] ?? null;
  }

  async response(client: PoolClient, session: string, key: string) {
    return (await client.query(`SELECT checkin_id,response,responded_at FROM safety_checkin_responses
      WHERE session_id=$1 AND client_response_id=$2`, [session, key])).rows[0];
  }

  async current(client: PoolClient, session: string, checkin: string) {
    return (await client.query(`SELECT c.*,c.deadline_at>clock_timestamp() AS can_answer,v.extension_seconds,v.interval_seconds
      FROM safety_checkins c JOIN safety_sessions s ON s.id=c.session_id
      JOIN safety_policy_versions v ON v.id=s.policy_version_id WHERE c.id=$1 AND s.id=$2`,
    [checkin, session])).rows[0];
  }

  async saveResponse(client: PoolClient, session: string, dto: SafetyCheckinResponseDto) {
    return (await client.query(`INSERT INTO safety_checkin_responses(session_id,checkin_id,client_response_id,response)
      VALUES($1,$2,$3,$4) RETURNING checkin_id,response,responded_at`,
    [session, dto.checkinId, dto.clientResponseId, dto.response])).rows[0];
  }

  async extend(client: PoolClient, checkin: string, seconds: number) {
    await client.query(`UPDATE safety_checkins SET snoozed_at=now(),reminded_at=NULL,
      deadline_at=deadline_at+$2::integer*interval '1 second',
      remind_at=deadline_at WHERE id=$1`, [checkin, seconds]);
  }

  async finish(client: PoolClient, session: string, checkin: string, interval: number) {
    await client.query("UPDATE safety_checkins SET state='ANSWERED' WHERE id=$1", [checkin]);
    await client.query(`UPDATE safety_sessions SET next_checkin_at=now()+$2::integer*interval '1 second'
      WHERE id=$1`, [session, interval]);
  }

  async alert(client: PoolClient, session: string, checkin: string, kind: string) {
    const alert = (await client.query(`INSERT INTO safety_alerts(session_id,checkin_id,kind)
      VALUES($1,$2,$3) RETURNING id`, [session, checkin, kind])).rows[0];
    await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES('safety.alert_created',$1,jsonb_build_object('alertId',$1::uuid))`, [alert.id]);
  }
}
