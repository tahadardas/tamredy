import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import { featureCapabilities, bookingCapabilityError, ordersState } from '../../../../packages/backend-policy/capabilities.mjs';

@Injectable()
export class FeatureCapabilitiesService {
  constructor(private readonly db: DbService) {}

  async snapshot() {
    let orders = ordersState(null);
    try {
      orders = ordersState((await this.db.query("SELECT value FROM app_settings WHERE key='orders'")).rows[0]?.value);
    } catch {
      console.error(JSON.stringify({event:'capabilities.unavailable', code:'ORDERS_SETTINGS_UNAVAILABLE'}));
    }
    const features = featureCapabilities();
    return {...features, ordersAccepting: orders.accepting, ordersStatus: orders.status,
      pausedMessage: orders.pausedMessage, serverTime: new Date().toISOString(),
      features: Object.fromEntries(Object.entries(features).map(([key, enabled]) => [key, {
        configured: key === 'liveLocationRedisEnabled' ? Boolean(process.env.REDIS_URL) : enabled,
        enabled, operational: enabled ? null : false,
      }]))};
  }

  assertBookingMode(mode: string): void {
    const code = bookingCapabilityError(mode, featureCapabilities());
    if (code) throw new ServiceUnavailableException({code});
  }

  async assertAccepting(client: PoolClient): Promise<void> {
    const orders = ordersState((await client.query("SELECT value FROM app_settings WHERE key='orders'")).rows[0]?.value);
    if (orders.status !== 'available') throw new ServiceUnavailableException({code:'ORDERS_SETTINGS_UNAVAILABLE'});
    if (!orders.accepting) throw new ServiceUnavailableException({code:'ORDERS_PAUSED', message:orders.pausedMessage});
  }
}
