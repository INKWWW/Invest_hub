import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  rows: new Map<string, unknown[]>(),
  filters: [] as Array<{ table: string; field: string; value: unknown }>,
  ins: [] as Array<{ table: string; field: string; values: unknown[] }>,
  ranges: [] as Array<{ table: string; from: number; to: number }>,
  selects: [] as Array<{ table: string; columns: string }>,
}));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({
    from(table: string) {
      const queryIns: Array<{ field: string; values: unknown[] }> = [];
      const queryOrders: Array<{ field: string; ascending: boolean }> = [];
      let queryRange: { from: number; to: number } | undefined;
      const query = {
        select: (columns: string) => { databaseMocks.selects.push({ table, columns }); return query; },
        eq: (field: string, value: unknown) => { databaseMocks.filters.push({ table, field, value }); return query; },
        in: (field: string, values: unknown[]) => { databaseMocks.ins.push({ table, field, values }); queryIns.push({ field, values }); return query; },
        order: (field: string, options?: { ascending?: boolean }) => {
          const ascending = options?.ascending !== false;
          queryOrders.push({ field, ascending });
          return query;
        },
        range: (from: number, to: number) => {
          databaseMocks.ranges.push({ table, from, to });
          queryRange = { from, to };
          return query;
        },
        then: (resolve: (value: { data: unknown[]; error: null }) => unknown) => {
          const rows = (databaseMocks.rows.get(table) ?? []).filter((row) => queryIns.every(({ field, values }) => (
            row && typeof row === "object" && values.includes((row as Record<string, unknown>)[field])
          ))).sort((left, right) => {
            if (!left || typeof left !== "object" || !right || typeof right !== "object") return 0;
            for (const { field, ascending } of queryOrders) {
              const leftValue = (left as Record<string, unknown>)[field];
              const rightValue = (right as Record<string, unknown>)[field];
              if (leftValue === rightValue) continue;
              const comparison = leftValue === undefined ? -1 : rightValue === undefined ? 1
                : typeof leftValue === "number" && typeof rightValue === "number" ? leftValue - rightValue
                  : String(leftValue).localeCompare(String(rightValue));
              return ascending ? comparison : -comparison;
            }
            return 0;
          });
          const from = queryRange?.from ?? 0;
          const requestedTo = queryRange?.to ?? from + 999;
          const cappedTo = Math.min(requestedTo, from + 999);
          return resolve({ data: rows.slice(from, cappedTo + 1), error: null });
        },
      };
      return query;
    },
  }),
}));

import { readXDay } from "./reader";

const repoRoot = resolve(process.cwd(), "..", "..");
const xDailyV5CompletionFixture = JSON.parse(
  readFileSync(resolve(repoRoot, "tests/fixtures/x_daily_v5/completion.json"), "utf8"),
) as Record<string, unknown>;

function readerV5Fixture() {
  return JSON.parse(JSON.stringify(xDailyV5CompletionFixture)
    .replaceAll("\"source-alpha\"", "\"source-a\"")
    .replaceAll("\"source-beta\"", "\"source-b\"")) as Record<string, unknown>;
}

const internalReadableTokenSentinel = "Analysis-17, BATCH-42; run-9 / SEGMENT-3 thesis-99 source-hidden post-hidden@2 integration-hidden assessment-hidden";

describe("X reader date projection", () => {
  beforeEach(() => {
    const currentV5 = readerV5Fixture();
    currentV5.uncertainties = [
      "仅基于当日已完成采集的博主窗口，仍可能遗漏尚未纳入的覆盖范围。",
      internalReadableTokenSentinel,
    ];

    databaseMocks.rows.clear();
    databaseMocks.filters.length = 0;
    databaseMocks.ins.length = 0;
    databaseMocks.ranges.length = 0;
    databaseMocks.selects.length = 0;
    databaseMocks.rows.set("sources", [
      { id: "source-a", source_key: "alpha", display_name: "Alpha", enabled: true },
      { id: "source-b", source_key: "beta", display_name: "Beta", enabled: true },
      { id: "source-c", source_key: "gamma", display_name: "Gamma current", enabled: false },
    ]);
    databaseMocks.rows.set("x_daily_viewpoint_segments", [
      { source_id: "source-a", natural_date: "2099-01-02", occurred_from_at: "2099-01-02T08:00:00.000Z", occurred_through_at: "2099-01-02T08:00:00.000Z", window_viewpoints: ["Alpha earlier"], post_analysis_refs: [], evidence_refs: ["internal"] },
      { source_id: "source-c", natural_date: "2099-01-02", occurred_from_at: "2099-01-02T07:00:00.000Z", occurred_through_at: "2099-01-02T08:00:00.000Z", window_viewpoints: ["Archived Gamma viewpoint"], post_analysis_refs: [], evidence_refs: [] },
    ]);
    databaseMocks.rows.set("x_collection_batches", [
      { id: "batch-16", natural_date: "2099-01-02", cutoff_at: "2099-01-02T08:00:00.000Z", status: "succeeded" },
      { id: "batch-20", natural_date: "2099-01-02", cutoff_at: "2099-01-02T12:00:00.000Z", status: "succeeded" },
      { id: "batch-pending", natural_date: "2099-01-01", cutoff_at: "2099-01-01T12:00:00.000Z", status: "judgement_pending" },
      { id: "batch-failed", natural_date: "2099-01-01", cutoff_at: "2099-01-01T08:00:00.000Z", status: "judgement_failed" },
    ]);
    databaseMocks.rows.set("x_daily_judgement_versions", [
      { batch_id: "batch-16", revision: 1, coverage_status: "partial", schema_version: "v4-x-cross-blogger", prompt_version: "v4-x-cross-blogger-1", output: { stock_viewpoints: [{ statement: "sixteen analysis-17 batch-42", supporting_source_ids: ["source-a"], dissenting_source_ids: [], analysis_ids: ["analysis-16"], evidence_post_ids: ["post-16"], uncertainties: ["legacy run-9"] }], market_industry_viewpoints: [], uncertainties: [] } },
      { batch_id: "batch-20", revision: 1, coverage_status: "complete", schema_version: "v4-x-cross-blogger", prompt_version: "v4-x-cross-blogger-1", output: { security_industry_viewpoints: [{ statement: "stale analysis-17 batch-42", action_intent: "buy", action_scope: "旧版测试个股 run-9 segment-3", conditions: ["旧版条件 source-hidden"], supporting_source_ids: ["source-a"], dissenting_source_ids: [], analysis_ids: ["analysis-1"], evidence_post_ids: ["post-1"], uncertainties: ["legacy post-hidden@2"] }], market_structure_viewpoints: [], strategy_mindset_viewpoints: [], uncertainties: ["legacy analysis-17"] } },
      { batch_id: "batch-20", revision: 2, coverage_status: "complete", schema_version: "v5-x-cross-blogger", prompt_version: "v5-x-cross-blogger-1", output: currentV5 },
    ]);
    databaseMocks.rows.set("x_collection_batch_sources", [
      { batch_id: "batch-16", source_id: "source-a", source_display_name: "Alpha at sixteen", x_sync_task_id: "task-a-16", settlement_status: "excluded", exclusion_code: "settlement_deadline_exceeded" },
      { batch_id: "batch-16", source_id: "source-c", source_display_name: "Gamma archived", x_sync_task_id: "task-c-16", settlement_status: "included" },
      { batch_id: "batch-20", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: "task-a-20", settlement_status: "included" },
      { batch_id: "batch-20", source_id: "source-b", source_display_name: "Beta", x_sync_task_id: "task-b-20", settlement_status: "no_new_information" },
      { batch_id: "batch-pending", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: "task-a-pending", settlement_status: "pending" },
      { batch_id: "batch-pending", source_id: "source-b", source_display_name: "Beta", x_sync_task_id: "task-b-failed", settlement_status: "excluded" },
      { batch_id: "batch-pending", source_id: "source-c", source_display_name: "Gamma archived", x_sync_task_id: "task-c-delayed", settlement_status: "excluded", exclusion_code: "settlement_deadline_exceeded" },
    ]);
    databaseMocks.rows.set("sync_tasks", [
      { id: "task-a-16", source_id: "source-a", status: "failed", updated_at: "2099-01-03T00:00:00.000Z" },
      { id: "task-c-16", source_id: "source-c", status: "succeeded", updated_at: "2099-01-02T08:00:00.000Z" },
      { id: "task-a-20", source_id: "source-a", status: "succeeded", updated_at: "2099-01-02T12:00:00.000Z" },
      { id: "task-b-20", source_id: "source-b", status: "succeeded", updated_at: "2099-01-02T12:00:00.000Z" },
      { id: "task-a-pending", source_id: "source-a", status: "queued", updated_at: "2099-01-01T12:00:00.000Z" },
      { id: "task-b-failed", source_id: "source-b", status: "failed", updated_at: "2099-01-01T12:00:00.000Z" },
      { id: "task-c-delayed", source_id: "source-c", status: "running", updated_at: "2099-01-01T12:00:00.000Z" },
      { id: "task-global-latest", source_id: "source-a", status: "failed", updated_at: "2100-01-01T00:00:00.000Z" },
    ]);
    databaseMocks.rows.set("task_attempts", [
      { task_id: "task-b-20", result: { no_new_data: true }, updated_at: "2099-01-02T12:01:00.000Z" },
      { task_id: "task-global-latest", result: { no_new_data: false }, updated_at: "2100-01-01T00:01:00.000Z" },
    ]);
  });

  it("projects late persisted segments without changing judgement", async () => {
    databaseMocks.rows.set("sources", [
      { id: "source-a", source_key: "alpha", display_name: "Alpha" },
      { id: "source-b", source_key: "beta", display_name: "Beta" },
      { id: "source-c", source_key: "gamma", display_name: "Gamma" },
      { id: "source-d", source_key: "delta", display_name: "Delta" },
    ]);
    databaseMocks.rows.set("x_daily_viewpoint_segments", [
      {
        source_id: "source-a",
        natural_date: "2099-01-03",
        range_task_id: "task-late",
        created_at: "2099-01-04T01:00:00.000Z",
        occurred_from_at: "2099-01-03T08:00:00.000Z",
        occurred_through_at: "2099-01-03T12:00:00.000Z",
        window_viewpoints: ["迟到但真实持久化的观点"],
        post_analysis_refs: [],
        evidence_refs: ["internal"],
      },
      {
        source_id: "source-b",
        natural_date: "2099-01-03",
        range_task_id: "task-normal",
        created_at: "2099-01-04T01:00:00+08:00",
        occurred_from_at: "2099-01-03T12:00:00.000Z",
        occurred_through_at: "2099-01-03T13:00:00.000Z",
        window_viewpoints: ["正常成功的观点"],
        post_analysis_refs: [],
        evidence_refs: ["internal"],
      },
    ]);
    databaseMocks.rows.set("x_collection_batches", [{
      id: "batch-late",
      natural_date: "2099-01-03",
      cutoff_at: "2099-01-03T12:00:00.000Z",
      settlement_deadline_at: "2099-01-03T14:00:00.000Z",
      status: "succeeded",
    }, {
      id: "batch-normal",
      natural_date: "2099-01-03",
      cutoff_at: "2099-01-03T13:00:00.000Z",
      settlement_deadline_at: "2099-01-03T18:00:00.000Z",
      status: "succeeded",
    }, {
      id: "batch-queued",
      natural_date: "2099-01-03",
      cutoff_at: "2099-01-03T14:00:00.000Z",
      settlement_deadline_at: "2099-01-03T15:00:00.000Z",
      status: "judgement_pending",
    }, {
      id: "batch-gap",
      natural_date: "2099-01-03",
      cutoff_at: "2099-01-03T15:00:00.000Z",
      settlement_deadline_at: "2099-01-03T16:00:00.000Z",
      status: "succeeded",
    }]);
    databaseMocks.rows.set("x_daily_judgement_versions", []);
    databaseMocks.rows.set("x_collection_batch_sources", [{
      batch_id: "batch-late",
      source_id: "source-a",
      source_display_name: "Alpha",
      x_sync_task_id: "task-late",
      settlement_status: "excluded",
      exclusion_code: "settlement_deadline_exceeded",
    }, {
      batch_id: "batch-normal",
      source_id: "source-b",
      source_display_name: "Beta",
      x_sync_task_id: "task-normal",
      settlement_status: "included",
    }, {
      batch_id: "batch-queued",
      source_id: "source-c",
      source_display_name: "Gamma",
      x_sync_task_id: "task-queued",
      settlement_status: "pending",
    }, {
      batch_id: "batch-gap",
      source_id: "source-d",
      source_display_name: "Delta",
      x_sync_task_id: "task-gap",
      settlement_status: "excluded",
      exclusion_code: "settlement_deadline_exceeded",
    }]);
    databaseMocks.rows.set("sync_tasks", [
      { id: "task-late", source_id: "source-a", status: "succeeded", collection_batch_id: "batch-late" },
      { id: "task-normal", source_id: "source-b", status: "succeeded", collection_batch_id: "batch-normal" },
      { id: "task-queued", source_id: "source-c", status: "queued", collection_batch_id: "batch-queued" },
      { id: "task-gap", source_id: "source-d", status: "failed", collection_batch_id: "batch-gap" },
    ]);
    databaseMocks.rows.set("task_attempts", []);
    databaseMocks.rows.set("x_collection_gaps", [{
      source_id: "source-a",
      natural_date: "2099-01-03",
      window_start_at: "2099-01-03T04:00:00.000Z",
      window_end_at: "2099-01-03T08:00:00.000Z",
      failed_task_id: "task-late-gap",
      failure_class: "timeout",
    }, {
      source_id: "source-d",
      natural_date: "2099-01-03",
      window_start_at: "2099-01-03T04:00:00.000Z",
      window_end_at: "2099-01-03T08:00:00.000Z",
      failed_task_id: "task-gap",
      failure_class: "timeout",
    }]);

    const result = await readXDay();
    const day = result.find((candidate) => candidate.naturalDate === "2099-01-03");
    const late = day?.bloggers.find((blogger) => blogger.source.sourceKey === "alpha");
    const normalIncluded = day?.bloggers.find((blogger) => blogger.source.sourceKey === "beta");
    const queuedWithoutSegment = day?.bloggers.find((blogger) => blogger.source.sourceKey === "gamma");
    const gapOnly = day?.bloggers.find((blogger) => blogger.source.sourceKey === "delta");

    expect(late).toMatchObject({
      lateArrival: true,
      collectionGaps: [{
        startAt: "2099-01-03T04:00:00.000Z",
        endAt: "2099-01-03T08:00:00.000Z",
      }],
      segments: [{ viewpoints: ["迟到但真实持久化的观点"] }],
    });
    expect(day?.judgement.batches).toEqual(expect.arrayContaining([expect.objectContaining({ coverageStatus: null })]));
    expect(normalIncluded?.lateArrival).toBe(false);
    expect(queuedWithoutSegment?.segments).toEqual([]);
    expect(gapOnly).toBeUndefined();
    expect(day?.collectionGaps).toEqual([{
      source: { sourceKey: "delta", displayName: "Delta" },
      gaps: [{
        startAt: "2099-01-03T04:00:00.000Z",
        endAt: "2099-01-03T08:00:00.000Z",
      }],
    }]);
    expect(JSON.stringify(result)).not.toContain("settlement_deadline_exceeded");
    expect(JSON.stringify(result)).not.toContain("task-late");
  });

  it("retains archived history, builds snapshot placeholders, and projects safe revision history", async () => {
    databaseMocks.rows.set("x_collection_gaps", [
      { source_id: "source-a", natural_date: "2099-01-02", window_start_at: "2099-01-02T04:00:00.000Z", window_end_at: "2099-01-02T08:00:00.000Z", failed_task_id: "task-a-gap", failure_class: "opencli_contract" },
      { source_id: "source-b", natural_date: "2099-01-01", window_start_at: "2099-01-01T04:00:00.000Z", window_end_at: "2099-01-01T08:00:00.000Z", failed_task_id: "task-b-gap", failure_class: "timeout" },
    ]);
    const result = await readXDay();
    const serialized = JSON.stringify(result);
    const current = result[0]?.judgement.batches[0];
    const history = current?.revisionHistory[0];

    expect(result.map((day) => day.naturalDate)).toEqual(["2099-01-02", "2099-01-01"]);
    expect(result[0]?.judgement.batches.map((batch) => batch.cutoffAt)).toEqual(["2099-01-02T12:00:00.000Z", "2099-01-02T08:00:00.000Z"]);
    expect(current).toMatchObject({
      revision: 2,
      presentationKind: "v5",
      stockViewpoints: [],
      marketIndustryViewpoints: [],
      strategyMindsetViewpoints: [],
      aiSynthesis: {
        crossBloggerIntegrations: [expect.objectContaining({
          headline: "两位博主都围绕 AI 基础设施展开，但结论侧重点不同。",
          synthesis: "共同点是都把产业链变化视作主线，分歧在于更偏向确认性配置还是等待节奏验证。",
          commonPoints: [expect.objectContaining({
            statement: "两位博主都把 AI 基础设施需求变化视为当前观察主线。",
            displayNames: ["Alpha", "Beta"],
          })],
          conflictPoints: [expect.objectContaining({
            issue: "是否已经进入可以明确加大配置的阶段。",
            positions: [
              expect.objectContaining({ position: "其中一位博主更偏向确认产业链景气并提前布局。", displayNames: ["Alpha"] }),
              expect.objectContaining({ position: "另一位博主仍强调先观察兑现节奏再决定是否扩大仓位。", displayNames: ["Beta"] }),
            ],
          })],
        })],
        aiAssessments: [expect.objectContaining({
          headline: "单一重要博主的市场结构判断仍值得保留。",
          judgement: expect.stringContaining("单博主市场结构判断"),
          importanceReason: "它直接影响后续是否把产业链景气从观察提升为更明确的配置判断。",
          reasoning: "该博主给出的链条约束和节奏判断较完整，因此即使目前只有单一博主支持，仍值得纳入 AI synthesis 的重点观察。",
          keyAssumptions: ["需求兑现仍将按当前节奏推进。"],
          risks: [expect.stringContaining("订单兑现节奏延后")],
          watchVariables: ["订单兑现节奏", "算力链库存变化"],
        })],
      },
      securityIndustryTheses: [expect.objectContaining({
        headline: "两位博主都认为 AI 基础设施链条仍在延续。",
        synthesis: "两位博主都延续看多 AI 基础设施主线，但其中一位更强调可以逐步建立观察仓位。",
        scenarioBranches: [{ condition: "若新增需求继续兑现。", outcome: "产业链景气判断将进一步强化。", uncertainties: [] }],
        attributedActions: [{
          displayName: "Alpha",
          actionIntent: "build_position",
          actionScope: "AI 基础设施链条龙头",
          actionScopeStatus: "specified",
          conditions: ["若新增需求继续兑现。"],
          uncertainties: [],
        }],
        supportingDisplayNames: ["Alpha", "Beta"],
        dissentingDisplayNames: [],
      })],
      marketStructureTheses: [expect.objectContaining({
        headline: "有博主认为当前节奏仍受兑现约束。",
        supportingDisplayNames: ["Alpha"],
        dissentingDisplayNames: [],
      })],
      strategyMindsetTheses: [],
      uncertainties: ["仅基于当日已完成采集的博主窗口，仍可能遗漏尚未纳入的覆盖范围。"],
    });
    expect(history).toMatchObject({
      revision: 1,
      presentationKind: "legacy",
      coverageStatus: "complete",
      stockViewpoints: [{ statement: "stale", supportingDisplayNames: ["Alpha"] }],
      marketIndustryViewpoints: [],
      strategyMindsetViewpoints: [],
    });
    expect(current).toMatchObject({ coverageStatus: "complete", includedSourceCount: 1, noNewSourceCount: 1 });
    expect(result[0]?.judgement.batches[1]).toMatchObject({ coverageStatus: "partial", includedSourceCount: 1, noNewSourceCount: 0, excludedSourceCount: 1, timedOutSourceCount: 1, stockViewpoints: [{ statement: "sixteen", supportingDisplayNames: ["Alpha at sixteen"] }] });
    expect(result[1]?.judgement.batches.map((batch) => batch.status)).toEqual(["judgement_pending", "judgement_failed"]);
    expect(result[0]?.bloggers).toEqual(expect.arrayContaining([
      expect.objectContaining({ source: { sourceKey: "alpha", displayName: "Alpha" }, status: "succeeded", collectionGaps: [{ startAt: "2099-01-02T04:00:00.000Z", endAt: "2099-01-02T08:00:00.000Z" }] }),
      expect.objectContaining({ source: { sourceKey: "beta", displayName: "Beta" }, status: "no_new_messages", collectionGaps: [], segments: [] }),
      expect.objectContaining({ source: { sourceKey: "gamma", displayName: "Gamma archived" }, status: "succeeded", collectionGaps: [], segments: [expect.objectContaining({ viewpoints: ["Archived Gamma viewpoint"] })] }),
    ]));
    expect(result[1]?.bloggers).toEqual(expect.arrayContaining([
      expect.objectContaining({ source: { sourceKey: "alpha", displayName: "Alpha" }, status: "processing", collectionGaps: [], segments: [] }),
      expect.objectContaining({ source: { sourceKey: "gamma", displayName: "Gamma archived" }, status: "partial_failure", collectionGaps: [], timedOut: true, segments: [] }),
    ]));
    expect(result[1]?.collectionGaps).toEqual([{
      source: { sourceKey: "beta", displayName: "Beta" },
      gaps: [{ startAt: "2099-01-01T04:00:00.000Z", endAt: "2099-01-01T08:00:00.000Z" }],
    }]);
    expect(databaseMocks.filters).not.toContainEqual({ table: "sources", field: "enabled", value: true });
    for (const forbidden of [
      "analysis_ids",
      "evidence_post_ids",
      "analysis-2",
      "post-2",
      "provider",
      "task-a-20",
      "task-global-latest",
      "evidence_refs",
      "settlement_deadline_exceeded",
      "integration-01",
      "assessment-01",
      "security-01",
      "market-01",
      "thesis_id",
      "integration_id",
      "assessment_id",
      "related_thesis_ids",
      "source_ids",
      "source-a",
      "source-b",
      "post-alpha@2",
      "post-beta@2",
      "post-alpha-2@2",
      "post-alpha",
      "post-beta",
      "post-alpha-2",
      "analysis-17",
      "BATCH-42",
      "run-9",
      "SEGMENT-3",
      "thesis-99",
      "source-hidden",
      "post-hidden@2",
      "integration-hidden",
      "assessment-hidden",
      "batch-42",
      "run-9",
      "segment-3",
      "source-hidden",
      "post-hidden@2",
    ]) expect(serialized).not.toContain(forbidden);
  });

  it("publishes judgement coverage only when a persisted version proves it", async () => {
    databaseMocks.rows.set("x_daily_viewpoint_segments", []);
    databaseMocks.rows.set("x_collection_batches", [
      { id: "batch-pending", natural_date: "2099-01-01", cutoff_at: "2099-01-01T12:00:00.000Z", status: "judgement_pending" },
      { id: "batch-failed", natural_date: "2099-01-01", cutoff_at: "2099-01-01T08:00:00.000Z", status: "judgement_failed" },
      { id: "batch-no-new", natural_date: "2099-01-01", cutoff_at: "2099-01-01T04:00:00.000Z", status: "succeeded" },
    ]);
    databaseMocks.rows.set("x_daily_judgement_versions", [{
      batch_id: "batch-no-new", revision: 1, coverage_status: "no_new_information",
      schema_version: "v4-x-cross-blogger", prompt_version: "v4-x-cross-blogger-1",
      output: { stock_viewpoints: [], market_industry_viewpoints: [], uncertainties: [] },
    }]);
    databaseMocks.rows.set("x_collection_batch_sources", [
      { batch_id: "batch-pending", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: "task-pending", settlement_status: "pending" },
      { batch_id: "batch-failed", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: "task-failed", settlement_status: "excluded" },
      { batch_id: "batch-no-new", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: "task-no-new", settlement_status: "no_new_information" },
    ]);
    databaseMocks.rows.set("sync_tasks", [
      { id: "task-pending", status: "queued" },
      { id: "task-failed", status: "failed" },
      { id: "task-no-new", status: "succeeded" },
    ]);
    databaseMocks.rows.set("task_attempts", [{ task_id: "task-no-new", result: { no_new_data: true }, updated_at: "2099-01-01T04:01:00.000Z" }]);

    const result = await readXDay();
    const batches = result[0]?.judgement.batches ?? [];

    expect(batches.map(({ status, revision, coverageStatus }) => ({ status, revision, coverageStatus }))).toEqual([
      { status: "judgement_pending", revision: 0, coverageStatus: null },
      { status: "judgement_failed", revision: 0, coverageStatus: null },
      { status: "succeeded", revision: 1, coverageStatus: "no_new_information" },
    ]);
  });

  it("fails closed for unknown or mismatched judgement schema and prompt pairs", async () => {
    const existingVersions = databaseMocks.rows.get("x_daily_judgement_versions") ?? [];
    const retainedVersions = existingVersions.filter((row) => row && typeof row === "object" && (row as Record<string, unknown>).batch_id !== "batch-20");
    const unsafeOutput = (marker: string) => ({
      stock_viewpoints: [{ statement: marker, supporting_source_ids: ["source-a"], dissenting_source_ids: [], uncertainties: [] }],
      market_industry_viewpoints: [],
      strategy_mindset_viewpoints: [],
      ai_synthesis: {
        cross_blogger_integrations: [{ headline: marker, synthesis: marker, common_points: [], conflict_points: [], uncertainties: [] }],
        ai_assessments: [],
      },
      security_industry_theses: [{ headline: marker, synthesis: marker, scenario_branches: [], attributed_actions: [], supporting_source_ids: [], dissenting_source_ids: [], uncertainties: [] }],
      market_structure_theses: [],
      strategy_mindset_theses: [],
      uncertainties: [marker],
    });
    databaseMocks.rows.set("x_daily_judgement_versions", [
      ...retainedVersions,
      { batch_id: "batch-20", revision: 3, coverage_status: "complete", schema_version: "v6-x-cross-blogger", prompt_version: "v6-x-cross-blogger-1", output: unsafeOutput("UNKNOWN_SCHEMA_V5_CONTENT") },
      { batch_id: "batch-20", revision: 2, coverage_status: "complete", schema_version: "v5-x-cross-blogger", prompt_version: "v5-x-cross-blogger-mismatch", output: unsafeOutput("MISMATCHED_PROMPT_V5_CONTENT") },
    ]);

    const result = await readXDay();
    const current = result[0]?.judgement.batches[0];
    const history = current?.revisionHistory[0];

    expect(current).toMatchObject({ revision: 3, presentationKind: "legacy", stockViewpoints: [], marketIndustryViewpoints: [], strategyMindsetViewpoints: [], uncertainties: [] });
    expect(history).toMatchObject({ revision: 2, presentationKind: "legacy", stockViewpoints: [], marketIndustryViewpoints: [], strategyMindsetViewpoints: [], uncertainties: [] });
    expect(current).not.toHaveProperty("aiSynthesis");
    expect(current).not.toHaveProperty("securityIndustryTheses");
    expect(history).not.toHaveProperty("aiSynthesis");
    expect(history).not.toHaveProperty("securityIndustryTheses");
    expect(JSON.stringify(result)).not.toContain("UNKNOWN_SCHEMA_V5_CONTENT");
    expect(JSON.stringify(result)).not.toContain("MISMATCHED_PROMPT_V5_CONTENT");
  });

  it("keeps the original judgement failure and projects only its succeeded one-off v3 recovery", async () => {
    databaseMocks.rows.set("sources", [{ id: "source-a", source_key: "alpha", display_name: "Alpha", enabled: true }]);
    databaseMocks.rows.set("x_daily_viewpoint_segments", []);
    databaseMocks.rows.set("x_collection_batches", [{ id: "batch-failed", natural_date: "2099-01-01", cutoff_at: "2099-01-01T08:00:00.000Z", status: "judgement_failed" }]);
    databaseMocks.rows.set("x_daily_judgement_versions", []);
    databaseMocks.rows.set("x_collection_batch_sources", [{ batch_id: "batch-failed", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: null, settlement_status: "included", exclusion_code: null }]);
    databaseMocks.rows.set("sync_tasks", []);
    databaseMocks.rows.set("task_attempts", []);
    databaseMocks.rows.set("x_v3_verification_replays", [
      { id: "replay-failed", source_batch_id: "batch-failed", status: "failed" },
    ]);
    databaseMocks.rows.set("x_v3_verification_acceptance_runs", [
      { id: "acceptance-succeeded", parent_replay_id: "replay-failed", status: "succeeded" },
    ]);
    databaseMocks.rows.set("x_v3_verification_acceptance_versions", [
      { acceptance_run_id: "acceptance-succeeded", output: { security_industry_viewpoints: [{ statement: "恢复后的 v3 判断 analysis-17 batch-42", action_intent: "watch", action_scope: "测试标的 run-9", conditions: ["条件 segment-3"], supporting_source_ids: ["source-a"], dissenting_source_ids: [], analysis_ids: ["private-analysis"], evidence_post_ids: ["private-evidence"], uncertainties: ["legacy source-hidden"] }], market_structure_viewpoints: [], strategy_mindset_viewpoints: [], uncertainties: ["recovery post-hidden@2"] }, schema_version: "v3-x-cross-blogger", prompt_version: "v3-x-cross-blogger-1" },
    ]);

    const result = await readXDay();
    const batch = result[0]?.judgement.batches[0] as unknown as { status: string; verificationRecovery?: { stockViewpoints: Array<{ statement: string }> } };

    expect(batch.status).toBe("judgement_failed");
    expect(batch.verificationRecovery?.stockViewpoints).toEqual([{ statement: "恢复后的 v3 判断", actionIntent: "watch", actionScope: "测试标的", actionScopeStatus: "specified", conditions: ["条件"], supportingDisplayNames: ["Alpha"], dissentingDisplayNames: [], uncertainties: ["legacy"] }]);
    expect(batch.verificationRecovery?.uncertainties).toEqual(["recovery"]);
    expect(JSON.stringify(batch)).not.toContain("acceptance-succeeded");
    expect(JSON.stringify(batch)).not.toContain("private-analysis");
    expect(JSON.stringify(batch)).not.toContain("private-evidence");
  });

  it("projects only the referenced v3 analysis and categorized v3 window output", async () => {
    databaseMocks.rows.set("x_daily_viewpoint_segments", [{
      source_id: "source-a", natural_date: "2099-01-03", occurred_from_at: "2099-01-03T08:00:00.000Z", occurred_through_at: "2099-01-03T09:00:00.000Z",
      schema_version: "v3-x-window", prompt_version: "v3-x-window-1",
      segment_output: { schema_version: "v3-x-window", security_industry_viewpoints: [{ statement: "窗口 v3 观点", action_intent: "buy", action_scope: "测试标的", conditions: ["条件"], uncertainties: [] }], market_structure_viewpoints: [], strategy_mindset_viewpoints: [], uncertainties: ["窗口不确定性"] },
      window_viewpoints: [], post_analysis_refs: [{ post_id: "post-1", analysis_version: 2 }],
    }]);
    databaseMocks.rows.set("canonical_messages", [{ id: "canonical-1", source_id: "source-a", external_message_id: "post-1", occurred_at: "2099-01-03T08:30:00.000Z" }]);
    databaseMocks.rows.set("x_post_analyses", [
      { canonical_message_id: "canonical-1", analysis_version: 1, blogger_viewpoint: "旧版本不得显示", arguments: [], quoted_post_viewpoint: null, uncertainties: [] },
      { canonical_message_id: "canonical-1", analysis_version: 2, schema_version: "v3-x-post-analysis", prompt_version: "v3-x-post-analysis-1", analysis_output: { post_id: "post-1", blogger_viewpoint: "v3 单帖观点", action_intent: "buy", action_scope: "测试标的", conditions: ["条件"], evidence_post_ids: ["post-1"] }, blogger_viewpoint: "投影", arguments: ["论据"], quoted_post_viewpoint: null, uncertainties: [] },
    ]);
    databaseMocks.rows.set("x_post_contexts", [{ canonical_message_id: "canonical-1", post_url: "https://x.test/post/1", post_type: "quote" }]);

    const result = await readXDay();
    const segment = result.find((day) => day.naturalDate === "2099-01-03")?.bloggers[0]?.segments[0];

    expect(segment).toMatchObject({ securityIndustryViewpoints: [{ statement: "窗口 v3 观点", actionIntent: "buy", actionScope: "测试标的" }], analyses: [{ bloggerViewpoint: "v3 单帖观点", actionIntent: "buy", postLink: "https://x.test/post/1", postedAt: "2099-01-03T08:30:00.000Z", postType: "quote" }] });
    expect(databaseMocks.selects).toContainEqual({ table: "canonical_messages", columns: "id,source_id,external_message_id,occurred_at" });
    expect(databaseMocks.selects).toContainEqual({ table: "x_post_contexts", columns: "canonical_message_id,post_url,post_type" });
    expect(JSON.stringify(segment)).not.toContain("post-1@2");
    expect(JSON.stringify(segment)).not.toContain("旧版本不得显示");
  });

  it("selects no unused internal evidence or segment identity fields", async () => {
    await readXDay();

    const projections = databaseMocks.selects.map((select) => `${select.table}:${select.columns}`).join("|");
    expect(projections).not.toContain("evidence_refs");
    expect(projections).not.toContain("x_daily_viewpoint_segments:id,");
    expect(databaseMocks.selects).toContainEqual({ table: "x_daily_judgement_versions", columns: "batch_id,revision,coverage_status,output,schema_version,prompt_version" });
    expect(databaseMocks.selects).toContainEqual({ table: "sync_tasks", columns: "id,status,collection_batch_id" });
    expect(databaseMocks.selects).toContainEqual({ table: "task_attempts", columns: "task_id,result,updated_at" });
    expect(databaseMocks.selects).toContainEqual({ table: "x_collection_gaps", columns: "source_id,natural_date,window_start_at,window_end_at" });
    expect(projections).not.toContain("failed_task_id");
    expect(projections).not.toContain("failure_class");
    expect(projections).not.toContain("skipped_at");
    expect(databaseMocks.ins).toContainEqual(expect.objectContaining({ table: "sync_tasks", field: "id", values: expect.arrayContaining(["task-a-20", "task-b-20"]) }));
  });

  it("bounds every snapshot task lookup and merges statuses across hundreds of task IDs", async () => {
    const count = 235;
    databaseMocks.rows.set("sources", Array.from({ length: count }, (_, index) => ({
      id: `bulk-source-${index}`, source_key: `bulk-${index}`, display_name: `Bulk ${index}`,
    })));
    databaseMocks.rows.set("x_daily_viewpoint_segments", []);
    databaseMocks.rows.set("x_collection_batches", [{
      id: "bulk-batch", natural_date: "2099-01-05", cutoff_at: "2099-01-05T12:00:00.000Z", status: "judgement_pending",
    }]);
    databaseMocks.rows.set("x_daily_judgement_versions", []);
    databaseMocks.rows.set("x_collection_batch_sources", Array.from({ length: count }, (_, index) => ({
      batch_id: "bulk-batch", source_id: `bulk-source-${index}`, source_display_name: `Bulk ${index}`,
      x_sync_task_id: `bulk-task-${index}`, settlement_status: "pending",
    })));
    databaseMocks.rows.set("sync_tasks", Array.from({ length: count }, (_, index) => ({
      id: `bulk-task-${index}`,
      status: index === 0 || index === 234 ? "succeeded" : index === 101 ? "failed" : "queued",
    })));
    databaseMocks.rows.set("task_attempts", [{
      task_id: "bulk-task-0", result: { no_new_data: true }, updated_at: "2099-01-05T12:01:00.000Z",
    }]);

    const result = await readXDay();
    const bloggers = result[0]?.bloggers ?? [];
    const statusFor = (sourceKey: string) => bloggers.find((blogger) => blogger.source.sourceKey === sourceKey)?.status;
    const taskLookups = databaseMocks.ins.filter((lookup) => lookup.table === "sync_tasks" && lookup.field === "id");
    const attemptLookups = databaseMocks.ins.filter((lookup) => lookup.table === "task_attempts" && lookup.field === "task_id");

    expect(bloggers).toHaveLength(235);
    expect(statusFor("bulk-0")).toBe("no_new_messages");
    expect(statusFor("bulk-101")).toBe("failed");
    expect(statusFor("bulk-234")).toBe("succeeded");
    for (const lookups of [taskLookups, attemptLookups]) {
      expect(lookups.length).toBeGreaterThan(1);
      expect(lookups.every((lookup) => lookup.values.length <= 100)).toBe(true);
      const taskIds = lookups.flatMap((lookup) => lookup.values);
      expect(taskIds).toHaveLength(count);
      expect(new Set(taskIds).size).toBe(count);
    }
  });

  it("bounds every high-cardinality X lookup while preserving merged content and ordering", async () => {
    const count = 235;
    const padded = (index: number) => String(index).padStart(3, "0");
    databaseMocks.rows.set("sources", Array.from({ length: count }, (_, index) => ({
      id: `wide-source-${index}`, source_key: `wide-${index}`, display_name: `Wide ${padded(index)}`,
    })));
    databaseMocks.rows.set("x_daily_viewpoint_segments", Array.from({ length: count }, (_, index) => ({
      source_id: `wide-source-${index}`, natural_date: "2099-01-06",
      occurred_from_at: `2099-01-06T10:00:00.${padded(index)}Z`,
      occurred_through_at: `2099-01-06T10:00:00.${padded(index)}Z`,
      window_viewpoints: [`window ${index}`], post_analysis_refs: [{ post_id: `external-${index}` }],
    })));
    databaseMocks.rows.set("canonical_messages", Array.from({ length: count }, (_, index) => ({
      id: `canonical-${index}`, source_id: `wide-source-${index}`, external_message_id: `external-${index}`,
    })));
    databaseMocks.rows.set("x_post_analyses", Array.from({ length: count }, (_, index) => ({
      canonical_message_id: `canonical-${index}`, analysis_version: 1, blogger_viewpoint: `analysis text ${index}`,
      arguments: [`argument-${index}`], quoted_post_viewpoint: null, uncertainties: [],
    })));
    databaseMocks.rows.set("x_post_contexts", Array.from({ length: count }, (_, index) => ({
      canonical_message_id: `canonical-${index}`, post_url: `https://x.test/post/${index}`,
    })));
    databaseMocks.rows.set("x_collection_batches", Array.from({ length: count }, (_, index) => ({
      id: `wide-batch-${index}`, natural_date: "2099-01-06",
      cutoff_at: `2099-01-06T12:00:00.${padded(index)}Z`, status: "succeeded",
    })));
    databaseMocks.rows.set("x_daily_judgement_versions", Array.from({ length: count }, (_, index) => ({
      batch_id: `wide-batch-${index}`, revision: 1, coverage_status: "complete",
      schema_version: "v4-x-cross-blogger", prompt_version: "v4-x-cross-blogger-1",
      output: { stock_viewpoints: [{ statement: `judgement-${index}`, supporting_source_ids: [`wide-source-${index}`], dissenting_source_ids: [], uncertainties: [] }], market_industry_viewpoints: [], uncertainties: [] },
    })));
    databaseMocks.rows.set("x_collection_batch_sources", Array.from({ length: count }, (_, index) => ({
      batch_id: `wide-batch-${index}`, source_id: `wide-source-${index}`, source_display_name: `Snapshot ${padded(index)}`,
      x_sync_task_id: `wide-task-${index}`, settlement_status: "included",
    })));
    databaseMocks.rows.set("sync_tasks", Array.from({ length: count }, (_, index) => ({
      id: `wide-task-${index}`, status: "succeeded",
    })));
    databaseMocks.rows.set("task_attempts", Array.from({ length: count }, (_, index) => ({
      task_id: `wide-task-${index}`, result: { no_new_data: false }, updated_at: `2099-01-06T12:01:00.${padded(index)}Z`,
    })));

    const result = await readXDay();
    const day = result[0];
    const lookupKeys = [
      "x_daily_viewpoint_segments:source_id",
      "canonical_messages:source_id",
      "canonical_messages:external_message_id",
      "x_post_analyses:canonical_message_id",
      "x_post_contexts:canonical_message_id",
      "x_daily_judgement_versions:batch_id",
      "x_collection_batch_sources:batch_id",
      "sync_tasks:id",
      "task_attempts:task_id",
    ];

    expect(day?.bloggers).toHaveLength(count);
    expect(day?.bloggers[0]).toMatchObject({
      source: { sourceKey: "wide-0", displayName: "Snapshot 000" },
      segments: [{ viewpoints: ["window 0"], analyses: [{ postLink: "https://x.test/post/0", bloggerViewpoint: "analysis text 0" }] }],
    });
    expect(day?.bloggers[234]).toMatchObject({
      source: { sourceKey: "wide-234", displayName: "Snapshot 234" },
      segments: [{ viewpoints: ["window 234"], analyses: [{ postLink: "https://x.test/post/234", bloggerViewpoint: "analysis text 234" }] }],
    });
    expect(day?.judgement.batches).toHaveLength(count);
    expect(day?.judgement.batches[0]).toMatchObject({ cutoffAt: "2099-01-06T12:00:00.234Z", stockViewpoints: [{ statement: "judgement-234", supportingDisplayNames: ["Snapshot 234"] }] });
    expect(day?.judgement.batches[234]).toMatchObject({ cutoffAt: "2099-01-06T12:00:00.000Z", stockViewpoints: [{ statement: "judgement-0", supportingDisplayNames: ["Snapshot 000"] }] });
    expect(databaseMocks.ins.every((lookup) => lookup.values.length <= 100)).toBe(true);
    for (const key of lookupKeys) {
      const [table, field] = key.split(":");
      const lookups = databaseMocks.ins.filter((lookup) => lookup.table === table && lookup.field === field);
      expect(lookups.length, key).toBeGreaterThan(1);
      expect(new Set(lookups.flatMap((lookup) => lookup.values)).size, key).toBe(count);
    }
  });

  it("paginates historical X rows without truncating the Reader projection", async () => {
    const segmentCount = 1005;
    const batchCount = 1005;
    const sourceCount = 100;
    const padded = (index: number) => String(index).padStart(4, "0");
    const naturalDateForBatch = (index: number) => new Date(Date.UTC(2099, 11, 31) - Math.floor(index / 5) * 86_400_000).toISOString().slice(0, 10);
    const cutoffHours = ["20", "16", "12", "08", "00"];
    const sources = Array.from({ length: sourceCount }, (_, index) => ({
      id: `paged-source-${padded(index)}`, source_key: `paged-${padded(index)}`, display_name: `Paged ${padded(index)}`,
    }));
    const batches = Array.from({ length: batchCount }, (_, index) => {
      const naturalDate = naturalDateForBatch(index);
      return {
        id: `paged-batch-${padded(index)}`, natural_date: naturalDate,
        cutoff_at: `${naturalDate}T${cutoffHours[index % 5]}:00:00+08:00`, status: "succeeded",
      };
    });
    const batchSources = batches.flatMap((batch, batchIndex) => (
      sources.slice(0, batchIndex < 11 ? sourceCount : 1).map((source, sourceIndex) => ({
        batch_id: batch.id, source_id: source.id, source_display_name: `Snapshot ${padded(sourceIndex)}`,
        x_sync_task_id: `paged-task-${padded(batchIndex)}-${padded(sourceIndex)}`, settlement_status: "excluded",
      }))
    ));
    databaseMocks.rows.set("sources", sources);
    databaseMocks.rows.set("x_daily_viewpoint_segments", Array.from({ length: segmentCount }, (_, index) => ({
      id: `paged-segment-${padded(index)}`, source_id: "paged-source-0000", natural_date: "2099-12-31",
      occurred_from_at: "2099-12-31T10:00:00.000Z", occurred_through_at: "2099-12-31T10:00:00.000Z",
      window_viewpoints: [`window ${padded(index)}`], post_analysis_refs: [],
    })).reverse());
    databaseMocks.rows.set("x_collection_batches", batches.reverse());
    databaseMocks.rows.set("x_daily_judgement_versions", []);
    databaseMocks.rows.set("x_collection_batch_sources", batchSources.reverse());
    databaseMocks.rows.set("sync_tasks", batchSources.map((row) => ({ id: row.x_sync_task_id, status: "succeeded" })));
    databaseMocks.rows.set("task_attempts", Array.from({ length: 1005 }, (_, index) => ({
      id: `paged-attempt-${padded(index)}`, task_id: "paged-task-0000-0000", attempt: index + 1,
      result: { no_new_data: index === 1004 },
      updated_at: new Date(Date.UTC(2099, 11, 31, 20, 1) + index).toISOString(),
    })).reverse());

    const result = await readXDay();
    const newestDay = result[0];
    const oldestDay = result[result.length - 1];
    const firstBlogger = newestDay?.bloggers.find((blogger) => blogger.source.sourceKey === "paged-0000");
    const allJudgementBatches = result.flatMap((day) => day.judgement.batches);
    const rangesFor = (table: string) => databaseMocks.ranges.filter((range) => range.table === table);

    expect(result).toHaveLength(201);
    expect(newestDay?.naturalDate).toBe("2099-12-31");
    expect(oldestDay?.naturalDate).toBe("2099-06-14");
    expect(newestDay?.bloggers).toHaveLength(100);
    expect(oldestDay?.bloggers).toHaveLength(1);
    expect(firstBlogger?.status).toBe("no_new_messages");
    expect(firstBlogger?.segments).toHaveLength(segmentCount);
    expect(firstBlogger?.segments[0]?.viewpoints).toEqual(["window 0000"]);
    expect(firstBlogger?.segments[1004]?.viewpoints).toEqual(["window 1004"]);
    expect(newestDay?.judgement.batches.map((batch) => batch.cutoffAt)).toEqual([
      "2099-12-31T20:00:00+08:00", "2099-12-31T16:00:00+08:00", "2099-12-31T12:00:00+08:00",
      "2099-12-31T08:00:00+08:00", "2099-12-31T00:00:00+08:00",
    ]);
    expect(oldestDay?.judgement.batches.map((batch) => batch.cutoffAt)).toEqual([
      "2099-06-14T20:00:00+08:00", "2099-06-14T16:00:00+08:00", "2099-06-14T12:00:00+08:00",
      "2099-06-14T08:00:00+08:00", "2099-06-14T00:00:00+08:00",
    ]);
    expect(allJudgementBatches).toHaveLength(batchCount);
    expect(allJudgementBatches.reduce((total, batch) => total + batch.excludedSourceCount, 0)).toBe(2094);
    for (const table of ["x_daily_viewpoint_segments", "x_collection_batches", "x_collection_batch_sources", "task_attempts"]) {
      expect(rangesFor(table), table).toContainEqual({ table, from: 0, to: 999 });
      expect(rangesFor(table), table).toContainEqual({ table, from: 1000, to: 1999 });
    }
    expect(databaseMocks.ranges.every(({ from, to }) => to - from + 1 === 1000)).toBe(true);
  });

  it("keeps the requested source's date placeholders while hiding cross-blogger judgement details", async () => {
    databaseMocks.rows.set("sources", [{ id: "source-a", source_key: "alpha", display_name: "Alpha", enabled: true }]);
    databaseMocks.rows.set("x_daily_viewpoint_segments", [
      { source_id: "source-a", natural_date: "2099-01-02", occurred_from_at: "2099-01-02T08:00:00.000Z", occurred_through_at: "2099-01-02T08:00:00.000Z", window_viewpoints: ["Alpha earlier"], post_analysis_refs: [] },
    ]);
    const result = await readXDay({ sourceKey: "alpha" });

    expect(result).toHaveLength(2);
    expect(result.every((day) => day.judgement.visible === false && day.judgement.batches.length === 0)).toBe(true);
    expect(result.every((day) => day.bloggers.length === 1 && day.bloggers[0]?.source.sourceKey === "alpha")).toBe(true);
    expect(result[1]?.bloggers[0]).toMatchObject({ status: "processing", segments: [] });
  });
});
