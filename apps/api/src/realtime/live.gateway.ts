import { ModuleRef } from '@nestjs/core';
import { buildNotificationPayload, type RecipientRole } from '../notifications/notification-routing.js';
import { isPrivateEventEnvelope, validHighFrequencyEvent, type PrivateEventEnvelope } from './private-event.js';
import { HttpException, Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConnectedSocket, MessageBody, OnGatewayConnection, SubscribeMessage, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Namespace, Socket } from 'socket.io';
import { Redis } from 'ioredis';
import jwt, { type JwtPayload } from 'jsonwebtoken';
const { verify } = jwt;
import { requireActiveDeviceSession } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { ReferenceCacheService } from '../cache/reference-cache.service.js';
import { LiveLocationService } from '../live-location/live-location.service.js';
import type { LiveLocationUpdateDto } from '../live-location/location-update.dto.js';
import { OperationalMetricsService } from '../observability/operational-metrics.service.js';

@WebSocketGateway({namespace:'/live', cors:{origin:(process.env.ALLOWED_ORIGINS??'http://localhost:5173').split(',')}})
@Injectable()
export class LiveGateway implements OnModuleInit, OnModuleDestroy, OnGatewayConnection {
  @WebSocketServer() io!:Namespace;
  private subscriber?:Redis;
  private publisher?:Redis;
  constructor(
    private readonly db:DbService,
    private readonly cache:ReferenceCacheService,
    private readonly liveLocation:LiveLocationService,
    private readonly metrics:OperationalMetricsService,
    private readonly moduleRef:ModuleRef,
  ){}
  async onModuleInit() {
    if(!process.env.REDIS_URL)return;
    this.subscriber=new Redis(process.env.REDIS_URL);
    this.publisher=new Redis(process.env.REDIS_URL, {enableOfflineQueue:false,maxRetriesPerRequest:1,commandTimeout:1500});
    await this.subscriber.subscribe('tamreedy:events');
    this.subscriber.on('message',(_channel,data)=>{
      try {
        const evt=JSON.parse(data) as {eventId?:string;type:string;payload:{eventId?:string;recipientUserId?:string;recipientUserIds?:string[];recipientRole?:string;requestId?:string;namespace?:string}};
        // Retryable outbox invalidation is received on all API replicas.
        if(evt.type==='cache.invalidate' && evt.payload.namespace==='services:public') {
          // Catalogue/prices changed: every connected app reloads its service list (REST stays the source of truth).
          void this.cache.invalidate('services:public');this.io?.emit('catalog.changed',{});return;
        }
        const users=[...(evt.payload.recipientUserIds??[]),...(evt.payload.recipientUserId?[evt.payload.recipientUserId]:[])];
        const resolvedEventId = evt.payload.eventId ?? evt.eventId;
        // Never rely on a client-selected room or broadcast private patient data publicly.
        for (const userId of new Set(users)) {
          void this.sendToUserLocal(userId,evt.type,{...evt.payload, ...(resolvedEventId ? { eventId: resolvedEventId } : {})}).catch(() => this.metrics.increment('private_event_delivery_failures_total'));
        }
      }catch { this.metrics.increment('realtime_malformed_messages_total'); }
    });
  }
  async handleConnection(client:Socket) {
    try {
      const token=client.handshake.auth?.token;
      if(typeof token!=='string'||!process.env.JWT_SECRET||process.env.JWT_SECRET.length<32)throw Error('auth');
      const payload=verify(token,process.env.JWT_SECRET,{algorithms:['HS256'],issuer:process.env.JWT_ISSUER??'tamreedy-api',audience:process.env.JWT_AUDIENCE??'tamreedy-mobile'});
      if(typeof payload==='string'||typeof payload.sub!=='string')throw Error('auth');
      const access=await this.assertSocketAccess(payload);
      client.data.auth = payload;
      client.data.role = access.role;
      client.data.appType = client.handshake.auth?.appType;
      await client.join(`user:${payload.sub}`);
      client.emit('connected',{resyncRequired:true});
    }catch { client.disconnect(true); }
  }
  private async assertSocketAccess(payload: JwtPayload): Promise<{role:string}> {
    if (!payload.sub || !payload.exp || payload.exp <= Date.now() / 1000) throw Error('auth');
    const result = await this.db.query(
      `SELECT auth_version,role FROM users WHERE id=$1 AND status='ACTIVE' AND NOT must_change_password`,
      [payload.sub],
    );
    if (!result.rowCount || (payload.av ?? null) !== (result.rows[0].auth_version ?? null)) {
      throw Error('inactive');
    }
    await requireActiveDeviceSession(this.db, payload.sub, payload.dsi, payload.sgen);
    return {role:result.rows[0].role};
  }
  private async sendToUserLocal(userId: string, type: string, payload: Record<string, unknown>) {
    const recipient = await this.db.query("SELECT role FROM users WHERE id=$1 AND status='ACTIVE'", [userId]);
    if (!recipient.rowCount) return;
    const envelope = buildNotificationPayload({
      eventId: typeof payload.eventId === 'string' ? payload.eventId : undefined,
      eventType:type, recipientUserId:userId, recipientRole:recipient.rows[0].role as RecipientRole,
      requestId:typeof payload.requestId === 'string' ? payload.requestId : null,
      callId:typeof payload.callId === 'string' ? payload.callId : null,
      createdAt:typeof payload.createdAt === 'string' ? payload.createdAt : null,
      expiresAt:typeof payload.expiresAt === 'string' ? payload.expiresAt : null,
      assignmentId: typeof payload.assignmentId === 'string' ? payload.assignmentId : null,
      offerId: typeof payload.offerId === 'string' ? payload.offerId : null,
      proposalId: typeof payload.proposalId === 'string' ? payload.proposalId : null,
      conversationId: typeof payload.conversationId === 'string' ? payload.conversationId : null,
      entityVersion: typeof payload.entityVersion === 'number' ? payload.entityVersion : null,
      extra:payload,
    });
    await this.deliverPrivateEvent(userId,type,envelope);
  }

  async sendToUser(userId: string, type: string, payload: unknown) {
    const obj = payload && typeof payload === 'object' ? payload as Record<string, unknown> : {};
    const recipient = await this.db.query("SELECT role FROM users WHERE id=$1 AND status='ACTIVE'", [userId]);
    if (!recipient.rowCount) return;
    const enriched = buildNotificationPayload({
      eventId: typeof obj.eventId === 'string' ? obj.eventId : undefined,
      eventType: type, recipientUserId: userId, recipientRole: recipient.rows[0].role as RecipientRole,
      requestId: typeof obj.requestId === 'string' ? obj.requestId : null,
      callId: typeof obj.callId === 'string' ? obj.callId : null,
      assignmentId: typeof obj.assignmentId === 'string' ? obj.assignmentId : null,
      offerId: typeof obj.offerId === 'string' ? obj.offerId : null,
      proposalId: typeof obj.proposalId === 'string' ? obj.proposalId : null,
      conversationId: typeof obj.conversationId === 'string' ? obj.conversationId : null,
      entityVersion: typeof obj.entityVersion === 'number' ? obj.entityVersion : null,
      extra: obj,
      expiresAt: typeof obj.expiresAt === 'string' ? obj.expiresAt : null,
    });
    if (!isPrivateEventEnvelope(enriched, userId, type)) throw Error('PRIVATE_EVENT_CONTRACT_INVALID');
    if (this.publisher) {
      try {
        await this.publisher.publish('tamreedy:events',JSON.stringify({eventId:enriched.eventId,type,payload:enriched}));
        return;
      } catch {
        this.metrics.increment('realtime_publish_failures_total');
      }
    }
    await this.deliverPrivateEvent(userId,type,enriched);
  }

  @SubscribeMessage('call.signal')
  async callSignal(@ConnectedSocket() client:Socket, @MessageBody() body: Record<string, unknown>) {
    try {
      const auth = client.data.auth as JwtPayload;
      await this.assertSocketAccess(auth);
      if (!body || typeof body.callId !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.callId)) {
        return {code:'INVALID_CALL_SIGNAL'};
      }
      // Resolve lazily: VoiceService already depends on this gateway.
      const { VoiceService } = await import('../voice/voice.service.js');
      const voice = this.moduleRef.get(VoiceService, {strict:false});
      return await voice.relaySignal(auth.sub!, body.callId, body as unknown as import('../voice/voice.service.js').CallSignalDto);
    } catch(error) {
      this.metrics.increment('voice_signal_rejections_total');
      return error instanceof HttpException ? error.getResponse() : {code:'CALL_SIGNAL_FAILED'};
    }
  }

  @SubscribeMessage('location.update')
  async locationUpdate(@ConnectedSocket() client:Socket,@MessageBody() dto:LiveLocationUpdateDto) {
    const auth=client.data.auth as JwtPayload|undefined;
    const now=Date.now();
    const rate=client.data.locationRate as {startedAt:number;count:number}|undefined;
    if(!rate||now-rate.startedAt>=10_000) client.data.locationRate={startedAt:now,count:1};
    else if(++rate.count>30) {
      const rejected={code:'LOCATION_RATE_LIMITED'};client.emit('location.rejected',rejected);return rejected;
    }
    if(client.data.role!=='NURSE'||typeof auth?.sub!=='string'||typeof auth.dsi!=='string') {
      const rejected={code:'LOCATION_NOT_AUTHORIZED'};client.emit('location.rejected',rejected);return rejected;
    }
    try {
      const result=await this.liveLocation.ingest(auth.sub,auth.dsi,dto);
      const ack={receivedAt:result.receivedAt,sequenceNumber:result.sequenceNumber};
      client.emit('location.ack',ack);
      if(result.tracking) {
        await this.sendToUser(result.tracking.patientUserId,'tracking.updated',{
          requestId:result.tracking.requestId,assignmentId:result.tracking.assignmentId,
          latitude:dto.latitude,longitude:dto.longitude,accuracyMeters:dto.accuracyMeters,
          capturedAt:dto.capturedAt,sequenceNumber:dto.sequenceNumber,
          recipientRole:'PATIENT',targetApp:'PATIENT_APP',
        });
      }
      return ack;
    } catch(error) {
      this.metrics.increment('location_rejections_total');
      const response=error instanceof HttpException?error.getResponse():{code:'LOCATION_UPDATE_FAILED'};
      const rejected=typeof response==='string'?{code:response}:response;
      client.emit('location.rejected',rejected);return rejected;
    }
  }

  private async deliverPrivateEvent(userId: string, type: string, payload: unknown) {
    const users = this.io?.sockets;
    const recipients = this.io?.adapter.rooms.get(`user:${userId}`);
    if (!users || !recipients) return;
    if (!isPrivateEventEnvelope(payload, userId, type) || !validHighFrequencyEvent(payload)) {
      this.metrics.increment('private_event_contract_rejections_total');
      return;
    }
    if (typeof payload.expiresAt === 'string' && Date.parse(payload.expiresAt) <= Date.now()) return;
    for (const socketId of [...recipients]) {
      const socket = users.get(socketId);
      if (!socket) continue;
      if (socket.data.role !== payload.recipientRole ||
          (socket.data.appType && socket.data.appType !== payload.targetApp)) {
        continue;
      }
      try {
        const access = await this.assertSocketAccess(socket.data.auth);
        if (access.role !== payload.recipientRole) continue;
        if (!await this.canAccessEntity(userId, type, payload)) continue;
        socket.emit(type, payload);
      } catch {
        socket.disconnect(true);
      }
    }
  }
  private async canAccessEntity(userId: string, type: string, payload: PrivateEventEnvelope): Promise<boolean> {
    if (typeof payload.callId === 'string') {
      const call = await this.db.query('SELECT 1 FROM voice_call_sessions WHERE id=$1 AND $2 IN (caller_user_id,receiver_user_id)', [payload.callId,userId]);
      return !!call.rowCount;
    }
    if (typeof payload.conversationId === 'string') {
      const member = await this.db.query('SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2',[payload.conversationId,userId]);
      return !!member.rowCount;
    }
    if (typeof payload.requestId !== 'string') return true;
    // Published marketplace notices only identify a browsable request; protected
    // clinical and financial contents always require participant access.
    const publicListing = ['marketplace.request.published','marketplace.request.updated','marketplace.recovery.alert'].includes(type);
    const result = await this.db.query(`SELECT 1 FROM care_requests r WHERE r.id=$1 AND (
      r.requester_user_id=$2 OR EXISTS(SELECT 1 FROM request_assignments a JOIN nurses n ON n.id=a.nurse_id WHERE a.request_id=r.id AND n.user_id=$2)
      OR ($4::boolean AND EXISTS(SELECT 1 FROM request_offers o JOIN nurses n ON n.id=o.nurse_id WHERE o.request_id=r.id AND n.user_id=$2))
      OR ($5::boolean AND EXISTS(SELECT 1 FROM marketplace_proposals p JOIN nurses n ON n.id=p.nurse_id WHERE p.request_id=r.id AND n.user_id=$2))
      OR ($3::boolean AND EXISTS(SELECT 1 FROM nurses n WHERE n.user_id=$2)))`, [payload.requestId,userId,publicListing,type.startsWith('offer.'),type.startsWith('marketplace.')]);
    return !!result.rowCount;
  }
  async onModuleDestroy() { await Promise.all([this.subscriber?.quit(),this.publisher?.quit()]); }
}
