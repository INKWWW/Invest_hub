import type { ReactNode } from "react";
import { redirect } from "next/navigation";

import { isCurrentUser, requireRole } from "../../lib/auth/require-role";

export default async function AdminLayout({ children }: { children: ReactNode }) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) {
    if (current.status === 401) redirect("/login?next=%2Fadmin");
    redirect("/?error=forbidden");
  }
  return (
    <main>
      <header>
        <p><strong>Invest Hub V0</strong> · Admin debug</p>
        <nav aria-label="Admin navigation">
          <a href="/admin">Overview</a>{" · "}
          <a href="/admin/workers">Workers</a>{" · "}
          <a href="/admin/sources">Sources</a>{" · "}
          <a href="/admin/tasks">Tasks</a>
        </nav>
      </header>
      {children}
    </main>
  );
}

