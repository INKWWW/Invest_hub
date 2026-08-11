import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const threadMocks = vi.hoisted(() => ({ appendResearchMessage: vi.fn() }));

vi.mock("../../../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../../../lib/db/repositories/research-threads", () => threadMocks);

import { POST } from "./route";

const context = { params: Promise.resolve({ threadId: "00000000-0000-0000-0000-000000000001" }) };

describe("/api/agent/threads/[threadId]/messages", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-one", email: "one@example.invalid", role: "user" });
    threadMocks.appendResearchMessage.mockResolvedValue({
      id: "message-one", threadId: "00000000-0000-0000-0000-000000000001", ownerId: "user-one", role: "user", content: "研究宁德时代", createdAt: "2099-01-01T00:00:01.000Z",
    });
  });

  it("persists plain text while keeping research execution fail-closed", async () => {
    const response = await POST(new Request("http://localhost", {
      method: "POST", body: JSON.stringify({ content: "研究宁德时代" }), headers: { "content-type": "application/json" },
    }), context);
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ research_available: false, message: { role: "user", content: "研究宁德时代" } });
    expect(threadMocks.appendResearchMessage).toHaveBeenCalledWith("user-one", "00000000-0000-0000-0000-000000000001", "研究宁德时代");
  });

  it("rejects empty, overlong, or non-text messages", async () => {
    for (const content of ["", " ", "a".repeat(20001), 42]) {
      const response = await POST(new Request("http://localhost", {
        method: "POST", body: JSON.stringify({ content }), headers: { "content-type": "application/json" },
      }), context);
      expect(response.status).toBe(422);
    }
    expect(threadMocks.appendResearchMessage).not.toHaveBeenCalled();
  });
});
