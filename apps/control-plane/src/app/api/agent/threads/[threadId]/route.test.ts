import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const threadMocks = vi.hoisted(() => ({
  getResearchThread: vi.fn(),
  renameResearchThread: vi.fn(),
  deleteResearchThread: vi.fn(),
}));

vi.mock("../../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../../lib/db/repositories/research-threads", () => threadMocks);

import { DELETE, GET, PATCH } from "./route";

const context = { params: Promise.resolve({ threadId: "00000000-0000-0000-0000-000000000001" }) };

describe("/api/agent/threads/[threadId]", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-one", email: "one@example.invalid", role: "user" });
    threadMocks.getResearchThread.mockResolvedValue({
      id: "00000000-0000-0000-0000-000000000001",
      ownerId: "user-one",
      title: "宁德时代研究",
      createdAt: "2099-01-01T00:00:00.000Z",
      updatedAt: "2099-01-01T00:00:00.000Z",
      messages: [{ id: "message-one", threadId: "thread-one", ownerId: "user-one", role: "user", content: "研究", skillId: "investment-research", createdAt: "2099-01-01T00:00:01.000Z" }],
      artifacts: [],
    });
    threadMocks.renameResearchThread.mockResolvedValue({
      id: "00000000-0000-0000-0000-000000000001", ownerId: "user-one", title: "新的标题", createdAt: "2099-01-01T00:00:00.000Z", updatedAt: "2099-01-01T00:00:02.000Z",
    });
  });

  it("opens a persisted thread only for the authenticated owner", async () => {
    const response = await GET(new Request("http://localhost"), context);
    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.thread.messages).toHaveLength(1);
    expect(payload.thread.messages[0]).toMatchObject({ skill_id: "investment-research" });
    expect(threadMocks.getResearchThread).toHaveBeenCalledWith("user-one", "00000000-0000-0000-0000-000000000001");
  });

  it("rejects a guessed or malformed thread identifier before repository access", async () => {
    const response = await GET(new Request("http://localhost"), { params: Promise.resolve({ threadId: "not-a-uuid" }) });
    expect(response.status).toBe(422);
    expect(threadMocks.getResearchThread).not.toHaveBeenCalled();
  });

  it("renames without accepting a client-supplied owner", async () => {
    const response = await PATCH(new Request("http://localhost", {
      method: "PATCH", body: JSON.stringify({ title: "新的标题", owner_id: "user-two" }), headers: { "content-type": "application/json" },
    }), context);
    expect(response.status).toBe(422);
    expect(threadMocks.renameResearchThread).not.toHaveBeenCalled();

    const valid = await PATCH(new Request("http://localhost", {
      method: "PATCH", body: JSON.stringify({ title: "新的标题" }), headers: { "content-type": "application/json" },
    }), context);
    expect(valid.status).toBe(200);
    expect(threadMocks.renameResearchThread).toHaveBeenCalledWith("user-one", "00000000-0000-0000-0000-000000000001", "新的标题");
  });

  it("requires explicit confirmation before deletion", async () => {
    const response = await DELETE(new Request("http://localhost", {
      method: "DELETE", body: JSON.stringify({ confirm: false }), headers: { "content-type": "application/json" },
    }), context);
    expect(response.status).toBe(422);
    expect(threadMocks.deleteResearchThread).not.toHaveBeenCalled();

    const valid = await DELETE(new Request("http://localhost", {
      method: "DELETE", body: JSON.stringify({ confirm: true }), headers: { "content-type": "application/json" },
    }), context);
    expect(valid.status).toBe(200);
    expect(await valid.json()).toEqual({ deleted: true, memory_management: "separate" });
    expect(threadMocks.deleteResearchThread).toHaveBeenCalledWith("user-one", "00000000-0000-0000-0000-000000000001");
  });
});
