import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const threadMocks = vi.hoisted(() => ({ listResearchThreads: vi.fn() }));
const navigationMocks = vi.hoisted(() => ({ redirect: vi.fn((value: string) => { throw new Error(`redirect:${value}`); }) }));

vi.mock("../../lib/auth/current-user", () => authMocks);
vi.mock("../../lib/db/repositories/research-threads", () => threadMocks);
vi.mock("next/navigation", () => navigationMocks);

import AgentPage from "./page";

describe("AgentPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-one", email: "one@example.invalid", role: "user" });
    threadMocks.listResearchThreads.mockResolvedValue([]);
  });

  it("is an authenticated independent Agent entry", async () => {
    const html = renderToStaticMarkup(await AgentPage());
    expect(html).toContain("投资研究 Agent");
    expect(html).toContain('href="/agent"');
    expect(html).toContain('href="/agent" aria-current="page"');
    expect(html).toContain("本地 Demo Runner");
    expect(html).not.toContain("可用额度");
    expect(threadMocks.listResearchThreads).toHaveBeenCalledWith("user-one");
  });

  it("redirects unauthenticated visitors to the existing login protection", async () => {
    authMocks.getCurrentUser.mockResolvedValue(null);
    await expect(AgentPage()).rejects.toThrow("redirect:/login?next=%2Fagent");
  });
});
