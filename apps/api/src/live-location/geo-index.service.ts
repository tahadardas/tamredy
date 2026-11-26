import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Redis } from 'ioredis';
import type { LiveLocationUpdateDto } from './location-update.dto.js';
import type { PreviousLocation } from './location-validator.js';

export interface RedisDetailedLocation {
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  recordedAt: Date;
  capturedAt: Date;
  sequenceNumber: number;
  source: 'redis';
}

const UPDATE_SCRIPT = `
local hash = KEYS[1]
local geo = KEYS[2]
local expiry = KEYS[3]
local previousSequence = tonumber(redis.call('HGET', hash, 'sequenceNumber') or '-1')
local previousCaptured = tonumber(redis.call('HGET', hash, 'capturedAtEpochMs') or '-1')
local incomingSequence = tonumber(ARGV[4])
local incomingCaptured = tonumber(ARGV[3])
local expired = redis.call('ZRANGEBYSCORE', expiry, '-inf', ARGV[7], 'LIMIT', 0, 100)
for _, member in ipairs(expired) do
  redis.call('ZREM', expiry, member)
  redis.call('ZREM', geo, member)
end
if previousSequence >= incomingSequence or previousCaptured >= incomingCaptured then return 0 end
redis.call('HSET', hash,
  'latitude', ARGV[1], 'longitude', ARGV[2], 'capturedAtEpochMs', ARGV[3],
  'sequenceNumber', ARGV[4], 'sessionId', ARGV[5], 'accuracyMeters', ARGV[6],
  'receivedAtEpochMs', ARGV[7], 'locationSource', ARGV[8],
  'speedMetersPerSecond', ARGV[9], 'heading', ARGV[10], 'assignmentId', ARGV[11])
redis.call('PEXPIRE', hash, ARGV[12])
redis.call('GEOADD', geo, ARGV[2], ARGV[1], ARGV[13])
redis.call('ZADD', expiry, ARGV[14], ARGV[13])
return 1`;

@Injectable()
export class GeoIndexService implements OnModuleDestroy {
  private readonly redis: Redis | null;
  private readonly enabled = process.env.LIVE_LOCATION_REDIS_ENABLED === 'true';
  private readonly ttlMs = Number(process.env.LIVE_LOCATION_TTL_SECONDS ?? 150) * 1000;

  constructor() {
    this.redis = this.enabled && process.env.REDIS_URL
      ? new Redis(process.env.REDIS_URL, {
          enableOfflineQueue: false,
          maxRetriesPerRequest: 1,
          commandTimeout: 1500,
        })
      : null;
  }

  get active(): boolean { return this.redis !== null; }

  async assertReady(): Promise<void> {
    if (!this.redis) return;
    try {
      await this.redis.ping();
    } catch (error) {
      if (process.env.LOCATION_POSTGRES_FALLBACK_ENABLED === 'false') throw error;
    }
  }

  async healthStatus(): Promise<{ enabled: boolean; connected: boolean }> {
    if (!this.redis) return { enabled: this.enabled, connected: false };
    try {
      await this.redis.ping();
      return { enabled: true, connected: true };
    } catch {
      return { enabled: true, connected: false };
    }
  }

  async current(nurseId: string): Promise<PreviousLocation | null> {
    if (!this.redis) return null;
    const value = await this.redis.hgetall(`live:location:${nurseId}`);
    if (!value.capturedAtEpochMs || !value.latitude || !value.longitude ||
        !value.sequenceNumber || !value.sessionId) return null;
    return {
      latitude: Number(value.latitude),
      longitude: Number(value.longitude),
      capturedAt: new Date(Number(value.capturedAtEpochMs)),
      sequenceNumber: Number(value.sequenceNumber),
      sessionId: value.sessionId,
    };
  }

  async currentDetailed(nurseId: string): Promise<RedisDetailedLocation | null> {
    if (!this.redis) return null;
    const value = await this.redis.hgetall(`live:location:${nurseId}`);
    if (!value.capturedAtEpochMs || !value.latitude || !value.longitude || !value.sequenceNumber) {
      return null;
    }
    const capturedAt = new Date(Number(value.capturedAtEpochMs));
    return {
      latitude: Number(value.latitude),
      longitude: Number(value.longitude),
      accuracyMeters: Number(value.accuracyMeters ?? 9999),
      recordedAt: capturedAt,
      capturedAt,
      sequenceNumber: Number(value.sequenceNumber),
      source: 'redis',
    };
  }

  async update(nurseId: string, dto: LiveLocationUpdateDto, capturedAt: Date, receivedAt: Date): Promise<boolean> {
    if (!this.redis) return false;
    const result = await this.redis.eval(
      UPDATE_SCRIPT,
      3,
      `live:location:${nurseId}`,
      'live:geo:nurses',
      'live:geo:expiry',
      dto.latitude,
      dto.longitude,
      capturedAt.getTime(),
      dto.sequenceNumber,
      dto.sessionId,
      dto.accuracyMeters,
      receivedAt.getTime(),
      dto.locationSource,
      dto.speedMetersPerSecond ?? '',
      dto.heading ?? '',
      dto.assignmentId ?? '',
      this.ttlMs,
      nurseId,
      receivedAt.getTime() + this.ttlMs,
    );
    return Number(result) === 1;
  }

  async claimPersistenceWindow(nurseId: string): Promise<boolean> {
    if (!this.redis) return true;
    const seconds = Number(process.env.LOCATION_POSTGRES_CHECKPOINT_SECONDS ?? 30);
    return (await this.redis.set(`live:persist:${nurseId}`, '1', 'EX', seconds, 'NX')) === 'OK';
  }

  async onModuleDestroy(): Promise<void> { await this.redis?.quit(); }
}

