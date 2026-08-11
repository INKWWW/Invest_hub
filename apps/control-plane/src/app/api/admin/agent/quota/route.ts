import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import {
  adjustResearchQuota,
  listResearchQuotasForAdmin,
  ResearchQuotaError,
} from "../../../../../lib/db/repositories/research-quota";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function adminQuotaResponse(quota: {
  ownerId: string;
  lifetimeUnits: number;
  availableUnits: number;
  reservedUnits: number;
  settledUnits: number;
  updatedAt: string | null;
}) {
  return {
    owner_id: quota.ownerId,
    lifetime_units: quota.lifetimeUnits,
    available_units: quota.availableUnits,
    reserved_units: quota.reservedUnits,
    settled_units: quota.settledUnits,
    updated_at: quota.updatedAt,
  };
}

export async function GET() {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const quotas = await listResearchQuotasForAdmin(current.id);
    return NextResponse.json({ quotas: quotas.map((quota) => ({
      ...adminQuotaResponse(quota),
      display_name: quota.displayName,
      email: quota.email,
    })) });
  } catch {
    return NextResponse.json({ error: "quota_admin_list_failed" }, { status: 503 });
  }
}

export async function PATCH(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return NextResponse.json({ error: "invalid_quota_adjustment" }, { status: 422 });
  }
  const input = body as Record<string, unknown>;
  if (Object.keys(input).length !== 3
    || typeof input.owner_id !== "string"
    || !UUID.test(input.owner_id)
    || typeof input.lifetime_units !== "number"
    || !Number.isSafeInteger(input.lifetime_units)
    || input.lifetime_units < 0
    || input.lifetime_units > 1_000_000
    || typeof input.reason !== "string"
    || input.reason.trim().length === 0
    || input.reason.trim().length > 500) {
    return NextResponse.json({ error: "invalid_quota_adjustment" }, { status: 422 });
  }

  try {
    const quota = await adjustResearchQuota({
      ownerId: input.owner_id,
      lifetimeUnits: input.lifetime_units,
      reason: input.reason.trim(),
    });
    return NextResponse.json({ quota: adminQuotaResponse(quota) });
  } catch (error) {
    if (error instanceof ResearchQuotaError && ["research_quota_below_committed", "research_quota_target_not_found"].includes(error.code)) {
      return NextResponse.json({ error: error.code }, { status: 422 });
    }
    return NextResponse.json({ error: "quota_adjustment_failed" }, { status: 503 });
  }
}
