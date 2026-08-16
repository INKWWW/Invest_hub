import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const demoMocks = vi.hoisted(() => ({ admitDemoRun: vi.fn() }));

vi.mock("../../../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../../../lib/db/repositories/agent-demo-runs", () => demoMocks);

import { POST } from "./route";

const context = { params: Promise.resolve({ threadId: "00000000-0000-0000-0000-000000000001" }) };

describe("/api/agent/threads/[threadId]/messages", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-one", email: "one@example.invalid", role: "user" });
    demoMocks.admitDemoRun.mockResolvedValue({
    runId: "run-one", userMessageId: "message-one", assistantMessageId: null, status: "queued", idempotent: false, invocationMode: "auto", skillId: null,
    });
  });

  it("admits a Demo run with an explicit request identity", async () => {
    const response = await POST(new Request("http://localhost", {
      method: "POST", body: JSON.stringify({ content: "研究宁德时代", request_id: "request-one" }), headers: { "content-type": "application/json" },
    }), context);
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ research_available: true, run: { id: "run-one", status: "queued" } });
    expect(demoMocks.admitDemoRun).toHaveBeenCalledWith({ ownerId: "user-one", threadId: "00000000-0000-0000-0000-000000000001", requestId: "request-one", question: "研究宁德时代", invocationMode: "auto", skillId: null });
  });

  it("rejects empty, overlong, or non-text messages", async () => {
    for (const content of ["", " ", "a".repeat(20001), 42]) {
      const response = await POST(new Request("http://localhost", {
        method: "POST", body: JSON.stringify({ content, request_id: "request-invalid" }), headers: { "content-type": "application/json" },
      }), context);
      expect(response.status).toBe(422);
    }
    expect(demoMocks.admitDemoRun).not.toHaveBeenCalled();
  });

  it("maps a Supabase error detail containing the busy code to a conflict", async () => {
    demoMocks.admitDemoRun.mockRejectedValue({ message: "Database error", details: "demo_runner_busy" });

    const response = await POST(new Request("http://localhost", {
      method: "POST", body: JSON.stringify({ content: "你好 在吗", request_id: "request-busy" }), headers: { "content-type": "application/json" },
    }), context);

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: "demo_runner_busy" });
  });
});
