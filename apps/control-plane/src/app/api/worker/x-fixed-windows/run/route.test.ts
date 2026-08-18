import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ authenticateWorker: vi.fn() }));
vi.mock("next/server", () => ({
  NextResponse: class MockNextResponse {
    status: number;
    private readonly payload: unknown;
    constructor(payload: unknown, init?: { status?: number }) {
      this.payload = payload;
      this.status = init?.status ?? 200;
    }
    static json(payload: unknown, init?: { status?: number }) {
      return new MockNextResponse(payload, init);
    }
    async json() { return this.payload; }
  },
}));
const taskMocks = vi.hoisted(() => ({
  beginXDemoFixedWindowRun: vi.fn(), bindXDemoFixedWindowTask: vi.fn(), createXDemoFixedWindowTaskForRun: vi.fn(),
  failXDemoFixedWindowSource: vi.fn(), settleXDemoFixedWindowRun: vi.fn(), terminalizeXDemoFixedWindowJudgement: vi.fn(),
  TaskScopeError: class TaskScopeError extends Error {},
}));
const judgementMocks = vi.hoisted(() => ({ claimXDemoFixedWindowJudgement: vi.fn() }));

vi.mock("../../../../../lib/auth/worker", () => authMocks);
vi.mock("../../../../../lib/db/repositories/tasks", () => taskMocks);
vi.mock("../../../../../lib/db/repositories/x-daily-judgements", () => judgementMocks);

import { POST } from "./route";

function request(body: unknown) {
  return new Request("https://control.example.invalid/api/worker/x-fixed-windows/run", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
  });
}

describe("POST /api/worker/x-fixed-windows/run", () => {
  beforeEach(() => vi.clearAllMocks());

  it("requires Worker authentication before the scoped judgement action", async () => {
    authMocks.authenticateWorker.mockResolvedValueOnce(null);
    const response = await POST(request({ action: "judgement_failure", run_id: "demo-1", judgement_run_id: "judgement-1" }));
    expect(response.status).toBe(401);
    expect(taskMocks.terminalizeXDemoFixedWindowJudgement).not.toHaveBeenCalled();
  });

  it("maps the exact scoped judgement identity to the repository and returns its status", async () => {
    authMocks.authenticateWorker.mockResolvedValueOnce({ id: "worker-1", status: "online" });
    taskMocks.terminalizeXDemoFixedWindowJudgement.mockResolvedValueOnce({
      status: "failed", demo_run_id: "demo-1", judgement_run_id: "judgement-1", idempotent: false,
    });
    const response = await POST(request({ action: "judgement_failure", run_id: "demo-1", judgement_run_id: "judgement-1" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ status: "failed", judgement_run_id: "judgement-1" });
    expect(taskMocks.terminalizeXDemoFixedWindowJudgement).toHaveBeenCalledWith({
      demoRunId: "demo-1", judgementRunId: "judgement-1", workerId: "worker-1",
    });
  });

  it("routes every fixed-window main-chain action with the authenticated Worker identity", async () => {
    authMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.beginXDemoFixedWindowRun.mockResolvedValue({ run_id: "demo-1", status: "running", idempotent: false, cutoff_at: "2026-08-18T16:00:00+08:00", sources: [] });
    taskMocks.createXDemoFixedWindowTaskForRun.mockResolvedValue({ id: "task-1", source_id: "source-1", idempotent: false, demo_fixed_window: {} });
    taskMocks.bindXDemoFixedWindowTask.mockResolvedValue({ status: "attached" });
    taskMocks.failXDemoFixedWindowSource.mockResolvedValue({ status: "excluded" });
    taskMocks.settleXDemoFixedWindowRun.mockResolvedValue({ status: "judgement_pending", coverage_status: "partial" });
    judgementMocks.claimXDemoFixedWindowJudgement.mockResolvedValue({ run_id: "judgement-1", attempt: 1, lease_expires_at: "2099-01-01T00:10:00Z", batch: {} });

    expect((await POST(request({ action: "start", cutoff_at: "2026-08-18T16:00:00+08:00" }))).status).toBe(200);
    expect((await POST(request({ action: "create_task", run_id: "demo-1", source_id: "source-1", cutoff_at: "2026-08-18T16:00:00+08:00", account_id: "fixture" }))).status).toBe(200);
    expect((await POST(request({ action: "bind_task", run_id: "demo-1", source_id: "source-1", task_id: "task-1" }))).status).toBe(200);
    expect((await POST(request({ action: "source_failure", run_id: "demo-1", source_id: "source-1", reason: "provider_failure" }))).status).toBe(200);
    expect((await POST(request({ action: "settle", run_id: "demo-1" }))).status).toBe(200);
    expect((await POST(request({ action: "claim_judgement", run_id: "demo-1" }))).status).toBe(200);
    expect(taskMocks.createXDemoFixedWindowTaskForRun).toHaveBeenCalledWith({ runId: "demo-1", sourceId: "source-1", cutoffAt: "2026-08-18T16:00:00+08:00", workerId: "worker-1", accountId: "fixture" });
    expect(judgementMocks.claimXDemoFixedWindowJudgement).toHaveBeenCalledWith("demo-1", "worker-1");
  });

  it("rejects the removed Ticket 02R activation action", async () => {
    authMocks.authenticateWorker.mockResolvedValueOnce({ id: "worker-1", status: "online" });
    const response = await POST(request({ action: "claim_activation", run_id: "demo-1", source_id: "source-1" }));
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_demo_fixed_window_run_request" });
  });

  it("maps a frozen snapshot mutation to a scoped client error", async () => {
    authMocks.authenticateWorker.mockResolvedValueOnce({ id: "worker-1", status: "online" });
    taskMocks.createXDemoFixedWindowTaskForRun.mockRejectedValueOnce(new Error("x_demo_fixed_window_snapshot_changed"));
    const response = await POST(request({ action: "create_task", run_id: "demo-1", source_id: "source-1", cutoff_at: "2026-08-18T16:00:00+08:00", account_id: "fixture" }));
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "x_demo_fixed_window_snapshot_changed" });
  });
});
