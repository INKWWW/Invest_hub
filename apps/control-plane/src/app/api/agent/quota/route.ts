import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../lib/auth/current-user";
import { getResearchQuota } from "../../../../lib/db/repositories/research-quota";

export async function GET() {
  const current = await getCurrentUser();
  if (!current) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const quota = await getResearchQuota(current.id);
    return NextResponse.json({ quota: {
      lifetime_units: quota.lifetimeUnits,
      available_units: quota.availableUnits,
      reserved_units: quota.reservedUnits,
      settled_units: quota.settledUnits,
      updated_at: quota.updatedAt,
    } });
  } catch {
    return NextResponse.json({ error: "quota_read_failed" }, { status: 503 });
  }
}
