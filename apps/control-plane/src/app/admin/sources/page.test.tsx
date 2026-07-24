import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

const sourceMocks = vi.hoisted(() => ({ listAdminSources: vi.fn() }));
const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));

vi.mock("../../../lib/db/repositories/sources", () => sourceMocks);
vi.mock("../../../lib/auth/current-user", () => authMocks);

import AdminSourcesPage from "./page";

describe("AdminSourcesPage", () => {
  it("honors the X workspace URL selection and removes the old source table", async () => {
    sourceMocks.listAdminSources.mockImplementation(({ sourceType }: { sourceType: "discord" | "x" }) => Promise.resolve(sourceType === "x" ? [{
      id: "x-private-id", sourceType: "x", displayName: "AllInvestHK", enabled: true,
      archivedAt: null, lifecycle: "identity_pending", workerName: null, latestCompletedAt: null,
    }] : []));
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-private-id", role: "admin", email: "admin@example.invalid" });

    const page = await AdminSourcesPage({ searchParams: Promise.resolve({ type: "x" }) });
    const html = renderToStaticMarkup(page);

    expect(html).toContain("管理 X 博主");
    expect(html).toContain("新建 X 博主");
    expect(html).not.toContain("新建 Discord 来源");
    expect(html).not.toContain("<table");
    expect(html).not.toContain("x-private-id");
  });
});
