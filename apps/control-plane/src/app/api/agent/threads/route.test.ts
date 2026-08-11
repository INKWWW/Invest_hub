import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({
  getCurrentUser: vi.fn(),
}));
const threadMocks = vi.hoisted(() => ({
  listResearchThreads: vi.fn(),
  createResearchThread: vi.fn(),
}));

vi.mock("../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../lib/db/repositories/research-threads", () => threadMocks);

import { GET, POST } from "./route";

describe("/api/agent/threads", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-one", email: "one@example.invalid", role: "user" });
    threadMocks.listResearchThreads.mockResolvedValue([]);
    threadMocks.createResearchThread.mockResolvedValue({
      id: "thread-one",
      ownerId: "user-one",
      title: "新研究会话",
      createdAt: "2099-01-01T00:00:00.000Z",
      updatedAt: "2099-01-01T00:00:00.000Z",
    });
  });

  it("requires an authenticated user before listing threads", async () => {
    authMocks.getCurrentUser.mockResolvedValue(null);
    const response = await GET();
    expect(response.status).toBe(401);
    expect(threadMocks.listResearchThreads).not.toHaveBeenCalled();
  });

  it("lists only the current user's thread view", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ threads: [] });
    expect(threadMocks.listResearchThreads).toHaveBeenCalledWith("user-one");
  });

  it("creates a thread with the authenticated owner and rejects extra fields", async () => {
    const invalid = await POST(new Request("http://localhost/api/agent/threads", {
      method: "POST",
      body: JSON.stringify({ title: "client-owned", owner_id: "user-two" }),
      headers: { "content-type": "application/json" },
    }));
    expect(invalid.status).toBe(422);
    expect(threadMocks.createResearchThread).not.toHaveBeenCalled();

    const response = await POST(new Request("http://localhost/api/agent/threads", {
      method: "POST",
      body: "{}",
      headers: { "content-type": "application/json" },
    }));
    expect(response.status).toBe(201);
    expect(threadMocks.createResearchThread).toHaveBeenCalledWith("user-one");
  });
});
