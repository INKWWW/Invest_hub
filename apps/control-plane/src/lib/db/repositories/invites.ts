import { createSupabaseAdminClient } from "../supabase-server";
import type { AppRole, Database } from "../types";

type InviteInsert = Database["public"]["Tables"]["invites"]["Insert"];

export async function createInviteRecord(input: {
  codeHash: string;
  role: AppRole;
  purpose?: "user" | "worker";
  expiresAt: string;
  createdBy: string;
  codeMask?: string;
  validityHours?: number;
  createdAt?: string;
}) {
  const db = createSupabaseAdminClient();
  const row: InviteInsert = {
    code_hash: input.codeHash,
    role: input.role,
    purpose: input.purpose ?? "user",
    expires_at: input.expiresAt,
    created_by: input.createdBy,
    ...(input.codeMask === undefined ? {} : { code_mask: input.codeMask }),
    ...(input.validityHours === undefined ? {} : { validity_hours: input.validityHours }),
    ...(input.createdAt === undefined ? {} : { created_at: input.createdAt }),
  };
  const { data, error } = await db.from("invites").insert(row).select().single();
  if (error) throw error;
  return data;
}

export async function listRecentUserInviteRecords(limit = 20) {
  const db = createSupabaseAdminClient();
  const { data, error } = await db
    .from("invites")
    .select("code_mask, validity_hours, created_at, expires_at, consumed_at")
    .eq("purpose", "user")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data;
}

export async function consumeInvite(
  codeHash: string,
  userId: string,
  purpose: "user" | "worker" = "user",
  now = new Date().toISOString(),
) {
  const db = createSupabaseAdminClient();
  const args = purpose === "user"
    ? { p_code_hash: codeHash, p_user_id: userId, p_now: now }
    : { p_code_hash: codeHash, p_purpose: purpose, p_user_id: userId, p_now: now };
  const { data, error } = await db.rpc("consume_invite", args);
  if (error) throw error;
  return data as { invite_id: string; role: AppRole; purpose: "user" | "worker"; expires_at: string } | null;
}
