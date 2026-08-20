import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ authenticateWorker: vi.fn() }));
const judgementMocks = vi.hoisted(() => ({ getXDailyJudgementContext: vi.fn() }));

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
vi.mock("../../../../../../lib/auth/worker", () => authMocks);
vi.mock("../../../../../../lib/db/repositories/x-daily-judgements", () => judgementMocks);

import { POST } from "./route";

const context = {
  run_id: "run-1",
  batch_id: "batch-1",
  attempt: 1,
  prompt_version: "v5-x-cross-blogger-1",
  sources: [],
  excluded_sources: [],
};

function request(body: unknown) {
  return new Request("https://control.example.invalid/api/worker/x-daily-judgements/run-1/context", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/worker/x-daily-judgements/[runId]/context", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.authenticateWorker.mockResolvedValue({ id: "worker-1" });
  });

  it("returns the V5 context supplied by the repository", async () => {
    judgementMocks.getXDailyJudgementContext.mockResolvedValue(context);

    const response = await POST(request({ attempt: 1 }), { params: Promise.resolve({ runId: "run-1" }) });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(context);
    expect(judgementMocks.getXDailyJudgementContext).toHaveBeenCalledWith("run-1", 1, "worker-1");
  });

  it("keeps unauthenticated context access closed", async () => {
    authMocks.authenticateWorker.mockResolvedValueOnce(null);

    const response = await POST(request({ attempt: 1 }), { params: Promise.resolve({ runId: "run-1" }) });

    expect(response.status).toBe(401);
    expect(judgementMocks.getXDailyJudgementContext).not.toHaveBeenCalled();
  });
});
