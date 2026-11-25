import { createHmac, randomBytes } from 'node:crypto';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { LiveGateway } from '../realtime/live.gateway.js';
import { TrustService } from '../trust/trust.service.js';
import { OperationalMetricsService } from '../observability/operational-metrics.service.js';

const ACTIVE_CALL_STATES = ['INITIATED', 'RINGING', 'ACCEPTED', 'CONNECTING', 'CONNECTED', 'RECONNECTING'] as const;
const TERMINAL_CALL_STATES = ['ENDED', 'REJECTED', 'MISSED', 'FAILED', 'CANCELLED'] as const;

export interface CallSignalDto {
  eventId: string;
  sequenceNumber: number;
  eventType: 'SDP_OFFER' | 'SDP_ANSWER' | 'ICE_CANDIDATE' | 'ICE_RESTART';
  data: Record<string, unknown>;
}

export interface CallQualityDto {
  rttMs?: number;
  jitterMs?: number;
  packetLossPercent?: number;
  bitrateKbps?: number;
  candidateType?: string;
  connectionType?: string;
  turnUsed?: boolean;
  reconnectionCount?: number;
}

@Injectable()
export class VoiceService {
  constructor(
    private readonly db: DbService,
    private readonly live: LiveGateway,
    private readonly trust: TrustService,
    private readonly metrics: OperationalMetricsService,
  ) {}

  private getIceServers(userId: string, callId: string) {
    const servers: Record<string, unknown>[] = [];
    const stunUrls = (process.env.STUN_URLS ?? 'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302')
      .split(',').map(value => value.trim()).filter(Boolean);
    if (stunUrls.length) servers.push({ urls: stunUrls });
    const turnUrls = process.env.TURN_URLS?.split(',').map(value => value.trim()).filter(Boolean) ?? [];
    const sharedSecret = process.env.TURN_SHARED_SECRET;
    if (turnUrls.length && sharedSecret) {
      const expiresAt = Math.floor(Date.now() / 1000) + Number(process.env.TURN_CREDENTIAL_TTL_SECONDS ?? 900);
      const username = `${expiresAt}:${userId}:${callId}`;
      const credential = createHmac('sha1', sharedSecret).update(username).digest('base64');
      servers.push({ urls: turnUrls, username, credential });
    }
    return servers;
  }

  async initiateCall(callerUserId: string, requestId: string, idempotencyKey?: string) {
    const request = await this.db.query(
      `SELECT r.id,r.status,r.requester_user_id,n.user_id AS nurse_user_id
       FROM care_requests r
       JOIN request_assignments a ON a.request_id=r.id AND a.status='ACTIVE'
       JOIN nurses n ON n.id=a.nurse_id
       JOIN users patient ON patient.id=r.requester_user_id AND patient.status='ACTIVE'
       JOIN users nurse_user ON nurse_user.id=n.user_id AND nurse_user.status='ACTIVE'
       WHERE r.id=$1`,
      [requestId],
    );
    if (!request.rowCount) throw new NotFoundException({ code: 'ACTIVE_VISIT_NOT_FOUND' });
    const visit = request.rows[0];
    if (!['ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE'].includes(visit.status)) {
      throw new BadRequestException({ code: 'CALL_ONLY_ALLOWED_DURING_ACTIVE_VISIT' });
    }
    const isPatient = visit.requester_user_id === callerUserId;
    const isNurse = visit.nurse_user_id === callerUserId;
    if (!isPatient && !isNurse) throw new ForbiddenException({ code: 'NOT_VISIT_PARTICIPANT' });
    const receiverUserId = isPatient ? visit.nurse_user_id : visit.requester_user_id;
    if (await this.trust.isMutuallyBlocked(callerUserId, receiverUserId)) {
      throw new ConflictException({ code: 'CALL_BLOCKED' });
    }

    const session = await this.db.transaction(async client => {
      for (const participant of [callerUserId, receiverUserId].sort()) {
        await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [participant]);
      }
      if (idempotencyKey) {
        const replay = await client.query(
          `SELECT * FROM voice_call_sessions WHERE caller_user_id=$1 AND initiation_key=$2`,
          [callerUserId, idempotencyKey],
        );
        if (replay.rowCount) return replay.rows[0];
      }
      const active = await client.query(
        `SELECT id FROM voice_call_sessions
         WHERE call_status=ANY($3::text[])
           AND (caller_user_id IN ($1,$2) OR receiver_user_id IN ($1,$2))
         LIMIT 1 FOR UPDATE`,
        [callerUserId, receiverUserId, [...ACTIVE_CALL_STATES]],
      );
      if (active.rowCount) throw new ConflictException({ code: 'CALL_ALREADY_IN_PROGRESS', callId: active.rows[0].id });
      const ringSeconds = Number(process.env.CALL_RING_TIMEOUT_SECONDS ?? 40);
      const created = await client.query(
        `INSERT INTO voice_call_sessions(
           request_id,caller_user_id,receiver_user_id,call_status,room_token,ice_servers,
           initiation_key,ringing_at,ring_expires_at)
         VALUES($1,$2,$3,'RINGING',$4,'[]'::jsonb,$5,statement_timestamp(),
           statement_timestamp()+$6::integer*interval '1 second') RETURNING *`,
        [requestId, callerUserId, receiverUserId, `room_${randomBytes(24).toString('base64url')}`, idempotencyKey ?? null, ringSeconds],
      );
      const row = created.rows[0];
      const updated = await client.query(
        'UPDATE voice_call_sessions SET ice_servers=$2::jsonb WHERE id=$1 RETURNING *',
        [row.id, JSON.stringify(this.getIceServers(callerUserId, row.id))],
      );
      await client.query(
        `INSERT INTO voice_call_events(session_id,actor_user_id,event_type,event_data)
         VALUES($1,$2,'RINGING','{}'::jsonb)`,
        [row.id, callerUserId],
      );
      await client.query(
        `INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('call.incoming',$1,$2::jsonb)`,
        [row.id, JSON.stringify({ recipientUserId: receiverUserId, callId: row.id, requestId })],
      );
      return updated.rows[0];
    });
    await this.live.sendToUser(receiverUserId, 'call.incoming', {
      callId: session.id, requestId, callerRole: isPatient ? 'PATIENT' : 'NURSE', ringExpiresAt: session.ring_expires_at,
    });
    this.metrics.increment('voice_calls_started_total');
    return session;
  }

  async acceptCall(receiverUserId: string, callId: string) {
    const result = await this.db.transaction(async client => {
      const locked = await client.query('SELECT * FROM voice_call_sessions WHERE id=$1 FOR UPDATE', [callId]);
      if (!locked.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
      const call = locked.rows[0];
      if (call.receiver_user_id !== receiverUserId) throw new ForbiddenException({ code: 'NOT_CALL_RECEIVER' });
      if (new Date(call.ring_expires_at).getTime() <= Date.now()) {
        throw new ConflictException({ code: 'CALL_RING_EXPIRED' });
      }
      if (!['INITIATED', 'RINGING'].includes(call.call_status)) {
        throw new ConflictException({ code: 'CALL_NOT_RINGING', currentStatus: call.call_status });
      }
      const updated = await client.query(
        `UPDATE voice_call_sessions SET call_status='ACCEPTED',accepted_at=now(),session_version=session_version+1
         WHERE id=$1 RETURNING *`, [callId],
      );
      await client.query(`INSERT INTO voice_call_events(session_id,actor_user_id,event_type) VALUES($1,$2,'ACCEPTED')`, [callId, receiverUserId]);
      return updated.rows[0];
    });
    await this.live.sendToUser(result.caller_user_id, 'call.accepted', { callId, acceptedAt: result.accepted_at });
    return result;
  }

  async markConnected(userId: string, callId: string) {
    const result = await this.db.query(
      `UPDATE voice_call_sessions SET call_status='CONNECTED',connected_at=coalesce(connected_at,now()),
        session_version=session_version+CASE WHEN call_status='CONNECTED' THEN 0 ELSE 1 END
       WHERE id=$1 AND $2 IN (caller_user_id,receiver_user_id)
         AND call_status IN ('ACCEPTED','CONNECTING','CONNECTED','RECONNECTING') RETURNING *`, [callId, userId],
    );
    if (!result.rowCount) throw new ConflictException({ code: 'CALL_CANNOT_CONNECT' });
    const call = result.rows[0];
    const peer = call.caller_user_id === userId ? call.receiver_user_id : call.caller_user_id;
    await this.live.sendToUser(peer, 'call.connected', { callId, connectedAt: call.connected_at });
    return call;
  }

  async rejectCall(userId: string, callId: string, reason = 'DECLINED') {
    const result = await this.finish(userId, callId, 'REJECTED', reason, ['INITIATED', 'RINGING']);
    const peer = result.caller_user_id === userId ? result.receiver_user_id : result.caller_user_id;
    await this.live.sendToUser(peer, 'call.rejected', { callId, reason });
    return result;
  }

  async endCall(userId: string, callId: string, reason = 'NORMAL_HANGUP') {
    const current = await this.db.query('SELECT call_status FROM voice_call_sessions WHERE id=$1', [callId]);
    if (!current.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
    if ((TERMINAL_CALL_STATES as readonly string[]).includes(current.rows[0].call_status)) return this.getCall(userId, callId, false);
    const cancelled = ['INITIATED', 'RINGING'].includes(current.rows[0].call_status);
    const result = await this.finish(userId, callId, cancelled ? 'CANCELLED' : 'ENDED', reason, [...ACTIVE_CALL_STATES]);
    const peer = result.caller_user_id === userId ? result.receiver_user_id : result.caller_user_id;
    await this.live.sendToUser(peer, cancelled ? 'call.cancel' : 'call.ended', { callId, durationSeconds: result.duration_seconds, reason });
    return result;
  }

  private async finish(userId: string, callId: string, status: string, reason: string, allowed: readonly string[]) {
    return this.db.transaction(async client => {
      const result = await client.query('SELECT * FROM voice_call_sessions WHERE id=$1 FOR UPDATE', [callId]);
      if (!result.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
      const call = result.rows[0];
      if (![call.caller_user_id, call.receiver_user_id].includes(userId)) throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
      if (!allowed.includes(call.call_status)) throw new ConflictException({ code: 'CALL_TERMINAL', currentStatus: call.call_status });
      const updated = await client.query(
        `UPDATE voice_call_sessions SET call_status=$2,ended_at=now(),end_reason=$3,
          duration_seconds=CASE WHEN connected_at IS NULL THEN 0 ELSE greatest(0,extract(epoch FROM now()-connected_at)::integer) END,
          session_version=session_version+1 WHERE id=$1 RETURNING *`, [callId, status, reason],
      );
      await client.query(`DELETE FROM voice_call_events WHERE session_id=$1 AND event_type IN ('SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART')`, [callId]);
      await client.query(`INSERT INTO voice_call_events(session_id,actor_user_id,event_type,event_data) VALUES($1,$2,$3,$4::jsonb)`, [callId, userId, status, JSON.stringify({ reason })]);
      return updated.rows[0];
    });
  }

  async relaySignal(senderUserId: string, callId: string, dto: CallSignalDto) {
    const serialized = JSON.stringify(dto.data);
    if (Buffer.byteLength(serialized, 'utf8') > Number(process.env.CALL_SIGNAL_MAX_BYTES ?? 32_768)) {
      throw new BadRequestException({ code: 'CALL_SIGNAL_TOO_LARGE' });
    }
    const callResult = await this.db.query(`SELECT caller_user_id,receiver_user_id,call_status FROM voice_call_sessions WHERE id=$1`, [callId]);
    if (!callResult.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
    const call = callResult.rows[0];
    if (![call.caller_user_id, call.receiver_user_id].includes(senderUserId)) throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
    if (!(ACTIVE_CALL_STATES as readonly string[]).includes(call.call_status)) throw new ConflictException({ code: 'CALL_TERMINAL' });
    const duplicate = await this.db.query('SELECT 1 FROM voice_call_events WHERE event_id=$1', [dto.eventId]);
    if (duplicate.rowCount) return { relayed: true, duplicate: true };
    const latest = await this.db.query(
      `SELECT max(sequence_number)::integer AS sequence_number FROM voice_call_events
       WHERE session_id=$1 AND actor_user_id=$2 AND sequence_number IS NOT NULL`,
      [callId, senderUserId],
    );
    if (dto.sequenceNumber <= Number(latest.rows[0]?.sequence_number ?? 0)) {
      throw new ConflictException({ code: 'CALL_SIGNAL_OUT_OF_ORDER' });
    }
    if (dto.eventType === 'ICE_CANDIDATE') {
      const count = await this.db.query(
        `SELECT count(*)::integer AS count FROM voice_call_events WHERE session_id=$1 AND actor_user_id=$2 AND event_type='ICE_CANDIDATE'`,
        [callId, senderUserId],
      );
      if (Number(count.rows[0].count) >= Number(process.env.CALL_MAX_ICE_CANDIDATES ?? 128)) {
        throw new BadRequestException({ code: 'ICE_CANDIDATE_LIMIT_REACHED' });
      }
    }
    const inserted = await this.db.query(
      `INSERT INTO voice_call_events(session_id,actor_user_id,event_type,event_data,event_id,sequence_number)
       VALUES($1,$2,$3,$4::jsonb,$5,$6) ON CONFLICT(event_id) DO NOTHING RETURNING id`,
      [callId, senderUserId, dto.eventType, serialized, dto.eventId, dto.sequenceNumber],
    );
    if (!inserted.rowCount) return { relayed: true, duplicate: true };
    const recipientUserId = call.caller_user_id === senderUserId ? call.receiver_user_id : call.caller_user_id;
    await this.live.sendToUser(recipientUserId, 'call.signal', { callId, ...dto, fromUserId: senderUserId });
    this.metrics.increment('voice_signals_total');
    return { relayed: true, eventId: dto.eventId, sequenceNumber: dto.sequenceNumber };
  }

  async activeCalls(userId: string) {
    const result = await this.db.query(
      `SELECT id,request_id,caller_user_id,receiver_user_id,call_status,ringing_at,ring_expires_at,accepted_at,connected_at,session_version
       FROM voice_call_sessions WHERE $1 IN (caller_user_id,receiver_user_id)
         AND call_status=ANY($2::text[]) ORDER BY created_at DESC LIMIT 2`,
      [userId, [...ACTIVE_CALL_STATES]],
    );
    return result.rows;
  }

  async getCall(userId: string, callId: string, includeSignals = true) {
    const result = await this.db.query(
      `SELECT s.*,u1.display_name AS caller_name,u2.display_name AS receiver_name
       FROM voice_call_sessions s JOIN users u1 ON u1.id=s.caller_user_id JOIN users u2 ON u2.id=s.receiver_user_id WHERE s.id=$1`, [callId],
    );
    if (!result.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
    const call = result.rows[0];
    if (![call.caller_user_id, call.receiver_user_id].includes(userId)) throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
    if (!includeSignals) return call;
    const signals = await this.db.query(
      `SELECT id,event_id,sequence_number,actor_user_id,event_type,event_data,created_at
       FROM voice_call_events WHERE session_id=$1 AND actor_user_id<>$2
         AND event_type IN ('SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART')
       ORDER BY created_at DESC,id DESC LIMIT 256`, [callId, userId],
    );
    return { ...call, signals: signals.rows.reverse() };
  }

  async recordQuality(userId: string, callId: string, quality: CallQualityDto) {
    const call = await this.getCall(userId, callId, false) as Record<string, unknown>;
    await this.db.query(
      `INSERT INTO voice_call_quality_samples(session_id,reporter_user_id,rtt_ms,jitter_ms,packet_loss_percent,
        bitrate_kbps,candidate_type,connection_type,turn_used,reconnection_count)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [callId, userId, quality.rttMs ?? null, quality.jitterMs ?? null, quality.packetLossPercent ?? null,
        quality.bitrateKbps ?? null, quality.candidateType ?? null, quality.connectionType ?? null,
        quality.turnUsed ?? null, quality.reconnectionCount ?? 0],
    );
    return { recorded: true, sessionVersion: call.session_version };
  }
}
