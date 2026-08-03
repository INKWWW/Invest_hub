import { describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ rpc: databaseMocks.rpc }),
}));

import {
  claimNextXDailyJudgement,
  completeXDailyJudgement,
  getXDailyJudgementContext,
  regenerateXDailyJudgement,
} from "./x-daily-judgements";

const claim = {
  run_id: "11111111-1111-4111-8111-111111111111",
  attempt: 1,
  lease_expires_at: "2099-01-01T00:10:00.000Z",
  batch: {
    id: "22222222-2222-4222-8222-222222222222",
    natural_date: "2099-01-01",
    cutoff_at: "2099-01-01T00:00:00.000Z",
    coverage_status: "complete",
  },
};

describe("X daily judgement repository", () => {
  it("returns only the validated claim identity supplied by the atomic RPC", async () => {
    databaseMocks.rpc.mockResolvedValue({ data: claim, error: null });

    await expect(claimNextXDailyJudgement("worker-1", "2099-01-01T00:00:00.000Z")).resolves.toEqual(claim);
    expect(databaseMocks.rpc).toHaveBeenCalledWith("claim_next_x_daily_judgement", {
      p_worker_id: "worker-1",
      p_now: "2099-01-01T00:00:00.000Z",
    });
  });

  it("does not expose raw canonical message content in the validated context", async () => {
    databaseMocks.rpc.mockResolvedValue({
      data: {
        run_id: claim.run_id,
        batch_id: claim.batch.id,
        attempt: 1,
        prompt_version: "v3-x-cross-blogger-1",
        sources: [{
          source_id: "33333333-3333-4333-8333-333333333333",
          display_name: "Fixture researcher",
          window_segments: [{
            id: "44444444-4444-4444-8444-444444444444",
            occurred_from_at: "2099-01-01T00:00:00.000Z",
            occurred_through_at: "2099-01-01T00:01:00.000Z",
            viewpoints: ["Demand is improving"],
            uncertainties: [],
            analyses: [{
              post_id: "post-1",
              blogger_viewpoint: "Demand is improving",
              arguments: ["Orders increased"],
              quoted_post_viewpoint: null,
              uncertainties: [],
              evidence_post_ids: ["post-1"],
            }],
          }],
        }],
        excluded_sources: [],
        canonical_messages: { content: "must never be accepted" },
      },
      error: null,
    });

    const result = await getXDailyJudgementContext(claim.run_id, 1, "worker-1");

    expect(JSON.stringify(result)).not.toContain("canonical_messages");
    expect(JSON.stringify(result)).not.toContain("must never be accepted");
    expect(result.batch_id).toBe(claim.batch.id);
    expect(result.sources[0]?.window_segments[0]?.analyses[0]?.evidence_post_ids).toEqual(["post-1"]);
  });

  it("sends only a validated versioned completion to the atomic RPC", async () => {
    databaseMocks.rpc.mockResolvedValue({ data: { run_id: claim.run_id, attempt: 1, status: "succeeded" }, error: null });
    const completion = {
      run_id: claim.run_id,
      attempt: 1,
      schema_version: "v3-x-cross-blogger" as const,
      provider: "codex_cli" as const,
      model_reported: null,
      prompt_version: "v3-x-cross-blogger-1" as const,
      security_industry_viewpoints: [{
        statement: "一位博主明确倾向买入该标的。", action_intent: "buy" as const, action_scope: "该标的", conditions: ["需求改善"],
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"], dissenting_source_ids: [], analysis_ids: ["post-1"], evidence_post_ids: ["post-1"], uncertainties: [],
      }],
      market_structure_viewpoints: [],
      strategy_mindset_viewpoints: [],
      uncertainties: [],
    };

    await completeXDailyJudgement(completion, "worker-1");

    expect(databaseMocks.rpc).toHaveBeenCalledWith("complete_x_daily_judgement", {
      p_run_id: claim.run_id,
      p_attempt: 1,
      p_worker_id: "worker-1",
      p_payload: {
        schema_version: "v3-x-cross-blogger",
        provider: "codex_cli",
        model_reported: null,
        prompt_version: "v3-x-cross-blogger-1",
        security_industry_viewpoints: [{
          statement: "一位博主明确倾向买入该标的。", action_intent: "buy", action_scope: "该标的", conditions: ["需求改善"],
          supporting_source_ids: ["33333333-3333-4333-8333-333333333333"], dissenting_source_ids: [], analysis_ids: ["post-1"], evidence_post_ids: ["post-1"], uncertainties: [],
        }],
        market_structure_viewpoints: [],
        strategy_mindset_viewpoints: [],
        uncertainties: [],
      },
    });
  });

  it("returns only the queued regeneration identity from the audited RPC", async () => {
    databaseMocks.rpc.mockResolvedValue({
      data: { run_id: "55555555-5555-4555-8555-555555555555", status: "queued", attempt: 0 },
      error: null,
    });

    await expect(regenerateXDailyJudgement(
      "22222222-2222-4222-8222-222222222222",
      "66666666-6666-4666-8666-666666666666",
    )).resolves.toEqual({
      runId: "55555555-5555-4555-8555-555555555555",
      status: "queued",
      attempt: 0,
    });
    expect(databaseMocks.rpc).toHaveBeenCalledWith("regenerate_x_daily_judgement", {
      p_batch_id: "22222222-2222-4222-8222-222222222222",
      p_requested_by: "66666666-6666-4666-8666-666666666666",
    });
  });
});
