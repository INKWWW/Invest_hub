import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ authenticateWorker: vi.fn() }));
const judgementMocks = vi.hoisted(() => ({
  completeXDailyJudgement: vi.fn(),
  getXDailyJudgementContext: vi.fn(),
}));

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

const v5Context = {
  run_id: "run-1",
  batch_id: "batch-1",
  attempt: 1,
  prompt_version: "v5-x-cross-blogger-1",
  sources: [{
    source_id: "source-1",
    display_name: "Fixture source",
    window_segments: [{
      id: "segment-1",
      schema_version: "v4-x-window",
      prompt_version: "v4-x-window-1",
      occurred_from_at: "2099-01-01T00:00:00.000Z",
      occurred_through_at: "2099-01-01T00:01:00.000Z",
      segment_output: {},
      analyses: [{
        analysis_id: "analysis-1",
        schema_version: "v4-x-post-analysis",
        prompt_version: "v4-x-post-analysis-1",
        analysis_output: {},
        evidence_post_ids: ["post-1"],
      }],
    }],
  }],
  excluded_sources: [],
};

const v5Completion = {
  run_id: "run-1",
  attempt: 1,
  schema_version: "v5-x-cross-blogger",
  provider: "codex_cli",
  model_reported: null,
  prompt_version: "v5-x-cross-blogger-1",
  ai_synthesis: { cross_blogger_integrations: [], ai_assessments: [] },
  security_industry_theses: [],
  market_structure_theses: [],
  strategy_mindset_theses: [],
  uncertainties: [],
};

const v4Context = { ...v5Context, prompt_version: "v4-x-cross-blogger-1" };
const v4Completion = {
  run_id: "run-1",
  attempt: 1,
  schema_version: "v4-x-cross-blogger",
  provider: "codex_cli",
  model_reported: null,
  prompt_version: "v4-x-cross-blogger-1",
  security_industry_viewpoints: [{
    statement: "Fixture statement",
    action_intent: "none",
    action_scope_status: "not_applicable",
    action_scope: "",
    conditions: [],
    supporting_source_ids: ["source-1"],
    dissenting_source_ids: [],
    analysis_ids: ["analysis-1"],
    evidence_post_ids: ["post-1"],
    uncertainties: [],
  }],
  market_structure_viewpoints: [],
  strategy_mindset_viewpoints: [],
  uncertainties: [],
};

function request(body: unknown) {
  return new Request("https://control.example.invalid/api/worker/x-daily-judgements/run-1/complete", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function params() {
  return { params: Promise.resolve({ runId: "run-1" }) };
}

describe("POST /api/worker/x-daily-judgements/[runId]/complete", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.authenticateWorker.mockResolvedValue({ id: "worker-1" });
    judgementMocks.completeXDailyJudgement.mockResolvedValue({ run_id: "run-1", attempt: 1, status: "succeeded" });
  });

  it("passes a structurally valid V5 completion to the database authority", async () => {
    judgementMocks.getXDailyJudgementContext.mockResolvedValue(v5Context);

    const response = await POST(request(v5Completion), params());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ run_id: "run-1", attempt: 1, status: "succeeded" });
    expect(judgementMocks.completeXDailyJudgement).toHaveBeenCalledWith(v5Completion, "worker-1");
  });

  it("keeps malformed or unknown V5 envelopes fail-closed before the database call", async () => {
    const malformed = { ...v5Completion, unexpected: true };
    const response = await POST(request(malformed), params());

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_daily_judgement_completion" });
    expect(judgementMocks.getXDailyJudgementContext).not.toHaveBeenCalled();
    expect(judgementMocks.completeXDailyJudgement).not.toHaveBeenCalled();
  });

  it("continues to apply the existing V4 frozen-context checks", async () => {
    judgementMocks.getXDailyJudgementContext.mockResolvedValue(v4Context);

    const response = await POST(request(v4Completion), params());

    expect(response.status).toBe(200);
    expect(judgementMocks.completeXDailyJudgement).toHaveBeenCalledWith(v4Completion, "worker-1");
  });
});
