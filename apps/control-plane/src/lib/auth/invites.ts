import { randomBytes, randomUUID } from "node:crypto";

import {
  generateUserInviteCode,
  hashLegacyInviteCode,
  hashUserInviteCode,
} from "./invite-code";
import { canAttemptInviteRedemption, recordFailedInviteRedemption } from "../db/repositories/invite-rate-limits";
import {
  completeInvitedUserRegistration,
  consumeInvite,
  createInviteRecord,
  listRecentUserInviteRecords,
} from "../db/repositories/invites";
import { createSupabaseAdminClient } from "../db/supabase-server";
import type { AppRole } from "../db/types";

export type InvitePurpose = "user" | "worker";

export function hashInviteCode(code: string): string {
  return hashLegacyInviteCode(code);
}

type BaseInviteInput = { role: AppRole; createdBy: string };

export async function createOneTimeUserInvite(input: BaseInviteInput & {
  expiresInHours: number;
  now?: string;
}) {
  const createdAt = input.now ?? new Date().toISOString();
  const expiresAt = new Date(Date.parse(createdAt) + input.expiresInHours * 60 * 60 * 1000).toISOString();

  for (let attempt = 0; attempt < 3; attempt += 1) {
    const generated = generateUserInviteCode();
    try {
      const record = await createInviteRecord({
        codeHash: hashUserInviteCode(generated.code),
        codeMask: generated.mask,
        purpose: "user",
        role: input.role,
        expiresAt,
        validityHours: input.expiresInHours,
        createdAt,
        createdBy: input.createdBy,
      });
      return {
        inviteId: record.id,
        code: generated.code,
        purpose: "user" as const,
        expiresAt,
        validityHours: input.expiresInHours,
        codeMask: generated.mask,
      };
    } catch (error) {
      const code = error && typeof error === "object" && "code" in error ? (error as { code?: string }).code : null;
      if (code !== "23505" || attempt === 2) throw error;
    }
  }

  throw new Error("invite generation exhausted");
}

export async function createOneTimeWorkerInvite(input: BaseInviteInput & { expiresAt: string }) {
  const code = randomBytes(24).toString("base64url");
  const record = await createInviteRecord({
    codeHash: hashLegacyInviteCode(code),
    purpose: "worker",
    role: input.role,
    expiresAt: input.expiresAt,
    createdBy: input.createdBy,
  });
  return { inviteId: record.id, code, purpose: "worker" as const, expiresAt: input.expiresAt };
}

/**
 * Kept as a compatibility wrapper for callers that still provide a purpose.
 * New routes use the explicit user/Worker functions above.
 */
export async function createOneTimeInvite(input: BaseInviteInput & {
  purpose: InvitePurpose;
  expiresAt: string;
  expiresInHours?: number;
  now?: string;
}) {
  if (input.purpose === "worker") return createOneTimeWorkerInvite(input);
  return createOneTimeUserInvite({
    role: input.role,
    createdBy: input.createdBy,
    expiresInHours: input.expiresInHours ?? 24,
    now: input.now ?? new Date(Date.parse(input.expiresAt) - 24 * 60 * 60 * 1000).toISOString(),
  });
}

export async function redeemInviteCode(code: string, userId: string, now = new Date().toISOString()) {
  const newHash = await consumeInvite(hashUserInviteCode(code), userId, "user", now);
  if (newHash) return newHash;
  return consumeInvite(hashLegacyInviteCode(code), userId, "user", now);
}

export async function consumeWorkerInvite(code: string, workerId = randomUUID(), now = new Date().toISOString()) {
  return consumeInvite(hashLegacyInviteCode(code), workerId, "worker", now);
}

export async function listRecentUserInvites(limit = 20) {
  const rows = await listRecentUserInviteRecords(limit);
  return rows.map((row) => ({
    codeMask: row.code_mask,
    validityHours: row.validity_hours,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    consumedAt: row.consumed_at,
  }));
}

export async function redeemInviteAccount(input: {
  code: string;
  email: string;
  password: string;
  sourceHash?: string;
}) {
  const sourceHash = input.sourceHash ?? "unknown";
  if (!await canAttemptInviteRedemption(sourceHash)) {
    return { ok: false as const, error: "invite_replayed" as const };
  }

  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.auth.admin.createUser({
    email: input.email,
    password: input.password,
    email_confirm: true,
  });
  if (error || !data.user) return { ok: false as const, error: "account_create_failed" as const };

  const cleanup = async () => {
    try {
      const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
      return !deleteError;
    } catch {
      return false;
    }
  };
  const recordFailedAttempt = async () => {
    try {
      await recordFailedInviteRedemption(sourceHash);
    } catch {
      // A failed-attempt record must never turn a safe registration failure into
      // an unsafe response or expose an internal database error.
    }
  };

  let invite: Awaited<ReturnType<typeof completeInvitedUserRegistration>>;
  try {
    invite = await completeInvitedUserRegistration({
      codeHashes: [hashUserInviteCode(input.code), hashLegacyInviteCode(input.code)],
      userId: data.user.id,
    });
  } catch {
    if (!await cleanup()) return { ok: false as const, error: "registration_cleanup_failed" as const };
    return { ok: false as const, error: "registration_failed" as const };
  }

  if (!invite) {
    const cleaned = await cleanup();
    await recordFailedAttempt();
    return cleaned
      ? { ok: false as const, error: "registration_failed" as const }
      : { ok: false as const, error: "registration_cleanup_failed" as const };
  }

  return { ok: true as const, userId: data.user.id, role: invite.role };
}
