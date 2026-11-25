import { randomBytes } from 'node:crypto';
import { Injectable, BadRequestException, ForbiddenException, NotFoundException, ConflictException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { LiveGateway } from '../realtime/live.gateway.js';
import { TrustService } from '../trust/trust.service.js';

export interface InitiateCallDto {
  requestId: string;
}

export interface CallSignalDto {
  eventType: 'SDP_OFFER' | 'SDP_ANSWER' | 'ICE_CANDIDATE';
  data: Record<string, unknown>;
}

@Injectable()
export class VoiceService {
  constructor(
    private readonly db: DbService,
    private readonly live: LiveGateway,
    private readonly trust: TrustService,
  ) {}

  /** Standard public STUN + optional TURN configuration for reliable WebRTC audio across NAT/4G */
  private getIceServers() {
    const servers: Record<string, unknown>[] = [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
    ];
    const turnUrls = process.env.TURN_URLS?.split(',').map(s => s.trim()).filter(Boolean);
    if (turnUrls && turnUrls.length > 0) {
      servers.push({
        urls: turnUrls,
        ...(process.env.TURN_USERNAME ? { username: process.env.TURN_USERNAME } : {}),
        ...(process.env.TURN_CREDENTIAL ? { credential: process.env.TURN_CREDENTIAL } : {}),
      });
    }
    return servers;
  }

  /** Initiates an in-app voice call session between visit participants */
  async initiateCall(callerUserId: string, requestId: string) {
    const reqRes = await this.db.query(`
      SELECT cr.id, cr.status, cr.requester_user_id,
             ra.nurse_id, n.user_id AS nurse_user_id
      FROM care_requests cr
      LEFT JOIN request_assignments ra ON ra.request_id = cr.id AND ra.status = 'ACTIVE'
      LEFT JOIN nurses n ON n.id = ra.nurse_id
      WHERE cr.id = $1
    `, [requestId]);

    if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
    const req = reqRes.rows[0];

    // Must be an active visit underway
    if (!['ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE'].includes(req.status)) {
      throw new BadRequestException({ code: 'CALL_ONLY_ALLOWED_DURING_ACTIVE_VISIT' });
    }

    if (!req.nurse_user_id) {
      throw new BadRequestException({ code: 'NO_ASSIGNED_NURSE' });
    }

    const isPatient = req.requester_user_id === callerUserId;
    const isNurse = req.nurse_user_id === callerUserId;
    if (!isPatient && !isNurse) {
      throw new ForbiddenException({ code: 'NOT_VISIT_PARTICIPANT' });
    }

    const receiverUserId = isPatient ? req.nurse_user_id : req.requester_user_id;

    // Check mutual blocking
    const blocked = await this.trust.isMutuallyBlocked(callerUserId, receiverUserId);
    if (blocked) {
      throw new ConflictException({ code: 'CALL_BLOCKED' });
    }

    return this.db.transaction(async client => {
      // Check if an active call session already exists for this visit
      const activeCall = await client.query(`
        SELECT id FROM voice_call_sessions
        WHERE request_id = $1 AND call_status IN ('INITIATED', 'RINGING', 'ACCEPTED', 'CONNECTING', 'CONNECTED')
        LIMIT 1
      `, [requestId]);

      if (activeCall.rowCount) {
        throw new ConflictException({ code: 'CALL_ALREADY_IN_PROGRESS' });
      }

      const roomToken = `room_${randomBytes(24).toString('base64url')}`;
      const iceServers = this.getIceServers();

      const sessionRes = await client.query(`
        INSERT INTO voice_call_sessions(
          request_id, caller_user_id, receiver_user_id, call_status,
          room_token, ice_servers
        )
        VALUES($1, $2, $3, 'INITIATED', $4, $5::jsonb)
        RETURNING *
      `, [requestId, callerUserId, receiverUserId, roomToken, JSON.stringify(iceServers)]);

      const session = sessionRes.rows[0];

      // Record call event
      await client.query(`
        INSERT INTO voice_call_events(session_id, actor_user_id, event_type)
        VALUES($1, $2, 'INITIATED')
      `, [session.id, callerUserId]);

      // Emit realtime incoming call event to receiver
      await this.live.sendToUser(receiverUserId, 'call.incoming', {
        callId: session.id,
        requestId,
        callerUserId,
        callerRole: isPatient ? 'PATIENT' : 'NURSE',
        roomToken,
      });

      // Outbox push event
      await client.query(`
        INSERT INTO outbox_events(event_type, aggregate_id, payload)
        VALUES('call.incoming', $1, $2::jsonb)
      `, [session.id, JSON.stringify({ recipientUserId: receiverUserId, callId: session.id, requestId })]);

      return session;
    });
  }

  /** Accepts an incoming call */
  async acceptCall(receiverUserId: string, callId: string) {
    return this.db.transaction(async client => {
      const res = await client.query(`
        SELECT * FROM voice_call_sessions WHERE id = $1 FOR UPDATE
      `, [callId]);

      if (!res.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
      const call = res.rows[0];

      if (call.receiver_user_id !== receiverUserId) {
        throw new ForbiddenException({ code: 'NOT_CALL_RECEIVER' });
      }

      if (!['INITIATED', 'RINGING'].includes(call.call_status)) {
        throw new BadRequestException({ code: 'CALL_NOT_IN_RINGING_STATE', currentStatus: call.call_status });
      }

      const updated = await client.query(`
        UPDATE voice_call_sessions
        SET call_status = 'ACCEPTED', connected_at = now()
        WHERE id = $1
        RETURNING *
      `, [callId]);

      await client.query(`
        INSERT INTO voice_call_events(session_id, actor_user_id, event_type)
        VALUES($1, $2, 'ACCEPTED')
      `, [callId, receiverUserId]);

      // Notify caller
      await this.live.sendToUser(call.caller_user_id, 'call.accepted', {
        callId,
        connectedAt: updated.rows[0].connected_at,
      });

      return updated.rows[0];
    });
  }

  /** Rejects an incoming call */
  async rejectCall(receiverUserId: string, callId: string, reason = 'DECLINED') {
    return this.db.transaction(async client => {
      const res = await client.query(`
        SELECT * FROM voice_call_sessions WHERE id = $1 FOR UPDATE
      `, [callId]);

      if (!res.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
      const call = res.rows[0];

      if (call.receiver_user_id !== receiverUserId && call.caller_user_id !== receiverUserId) {
        throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
      }

      const updated = await client.query(`
        UPDATE voice_call_sessions
        SET call_status = 'REJECTED', ended_at = now(), end_reason = $2
        WHERE id = $1
        RETURNING *
      `, [callId, reason]);

      const otherUserId = call.caller_user_id === receiverUserId ? call.receiver_user_id : call.caller_user_id;
      await this.live.sendToUser(otherUserId, 'call.rejected', { callId, reason });

      return updated.rows[0];
    });
  }

  /** Ends an active call session */
  async endCall(userId: string, callId: string, reason = 'NORMAL_HANGUP') {
    return this.db.transaction(async client => {
      const res = await client.query(`
        SELECT * FROM voice_call_sessions WHERE id = $1 FOR UPDATE
      `, [callId]);

      if (!res.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
      const call = res.rows[0];

      if (call.caller_user_id !== userId && call.receiver_user_id !== userId) {
        throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
      }

      if (call.call_status === 'ENDED') {
        return call;
      }

      const connectedAt = call.connected_at ? new Date(call.connected_at).getTime() : Date.now();
      const durationSeconds = call.connected_at ? Math.max(0, Math.round((Date.now() - connectedAt) / 1000)) : 0;

      const updated = await client.query(`
        UPDATE voice_call_sessions
        SET call_status = 'ENDED', ended_at = now(), duration_seconds = $2, end_reason = $3
        WHERE id = $1
        RETURNING *
      `, [callId, durationSeconds, reason]);

      const otherUserId = call.caller_user_id === userId ? call.receiver_user_id : call.caller_user_id;
      await this.live.sendToUser(otherUserId, 'call.ended', {
        callId,
        durationSeconds,
        reason,
      });

      return updated.rows[0];
    });
  }

  /** Relays WebRTC signaling data (SDP Offer / Answer / ICE Candidates) */
  async relaySignal(senderUserId: string, callId: string, dto: CallSignalDto) {
    const res = await this.db.query(`
      SELECT caller_user_id, receiver_user_id, call_status FROM voice_call_sessions WHERE id = $1
    `, [callId]);

    if (!res.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
    const call = res.rows[0];

    if (call.caller_user_id !== senderUserId && call.receiver_user_id !== senderUserId) {
      throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
    }

    const recipientUserId = call.caller_user_id === senderUserId ? call.receiver_user_id : call.caller_user_id;

    // Record signaling event
    await this.db.query(`
      INSERT INTO voice_call_events(session_id, actor_user_id, event_type, event_data)
      VALUES($1, $2, $3, $4::jsonb)
    `, [callId, senderUserId, dto.eventType, JSON.stringify(dto.data)]);

    // Live relay
    await this.live.sendToUser(recipientUserId, 'call.signal', {
      callId,
      eventType: dto.eventType,
      data: dto.data,
      fromUserId: senderUserId,
    });

    return { relayed: true };
  }

  /** Gets call session details (never exposes private phone numbers) and peer WebRTC signals */
  async getCall(userId: string, callId: string) {
    const res = await this.db.query(`
      SELECT s.*,
             u1.display_name AS caller_name, u2.display_name AS receiver_name
      FROM voice_call_sessions s
      JOIN users u1 ON u1.id = s.caller_user_id
      JOIN users u2 ON u2.id = s.receiver_user_id
      WHERE s.id = $1
    `, [callId]);

    if (!res.rowCount) throw new NotFoundException({ code: 'CALL_NOT_FOUND' });
    const call = res.rows[0];

    if (call.caller_user_id !== userId && call.receiver_user_id !== userId) {
      throw new ForbiddenException({ code: 'NOT_CALL_PARTICIPANT' });
    }

    const signalsRes = await this.db.query(`
      SELECT id, actor_user_id, event_type, event_data, created_at
      FROM voice_call_events
      WHERE session_id = $1
        AND actor_user_id <> $2
        AND event_type IN ('SDP_OFFER', 'SDP_ANSWER', 'ICE_CANDIDATE')
      ORDER BY created_at ASC, id ASC
    `, [callId, userId]);

    return {
      ...call,
      signals: signalsRes.rows,
    };
  }
}
