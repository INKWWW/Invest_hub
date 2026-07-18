export const HEARTBEAT_INTERVAL_SECONDS = 60;
export const LEASE_DURATION_SECONDS = 10 * 60;
export const LEASE_RENEWAL_THRESHOLD_SECONDS = 2 * 60;

export function heartbeatDeadline(now = new Date()): string {
  return new Date(now.getTime() + HEARTBEAT_INTERVAL_SECONDS * 1000).toISOString();
}

export function leaseDeadline(now = new Date()): string {
  return new Date(now.getTime() + LEASE_DURATION_SECONDS * 1000).toISOString();
}

export function leaseIsExpired(leaseExpiresAt: string | null, now = new Date()): boolean {
  return !leaseExpiresAt || new Date(leaseExpiresAt).getTime() <= now.getTime();
}

export function shouldRenewLease(leaseExpiresAt: string | null, now = new Date()): boolean {
  if (leaseIsExpired(leaseExpiresAt, now)) return false;
  return new Date(leaseExpiresAt!).getTime() - now.getTime() <= LEASE_RENEWAL_THRESHOLD_SECONDS * 1000;
}
