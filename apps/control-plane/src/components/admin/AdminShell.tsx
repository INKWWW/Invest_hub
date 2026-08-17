import type { ReactNode } from "react";

import { SessionControls, type SessionViewer } from "../auth/SessionControls";

export type AdminSection = "overview" | "agent" | "sources" | "tasks" | "workers";

const navigation: Array<{ section: AdminSection; href: string; label: string }> = [
  { section: "overview", href: "/admin", label: "Overview" },
  { section: "sources", href: "/admin/sources", label: "Sources" },
  { section: "tasks", href: "/admin/tasks", label: "Tasks" },
  { section: "workers", href: "/admin/workers", label: "Workers" },
];

export function AdminShell({ active, viewer, children }: { active: AdminSection; viewer: SessionViewer; children: ReactNode }) {
  return <div className="admin-shell">
    <header className="admin-shell-header">
      <div className="admin-header-navigation">
        <a className="product-mark" href="/discord">Invest Hub</a>
        <nav aria-label="Admin navigation" className="admin-navigation">
          {navigation.map((item) => <a
            aria-current={item.section === active ? "page" : undefined}
            href={item.href}
            key={item.section}
          >{item.label}</a>)}
        </nav>
      </div>
      <SessionControls viewer={viewer} />
    </header>
    <main className="admin-content">{children}</main>
  </div>;
}
