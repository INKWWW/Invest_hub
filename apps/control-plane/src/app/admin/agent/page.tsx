import { redirect } from "next/navigation";

import { AdminShell } from "../../../components/admin/AdminShell";
import { QuotaManagement, type AdminQuotaRow } from "../../../components/admin/QuotaManagement";
import { getCurrentUser } from "../../../lib/auth/current-user";
import { listResearchQuotasForAdmin } from "../../../lib/db/repositories/research-quota";

export default async function AdminAgentPage() {
  const viewer = await getCurrentUser();
  if (!viewer) redirect("/login?next=%2Fadmin%2Fagent");
  if (viewer.role !== "admin") redirect("/forbidden");
  const quotas = await listResearchQuotasForAdmin(viewer.id);
  const initialQuotas: AdminQuotaRow[] = quotas.map((quota) => ({
    owner_id: quota.ownerId,
    display_name: quota.displayName,
    email: quota.email,
    lifetime_units: quota.lifetimeUnits,
    available_units: quota.availableUnits,
    reserved_units: quota.reservedUnits,
    settled_units: quota.settledUnits,
    updated_at: quota.updatedAt,
  }));
  return <AdminShell active="agent" viewer={viewer}><QuotaManagement initialQuotas={initialQuotas} /></AdminShell>;
}
