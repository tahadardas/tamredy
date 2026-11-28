import { createHash } from 'node:crypto';

/** One configuration policy consumed by API and worker. No defaults enable optional features. */
export function featureCapabilities(env = process.env) {
  const enabled = key => env[key] === 'true';
  return {
    scheduledVisitsEnabled: enabled('SCHEDULED_VISITS_ENABLED'),
    openMarketplaceEnabled: env.OPEN_MARKETPLACE_ENABLED !== 'false',
    openDispatchEnabled: enabled('OPEN_DISPATCH_ENABLED'),
    liveLocationRedisEnabled: enabled('LIVE_LOCATION_REDIS_ENABLED'),
    locationPostgresFallbackEnabled: env.LOCATION_POSTGRES_FALLBACK_ENABLED === 'true',
    guardianRoutingEnabled: enabled('GUARDIAN_ROUTING_ENABLED'),
    pushEnabled: env.PUSH_ENABLED !== 'false',
    realtimeEnabled: env.REALTIME_ENABLED !== 'false',
    voiceEnabled: env.VOICE_ENABLED !== 'false',
    guardianNightPolicyEnabled: enabled('GUARDIAN_NIGHT_POLICY_ENABLED'),
    walletProviderEnabled: enabled('WALLET_PROVIDER_ENABLED'),
  };
}
export function bookingCapabilityError(mode, features) {
  if (mode === 'SCHEDULED' && !features.scheduledVisitsEnabled) return 'SCHEDULED_VISITS_DISABLED';
  if (mode === 'OPEN' && !features.openMarketplaceEnabled) return 'OPEN_MARKETPLACE_DISABLED';
  return null;
}
export function ordersState(value) {
  if (!value || typeof value.accepting !== 'boolean') return { status: 'unavailable', accepting: false, pausedMessage: null };
  return {status: 'available', accepting: value.accepting, pausedMessage: typeof value.pausedMessage === 'string' ? value.pausedMessage : null};
}

/** Compare only shared non-secret settings consumed by API and worker. */
export function runtimeConfigFingerprint(features = featureCapabilities()) {
  const { walletProviderEnabled, ...shared } = features;
  return createHash('sha256').update(JSON.stringify(shared)).digest('hex');
}
