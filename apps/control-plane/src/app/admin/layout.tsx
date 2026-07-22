import type { ReactNode } from "react";
import { redirect } from "next/navigation";

import { isCurrentUser, requireRole } from "../../lib/auth/require-role";

export default async function AdminLayout({ children }: { children: ReactNode }) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) {
    if (current.status === 401) redirect("/login?next=%2Fadmin");
    redirect("/forbidden");
  }
  return children;
}
