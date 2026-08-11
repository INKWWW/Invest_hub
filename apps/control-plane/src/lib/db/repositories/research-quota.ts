import type { User } from "@supabase/supabase-js";

import { createSupabaseAdminClient, createSupabaseServerClient } from "../supabase-server";
import type { Database } from "../types";

type QuotaRow = Database["public"]["Tables"]["research_quotas"]["Row"];

export type ResearchQuota = {
  ownerId: string;
  lifetimeUnits: number;
  availableUnits: number;
  reservedUnits: number;
  settledUnits: number;
  updatedAt: string | null;
};

export type AdminResearchQuota = ResearchQuota & {
  displayName: string | null;
  email: string | null;
};

export class ResearchQuotaError extends Error {
  constructor(public readonly code: string) {
    super(code);
  }
}

function mapQuota(ownerId: string, row?: Pick<QuotaRow, "lifetime_units" | "reserved_units" | "settled_units" | "updated_at"> | null): ResearchQuota {
  const lifetimeUnits = row?.lifetime_units ?? 0;
  const reservedUnits = row?.reserved_units ?? 0;
  const settledUnits = row?.settled_units ?? 0;
  return {
    ownerId,
    lifetimeUnits,
    reservedUnits,
    settledUnits,
    availableUnits: lifetimeUnits - reservedUnits - settledUnits,
    updatedAt: row?.updated_at ?? null,
  };
}

function mapRpcQuota(ownerId: string, value: unknown): ResearchQuota {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new ResearchQuotaError("invalid_quota_response");
  const row = value as Record<string, unknown>;
  if (typeof row.lifetime_units !== "number"
    || typeof row.reserved_units !== "number"
    || typeof row.settled_units !== "number"
    || typeof row.available_units !== "number") {
    throw new ResearchQuotaError("invalid_quota_response");
  }
  return {
    ownerId,
    lifetimeUnits: row.lifetime_units,
    reservedUnits: row.reserved_units,
    settledUnits: row.settled_units,
    availableUnits: row.available_units,
    updatedAt: typeof row.updated_at === "string" ? row.updated_at : null,
  };
}

function throwQuotaError(error: { message?: string } | null): never {
  throw new ResearchQuotaError(error?.message ?? "quota_operation_failed");
}

export async function getResearchQuota(ownerId: string): Promise<ResearchQuota> {
  const { data, error } = await (await createSupabaseServerClient())
    .from("research_quotas")
    .select("owner_id,lifetime_units,reserved_units,settled_units,updated_at")
    .eq("owner_id", ownerId)
    .maybeSingle();
  if (error) throw error;
  return mapQuota(ownerId, data);
}

export async function listResearchQuotasForAdmin(actorId: string): Promise<AdminResearchQuota[]> {
  const db = createSupabaseAdminClient();
  const { data: actor, error: actorError } = await db.from("profiles").select("id").eq("id", actorId).eq("role", "admin").maybeSingle();
  if (actorError) throw actorError;
  if (!actor) throw new ResearchQuotaError("forbidden");
  const [{ data: profiles, error: profileError }, authUsers] = await Promise.all([
    db.from("profiles").select("id,display_name").eq("role", "user").order("created_at", { ascending: true }),
    listAllAuthUsers(db),
  ]);
  if (profileError) throw profileError;
  const ownerIds = (profiles ?? []).map((profile) => profile.id);
  const { data: quotaRows, error: quotaError } = ownerIds.length === 0
    ? { data: [], error: null }
    : await db.from("research_quotas").select("owner_id,lifetime_units,reserved_units,settled_units,updated_at").in("owner_id", ownerIds);
  if (quotaError) throw quotaError;

  const quotaByOwner = new Map((quotaRows ?? []).map((row) => [row.owner_id, row]));
  const emailByOwner = new Map(authUsers.map((user) => [user.id, user.email ?? null]));
  return (profiles ?? []).map((profile) => ({
    ...mapQuota(profile.id, quotaByOwner.get(profile.id)),
    displayName: profile.display_name,
    email: emailByOwner.get(profile.id) ?? null,
  }));
}

async function listAllAuthUsers(db: ReturnType<typeof createSupabaseAdminClient>): Promise<User[]> {
  const users: User[] = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) return users;
  }
}

export async function adjustResearchQuota(input: {
  ownerId: string;
  lifetimeUnits: number;
  reason: string;
}): Promise<ResearchQuota> {
  const { data, error } = await (await createSupabaseServerClient()).rpc("admin_adjust_research_quota", {
    p_owner_id: input.ownerId,
    p_lifetime_units: input.lifetimeUnits,
    p_reason: input.reason,
  });
  if (error) throwQuotaError(error);
  return mapRpcQuota(input.ownerId, data);
}

export async function reserveResearchQuota(requestId: string): Promise<ResearchQuota> {
  const client = await createSupabaseServerClient();
  const { data: userData, error: userError } = await client.auth.getUser();
  if (userError || !userData.user) throw new ResearchQuotaError("unauthorized");
  const { data, error } = await client.rpc("reserve_research_quota", { p_request_id: requestId });
  if (error) throwQuotaError(error);
  return mapRpcQuota(userData.user.id, data);
}

export async function commitResearchQuota(reservationId: string, ownerId: string): Promise<ResearchQuota> {
  const { data, error } = await (await createSupabaseServerClient()).rpc("commit_research_quota", { p_reservation_id: reservationId });
  if (error) throwQuotaError(error);
  return mapRpcQuota(ownerId, data);
}

export async function releaseResearchQuota(reservationId: string, ownerId: string): Promise<ResearchQuota> {
  const { data, error } = await (await createSupabaseServerClient()).rpc("release_research_quota", { p_reservation_id: reservationId });
  if (error) throwQuotaError(error);
  return mapRpcQuota(ownerId, data);
}
