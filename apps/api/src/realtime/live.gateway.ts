import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { WebSocketGateway, WebSocketServer, OnGatewayConnection } from '@nestjs/websockets';
import { Namespace, Socket } from 'socket.io';
import { Redis } from 'ioredis';
import jwt, { type JwtPayload } from 'jsonwebtoken';
const { verify } = jwt;
import { requireActiveDeviceSession } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { ReferenceCacheService } from '../cache/reference-cache.service.js';

@WebSocketGateway({namespace:'/live', cors:{origin:(process.env.ALLOWED_ORIGINS??'http://localhost:5173').split(',')}})
@Injectable()
export class LiveGateway implements OnModuleInit, OnModuleDestroy, OnGatewayConnection {
  @WebSocketServer() io!:Namespace;
  private subscriber?:Redis;
  constructor(private readonly db:DbService,private readonly cache:ReferenceCacheService){}
  async onModuleInit() {
    if(!process.env.REDIS_URL)return;
    this.subscriber=new Redis(process.env.REDIS_URL);
    await this.subscriber.subscribe('tamreedy:events');
    this.subscriber.on('message',(_channel,data)=>{
      try {
        const evt=JSON.parse(data) as {type:string;payload:{recipientUserId?:string;recipientUserIds?:string[];requestId?:string;namespace?:string}};
        // Retryable outbox invalidation is received on all API replicas.
        if(evt.type==='cache.invalidate' && evt.payload.namespace==='services:public') {
          // Catalogue/prices changed: every connected app reloads its service list (REST stays the source of truth).
          void this.cache.invalidate('services:public');this.io?.emit('catalog.changed',{});return;
        }
        const users=[...(evt.payload.recipientUserIds??[]),...(evt.payload.recipientUserId?[evt.payload.recipientUserId]:[])];
        // Never rely on a client-selected room or broadcast private patient data publicly.
        for (const userId of new Set(users)) void this.deliverPrivateEvent(userId, evt.type, evt.payload);
      }catch { /* malformed worker message ignored and logged upstream */ }
    });
  }
  async handleConnection(client:Socket) {
    try {
      const token=client.handshake.auth?.token;
      if(typeof token!=='string'||!process.env.JWT_SECRET||process.env.JWT_SECRET.length<32)throw Error('auth');
      const payload=verify(token,process.env.JWT_SECRET,{algorithms:['HS256'],issuer:process.env.JWT_ISSUER??'tamreedy-api',audience:process.env.JWT_AUDIENCE??'tamreedy-mobile'});
      if(typeof payload==='string'||typeof payload.sub!=='string')throw Error('auth');
      await this.assertSocketAccess(payload);
      client.data.auth = payload;
      await client.join(`user:${payload.sub}`);
      client.emit('connected',{resyncRequired:true});
    }catch { client.disconnect(true); }
  }
  private async assertSocketAccess(payload: JwtPayload) {
    if (!payload.sub || !payload.exp || payload.exp <= Date.now() / 1000) throw Error('auth');
    const result = await this.db.query(
      `SELECT auth_version FROM users WHERE id=$1 AND status='ACTIVE' AND NOT must_change_password`,
      [payload.sub],
    );
    if (!result.rowCount || (payload.av ?? null) !== (result.rows[0].auth_version ?? null)) {
      throw Error('inactive');
    }
    await requireActiveDeviceSession(this.db, payload.sub, payload.dsi);
  }
  async sendToUser(userId: string, type: string, payload: unknown) {
    await this.deliverPrivateEvent(userId, type, payload);
  }

  private async deliverPrivateEvent(userId: string, type: string, payload: unknown) {
    const users = this.io?.sockets;
    const recipients = this.io?.adapter.rooms.get(`user:${userId}`);
    if (!users || !recipients) return;
    for (const socketId of [...recipients]) {
      const socket = users.get(socketId);
      if (!socket) continue;
      try {
        await this.assertSocketAccess(socket.data.auth);
        socket.emit(type, payload);
      } catch {
        socket.disconnect(true);
      }
    }
  }
  async onModuleDestroy() { await this.subscriber?.quit(); }
}
