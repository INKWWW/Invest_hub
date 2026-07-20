import type { ReactNode } from "react";

export type AdminSection = "overview" | "sources" | "tasks" | "workers";

const navigation: Array<{ section: AdminSection; href: string; label: string }> = [
  { section: "overview", href: "/admin", label: "Overview" },
  { section: "sources", href: "/admin/sources", label: "Sources" },
  { section: "tasks", href: "/admin/tasks", label: "Tasks" },
  { section: "workers", href: "/admin/workers", label: "Workers" },
];

export function AdminShell({ active, children }: { active: AdminSection; children: ReactNode }) {
  return <div className="admin-shell">
    <header className="admin-shell-header">
      <a className="product-mark" href="/discord">Invest Hub</a>
      <nav aria-label="Admin navigation" className="admin-navigation">
        {navigation.map((item) => <a
          aria-current={item.section === active ? "page" : undefined}
          href={item.href}
          key={item.section}
        >{item.label}</a>)}
      </nav>
    </header>
    <main className="admin-content">{children}</main>
  </div>;
}
