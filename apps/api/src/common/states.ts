export type RequestState = 'OFFERING'|'ASSIGNED'|'EN_ROUTE'|'ARRIVED'|'IN_SERVICE'|'COMPLETED'|'CANCELLED'|'UNFULFILLED'|'ESCALATED';
export const transitions: Readonly<Record<string,readonly string[]>> = {
  OFFERING: ['ASSIGNED','CANCELLED','UNFULFILLED'],
  ASSIGNED: ['EN_ROUTE','CANCELLED','OFFERING'],
  EN_ROUTE: ['ARRIVED','CANCELLED','ESCALATED'],
  ARRIVED: ['IN_SERVICE','ESCALATED'],
  IN_SERVICE: ['COMPLETED','ESCALATED'],
  COMPLETED: [], CANCELLED: [], UNFULFILLED: [], ESCALATED: [],
};
export function canTransition(from: string,to: string): boolean {
  return (transitions[from] ?? []).includes(to);
}
export function nextWave(current: number): { radiusMeters: number; seconds: number } | null {
  return [{radiusMeters:3000,seconds:15},{radiusMeters:6000,seconds:15},{radiusMeters:10000,seconds:20}][current-1] ?? null;
}
export function calculateChange(price: bigint, received: bigint): bigint {
  if (price < 0n || received < 0n || received < price) throw new Error('INVALID_CASH_COLLECTION');
  return received-price;
}
