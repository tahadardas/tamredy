import { randomUUID } from 'node:crypto';
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
          void this.deliverPrivateEvent(userId,evt.type,{...evt.payload, ...(resolvedEventId ? { eventId: resolvedEventId } : {})});
        }
      }catch { /* malformed worker message ignored and logged upstream */ }
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
  async sendToUser(userId: string, type: string, payload: unknown) {
    const obj = (payload && typeof payload === 'object') ? (payload as Record<string, unknown>) : {};
    const eventId = typeof obj.eventId === 'string' && obj.eventId ? obj.eventId : randomUUID();
    const enriched = { ...obj, eventId, recipientUserId: userId };
    if (this.publisher) {
      try {
        await this.publisher.publish('tamreedy:events',JSON.stringify({
          eventId, type, payload: enriched,
        }));
        return;
      } catch {
        // Local delivery remains available; durable outbox and REST reconcile
        // events for clients connected to another replica.
      }
    }
    await this.deliverPrivateEvent(userId,type,enriched);
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
    const targetRole = (payload && typeof payload === 'object' && 'recipientRole' in payload)
      ? (payload as { recipientRole?: unknown }).recipientRole
      : undefined;
    for (const socketId of [...recipients]) {
      const socket = users.get(socketId);
      if (!socket) continue;
      if (typeof targetRole === 'string' && socket.data.role && socket.data.role !== targetRole) {
        continue;
      }
      try {
        await this.assertSocketAccess(socket.data.auth);
        socket.emit(type, payload);
      } catch {
        socket.disconnect(true);
      }
    }
  }
  async onModuleDestroy() { await Promise.all([this.subscriber?.quit(),this.publisher?.quit()]); }
}
