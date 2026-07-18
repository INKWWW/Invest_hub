import { statusLabel, type AdminDisplayStatus } from "../../lib/admin/view-model";

export function StatusBadge({ status }: { status: AdminDisplayStatus }) {
  return (
    <span aria-label={`Status: ${statusLabel(status)}`} data-status={status}>
      {statusLabel(status)}
    </span>
  );
}
