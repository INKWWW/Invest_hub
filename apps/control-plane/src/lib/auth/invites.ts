import { createHash, randomBytes, randomUUID } from "node:crypto";

import { createInviteRecord, consumeInvite } from "../db/repositories/invites";
import { createSupabaseAdminClient } from "../db/supabase-server";
import type { AppRole } from "../db/types";

export type InvitePurpose = "user" | "worker";

export function hashInviteCode(code: string): string {
  return createHash("sha256").update(code, "utf8").digest("hex");
}

export async function createOneTimeInvite(input: {
  purpose: InvitePurpose;
  role: AppRole;
  expiresAt: string;
  createdBy: string;
}) {
  const code = randomBytes(24).toString("base64url");
  const record = await createInviteRecord({
    codeHash: hashInviteCode(code),
    purpose: input.purpose,
    role: input.role,
    expiresAt: input.expiresAt,
    createdBy: input.createdBy,
  });
  return { inviteId: record.id, code, purpose: input.purpose, expiresAt: input.expiresAt };
}

export async function redeemInviteCode(code: string, userId: string, now = new Date().toISOString()) {
  return consumeInvite(hashInviteCode(code), userId, "user", now);
}

export async function consumeWorkerInvite(code: string, workerId = randomUUID(), now = new Date().toISOString()) {
  return consumeInvite(hashInviteCode(code), workerId, "worker", now);
}

export async function redeemInviteAccount(input: { code: string; email: string; password: string }) {
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.auth.admin.createUser({
    email: input.email,
    password: input.password,
    email_confirm: true,
  });
  if (error || !data.user) return { ok: false as const, error: "account_create_failed" as const };

  const invite = await redeemInviteCode(input.code, data.user.id);
  if (!invite) {
    await admin.auth.admin.deleteUser(data.user.id);
    return { ok: false as const, error: "invite_replayed" as const };
  }

  const { error: profileError } = await admin.from("profiles").upsert({
    id: data.user.id,
    role: invite.role,
  });
  if (profileError) return { ok: false as const, error: "profile_create_failed" as const };
  return { ok: true as const, userId: data.user.id, role: invite.role };
}
