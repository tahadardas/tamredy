export interface FeatureCapabilities {
  scheduledVisitsEnabled: boolean; openMarketplaceEnabled: boolean; openDispatchEnabled: boolean;
  liveLocationRedisEnabled: boolean; guardianNightPolicyEnabled: boolean; walletProviderEnabled: boolean;
}
export function featureCapabilities(env?: Record<string,string|undefined>): FeatureCapabilities;
export function bookingCapabilityError(mode: string, features: FeatureCapabilities): string|null;
export function ordersState(value: unknown): {status: string; accepting: boolean; pausedMessage: string|null};
