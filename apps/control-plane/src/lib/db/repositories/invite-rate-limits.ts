import { createSupabaseAdminClient } from "../supabase-server";

export async function canAttemptInviteRedemption(sourceHash: string, now = new Date().toISOString()): Promise<boolean> {
  const db = createSupabaseAdminClient();
  const { data, error } = await db.rpc("can_attempt_invite_redemption", {
    p_source_hash: sourceHash,
    p_now: now,
  });
  if (error) throw error;
  return data === true;
}

export async function recordFailedInviteRedemption(sourceHash: string, now = new Date().toISOString()): Promise<boolean> {
  const db = createSupabaseAdminClient();
  const { data, error } = await db.rpc("record_failed_invite_redemption", {
    p_source_hash: sourceHash,
    p_now: now,
  });
  if (error) throw error;
  return data === true;
}
