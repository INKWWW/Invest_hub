import { createSupabaseAdminClient } from "../supabase-server";
import type { AppRole, Database } from "../types";

type InviteInsert = Database["public"]["Tables"]["invites"]["Insert"];

export async function createInviteRecord(input: {
  codeHash: string;
  role: AppRole;
  purpose?: "user" | "worker";
  expiresAt: string;
  createdBy: string;
}) {
  const db = createSupabaseAdminClient();
  const row: InviteInsert = {
    code_hash: input.codeHash,
    role: input.role,
    purpose: input.purpose ?? "user",
    expires_at: input.expiresAt,
    created_by: input.createdBy,
  };
  const { data, error } = await db.from("invites").insert(row).select().single();
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
