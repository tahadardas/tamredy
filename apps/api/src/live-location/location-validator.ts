import { BadRequestException, Injectable } from '@nestjs/common';
import type { LiveLocationUpdateDto } from './location-update.dto.js';

export interface PreviousLocation {
  latitude: number;
  longitude: number;
  capturedAt: Date;
  sequenceNumber: number;
  sessionId: string;
}

@Injectable()
export class LocationValidator {
  private readonly maxAgeMs = Number(process.env.LOCATION_MAX_AGE_SECONDS ?? 120) * 1000;
  private readonly maxFutureMs = Number(process.env.LOCATION_MAX_FUTURE_SECONDS ?? 30) * 1000;
  private readonly maxAccuracyMeters = Number(process.env.LOCATION_MAX_ACCURACY_METERS ?? 150);
  private readonly maxPlausibleSpeed = Number(process.env.LOCATION_MAX_SPEED_MPS ?? 70);

  validate(dto: LiveLocationUpdateDto, expectedSessionId: string, previous?: PreviousLocation | null): Date {
    if (dto.sessionId !== expectedSessionId) this.reject('DEVICE_SESSION_MISMATCH');
    const capturedAt = new Date(dto.capturedAt);
    if (!Number.isFinite(capturedAt.getTime())) this.reject('INVALID_CAPTURE_TIME');
    const age = Date.now() - capturedAt.getTime();
    if (age > this.maxAgeMs) this.reject('LOCATION_STALE', { ageSeconds: Math.floor(age / 1000) });
    if (age < -this.maxFutureMs) this.reject('LOCATION_FROM_FUTURE');
    if (dto.accuracyMeters > this.maxAccuracyMeters) {
      this.reject('LOCATION_ACCURACY_TOO_LOW', { maximumAccuracyMeters: this.maxAccuracyMeters });
    }
    if (!previous) return capturedAt;
    if (previous.sessionId === dto.sessionId && dto.sequenceNumber <= previous.sequenceNumber) {
      this.reject(dto.sequenceNumber === previous.sequenceNumber ? 'LOCATION_DUPLICATE' : 'LOCATION_OUT_OF_ORDER');
    }
    if (capturedAt <= previous.capturedAt) this.reject('LOCATION_OUT_OF_ORDER');
    const elapsedSeconds = (capturedAt.getTime() - previous.capturedAt.getTime()) / 1000;
    if (elapsedSeconds > 0) {
      const impliedSpeed = this.distanceMeters(previous.latitude, previous.longitude, dto.latitude, dto.longitude) / elapsedSeconds;
      if (impliedSpeed > this.maxPlausibleSpeed) {
        this.reject('LOCATION_IMPLAUSIBLE_JUMP', { impliedSpeedMetersPerSecond: Math.round(impliedSpeed) });
      }
    }
    return capturedAt;
  }

  private reject(code: string, details?: Record<string, unknown>): never {
    throw new BadRequestException({ code, ...details });
  }

  private distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const radians = (value: number) => value * Math.PI / 180;
    const dLat = radians(lat2 - lat1);
    const dLon = radians(lon2 - lon1);
    const a = Math.sin(dLat / 2) ** 2
      + Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
    return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
}

