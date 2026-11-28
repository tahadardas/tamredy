import { createHmac, randomBytes, randomUUID } from 'node:crypto';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { featureCapabilities } from '../../../../packages/backend-policy/capabilities.mjs';
import { DbService } from '../db/db.service.js';
import { LiveGateway } from '../realtime/live.gateway.js';
import { TrustService } from '../trust/trust.service.js';
import { OperationalMetricsService } from '../observability/operational-metrics.service.js';
import { buildNotificationPayload, targetAppForRole, type RecipientRole } from '../notifications/notification-routing.js';

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

  private async enqueueCallEvent(
    client: PoolClient, receiverId: string, eventType: string, call: Record<string, any>,
    extra: Record<string, unknown> = {},
  ) {
    const recipient = await client.query("SELECT role FROM users WHERE id=$1 AND status='ACTIVE'", [receiverId]);
    if (!recipient.rowCount) return null;
    const payload = buildNotificationPayload({
      eventType, recipientUserId: receiverId, recipientRole: recipient.rows[0].role as RecipientRole,
      callId: call.id, requestId: call.request_id, entityVersion: Number(call.session_version),
      skipPush: true,
      extra: { ...extra, sessionVersion: Number(call.session_version) },
    });
    await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES($1,$2,$3::jsonb)`,
      [eventType, call.id, JSON.stringify(payload)]);
    return payload;
  }

  private sendCallEvent(receiverId: string, eventType: string, payload: ReturnType<typeof buildNotificationPayload> | null) {
    if (!payload) return;
    // State and the stable event ID are already committed. Delivery remains retryable by the worker.
    void Promise.resolve().then(() => this.live.sendToUser(receiverId, eventType, payload))
      .catch(() => this.metrics.increment('private_event_delivery_failures_total'));
  }

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
    if (!featureCapabilities().voiceEnabled) throw new ServiceUnavailableException({ code: 'VOICE_DISABLED' });
    const request = await this.db.query(
      `SELECT r.id,r.status,r.requester_user_id,n.user_id AS nurse_user_id,patient.role AS patient_role,nurse_user.role AS nurse_role
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

    const sessionResult = await this.db.transaction(async client => {
      for (const participant of [callerUserId, receiverUserId].sort()) {
        await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [participant]);
      }
      if (idempotencyKey) {
        const replay = await client.query(
          `SELECT * FROM voice_call_sessions WHERE caller_user_id=$1 AND initiation_key=$2`,
          [callerUserId, idempotencyKey],
        );
        if (replay.rowCount) return { session: replay.rows[0], callPayload: null, replayed: true };
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
      const callEventId = randomUUID();
      const receiverRole = (isPatient ? visit.nurse_role : visit.patient_role) as RecipientRole;
      const receiverTargetApp = targetAppForRole(receiverRole);
      const callPayload = buildNotificationPayload({
        eventId: callEventId,
        eventType: 'call.incoming',
        recipientUserId: receiverUserId,
        recipientRole: receiverRole,
        targetApp: receiverTargetApp,
        requestId,
        callId: row.id,
        expiresAt: updated.rows[0].ring_expires_at ? new Date(updated.rows[0].ring_expires_at).toISOString() : null,
        extra: {
          callerRole: isPatient ? visit.patient_role : visit.nurse_role,
          ringExpiresAt: updated.rows[0].ring_expires_at,
          sessionVersion: Number(updated.rows[0].session_version),
        },
      });
      await client.query(
        `INSERT INTO outbox_events(event_type,aggregate_id,payload) VALUES('call.incoming',$1,$2::jsonb)`,
        [row.id, JSON.stringify(callPayload)],
      );
      return { session: updated.rows[0], callPayload, replayed: false };
    });
    const session = sessionResult.session;
    if (!sessionResult.replayed && sessionResult.callPayload) {
      this.sendCallEvent(receiverUserId, 'call.incoming', sessionResult.callPayload);
      this.metrics.increment('voice_calls_started_total');
    }
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
      const accepted = updated.rows[0];
      const payload = await this.enqueueCallEvent(client, accepted.caller_user_id, 'call.accepted', accepted, {
        acceptedAt: accepted.accepted_at,
      });
      return { call: accepted, payload };
    });
    this.sendCallEvent(result.call.caller_user_id, 'call.accepted', result.payload);
    return result.call;
  }

  async markConnected(userId: string, callId: string) {
    const result = await this.db.transaction(async client => {
      const row = await client.query(`SELECT * FROM voice_call_sessions WHERE id=$1
        AND $2 IN (caller_user_id,receiver_user_id) FOR UPDATE`, [callId, userId]);
      const current = row.rows[0];
      if (!current || !['ACCEPTED','CONNECTING','CONNECTED','RECONNECTING'].includes(current.call_status)) {
        throw new ConflictException({ code: 'CALL_CANNOT_CONNECT' });
      }
      const peer = current.caller_user_id === userId ? current.receiver_user_id : current.caller_user_id;
      if (current.call_status === 'CONNECTED') return { call: current, peer, payload: null };
      const updated = await client.query(`UPDATE voice_call_sessions SET call_status='CONNECTED',
        connected_at=coalesce(connected_at,now()),session_version=session_version+1 WHERE id=$1 RETURNING *`, [callId]);
      const call = updated.rows[0];
      const payload = await this.enqueueCallEvent(client, peer, 'call.connected', call, { connectedAt: call.connected_at });
      return { call, peer, payload };
    });
    this.sendCallEvent(result.peer, 'call.connected', result.payload);
    return result.call;
  }

  async rejectCall(userId: string, callId: string, reason = 'DECLINED') {
    return this.finish(userId, callId, 'reject', reason);
  }

  async endCall(userId: string, callId: string, reason = 'NORMAL_HANGUP') {
    return this.finish(userId, callId, 'end', reason);
  }

  private async finish(userId: string, callId: string, action: 'reject' | 'end', reason: string) {
    const result = await this.db.transaction(async client => {
      const locked = await client.query('SELECT * FROM voice_call_sessions WHERE id=$1 FOR UPDATE', [callId]);
      if (!locked.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
      const current = locked.rows[0];
      if (![current.caller_user_id, current.receiver_user_id].includes(userId)) {
        throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
      }
      const peer = current.caller_user_id === userId ? current.receiver_user_id : current.caller_user_id;
      if (action === 'end' && (TERMINAL_CALL_STATES as readonly string[]).includes(current.call_status)) {
        return { call: current, peer, eventType: 'call.ended', payload: null };
      }
      const ringing = ['INITIATED', 'RINGING'].includes(current.call_status);
      if (action === 'reject' ? !ringing : !(ACTIVE_CALL_STATES as readonly string[]).includes(current.call_status)) {
        throw new ConflictException({ code: 'CALL_TERMINAL', currentStatus: current.call_status });
      }
      const status = action === 'reject' ? 'REJECTED' : ringing ? 'CANCELLED' : 'ENDED';
      const eventType = action === 'reject' ? 'call.rejected' : ringing ? 'call.cancel' : 'call.ended';
      const updated = await client.query(
        `UPDATE voice_call_sessions SET call_status=$2,ended_at=now(),end_reason=$3,
          duration_seconds=CASE WHEN connected_at IS NULL THEN 0 ELSE greatest(0,extract(epoch FROM now()-connected_at)::integer) END,
          session_version=session_version+1 WHERE id=$1 RETURNING *`, [callId, status, reason],
      );
      await client.query(`DELETE FROM voice_call_events WHERE session_id=$1 AND event_type IN ('SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART')`, [callId]);
      await client.query(`INSERT INTO voice_call_events(session_id,actor_user_id,event_type,event_data) VALUES($1,$2,$3,$4::jsonb)`, [callId, userId, status, JSON.stringify({ reason })]);
      const call = updated.rows[0];
      const payload = await this.enqueueCallEvent(client, peer, eventType, call, { durationSeconds: call.duration_seconds, reason });
      return { call, peer, eventType, payload };
    });
    this.sendCallEvent(result.peer, result.eventType, result.payload);
    return result.call;
  }

  /** BUG-038: Serialize WebRTC signals per session + actor inside one transaction lock to eliminate sequence races. */
  async relaySignal(senderUserId: string, callId: string, dto: CallSignalDto) {
    if (!dto || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(dto.eventId) ||
        !Number.isSafeInteger(dto.sequenceNumber) || dto.sequenceNumber < 1 ||
        !['SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART'].includes(dto.eventType) ||
        !dto.data || typeof dto.data !== 'object' || Array.isArray(dto.data)) {
      throw new BadRequestException({ code: 'INVALID_CALL_SIGNAL' });
    }
    const serialized = JSON.stringify(dto.data);
    if (Buffer.byteLength(serialized, 'utf8') > Number(process.env.CALL_SIGNAL_MAX_BYTES ?? 32_768)) {
      throw new BadRequestException({ code: 'CALL_SIGNAL_TOO_LARGE' });
    }
    const txResult = await this.db.transaction(async client => {
      const callResult = await client.query(
        `SELECT caller_user_id, receiver_user_id, call_status
         FROM voice_call_sessions
         WHERE id=$1 FOR UPDATE`,
        [callId],
      );
      if (!callResult.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
      const call = callResult.rows[0];
      if (![call.caller_user_id, call.receiver_user_id].includes(senderUserId)) {
        throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
      }
      if (!(ACTIVE_CALL_STATES as readonly string[]).includes(call.call_status)) {
        throw new ConflictException({ code: 'CALL_TERMINAL' });
      }
      const duplicate = await client.query('SELECT id,session_id,actor_user_id,sequence_number,event_type,(event_data=$2::jsonb) AS same_data FROM voice_call_events WHERE event_id=$1', [dto.eventId,serialized]);
      if (duplicate.rowCount) {
        const previous = duplicate.rows[0];
        if (previous.session_id !== callId || previous.actor_user_id !== senderUserId ||
            Number(previous.sequence_number) !== dto.sequenceNumber || previous.event_type !== dto.eventType ||
            !previous.same_data) {
          throw new ConflictException({ code: 'CALL_SIGNAL_IDEMPOTENCY_CONFLICT' });
        }
        return { duplicate: true as const, recipientUserId: null as string | null };
      }
      const latest = await client.query(
        `SELECT max(sequence_number)::integer AS sequence_number
         FROM voice_call_events
         WHERE session_id=$1 AND actor_user_id=$2 AND sequence_number IS NOT NULL`,
        [callId, senderUserId],
      );
      const latestSeq = Number(latest.rows[0]?.sequence_number ?? 0);
      if (dto.sequenceNumber <= latestSeq) {
        throw new ConflictException({
          code: 'CALL_SIGNAL_OUT_OF_ORDER',
          latestSequence: latestSeq,
        });
      }
      if (dto.eventType === 'ICE_CANDIDATE') {
        const count = await client.query(
          `SELECT count(*)::integer AS count
           FROM voice_call_events
           WHERE session_id=$1 AND actor_user_id=$2 AND event_type='ICE_CANDIDATE'`,
          [callId, senderUserId],
        );
        if (Number(count.rows[0].count) >= Number(process.env.CALL_MAX_ICE_CANDIDATES ?? 128)) {
          throw new BadRequestException({ code: 'ICE_CANDIDATE_LIMIT_REACHED' });
        }
      }
      try {
        const inserted = await client.query(
          `INSERT INTO voice_call_events(session_id,actor_user_id,event_type,event_data,event_id,sequence_number)
           VALUES($1,$2,$3,$4::jsonb,$5,$6) ON CONFLICT(event_id) WHERE event_id IS NOT NULL DO NOTHING RETURNING id`,
          [callId, senderUserId, dto.eventType, serialized, dto.eventId, dto.sequenceNumber],
        );
        if (!inserted.rowCount) {
          return { duplicate: true as const, recipientUserId: null as string | null };
        }
      } catch (err) {
        if ((err as { code?: string }).code === '23505') {
          throw new ConflictException({ code: 'CALL_SIGNAL_OUT_OF_ORDER' });
        }
        throw err;
      }
      const recipientUserId = call.caller_user_id === senderUserId ? call.receiver_user_id : call.caller_user_id;
      return { duplicate: false as const, recipientUserId };
    });

    if (txResult.duplicate || !txResult.recipientUserId) {
      return { relayed: true, duplicate: true, eventId:dto.eventId, sequenceNumber:dto.sequenceNumber };
    }
    await this.live.sendToUser(txResult.recipientUserId, 'call.signal', {
      callId,
      ...dto,
      signalType: dto.eventType,
      event_id: dto.eventId,
      fromUserId: senderUserId,
    });
    this.metrics.increment('voice_signals_total');
    return { relayed: true, eventId: dto.eventId, sequenceNumber: dto.sequenceNumber };
  }

  async activeCalls(userId: string) {
    const result = await this.db.query(
      `SELECT s.id,s.request_id,s.caller_user_id,s.receiver_user_id,
              ($1 = s.caller_user_id) AS is_caller,
              u1.display_name AS caller_name, u2.display_name AS receiver_name,
              s.ice_servers,
              s.call_status,s.ringing_at,s.ring_expires_at,s.accepted_at,s.connected_at,s.session_version
       FROM voice_call_sessions s
       JOIN users u1 ON u1.id = s.caller_user_id
       JOIN users u2 ON u2.id = s.receiver_user_id
       WHERE $1 IN (s.caller_user_id,s.receiver_user_id)
         AND s.call_status=ANY($2::text[])
       ORDER BY s.created_at DESC LIMIT 2`,
      [userId, [...ACTIVE_CALL_STATES]],
    );
    return result.rows;
  }

  async getCall(userId: string, callId: string, includeSignals = true) {
    const result = await this.db.query(
      `SELECT s.*, ($2 = s.caller_user_id) AS is_caller, u1.display_name AS caller_name, u2.display_name AS receiver_name
       FROM voice_call_sessions s JOIN users u1 ON u1.id=s.caller_user_id JOIN users u2 ON u2.id=s.receiver_user_id WHERE s.id=$1`, [callId, userId],
    );
    if (!result.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
    const call = result.rows[0];
    if (![call.caller_user_id, call.receiver_user_id].includes(userId)) throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
    if (!includeSignals) return call;
    const signals = await this.db.query(
      `SELECT id,event_id,sequence_number,actor_user_id,event_type,event_data,created_at
       FROM voice_call_events WHERE session_id=$1 AND actor_user_id<>$2
         AND event_type IN ('SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART')
       ORDER BY sequence_number ASC NULLS LAST, created_at ASC, id ASC LIMIT 256`, [callId, userId],
    );
    return { ...call, signals: signals.rows };
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
