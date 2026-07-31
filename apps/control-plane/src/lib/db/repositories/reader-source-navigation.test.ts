import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({ rows: new Map<string, unknown[]>(), filters: [] as Array<{ table: string; field: string; value: unknown }> }));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({
    from(table: string) {
      const query = {
        select: () => query,
        eq: (field: string, value: unknown) => { databaseMocks.filters.push({ table, field, value }); return query; },
        in: () => query,
        order: () => query,
        then: (resolve: (value: { data: unknown[]; error: null }) => unknown) => resolve({ data: databaseMocks.rows.get(table) ?? [], error: null }),
      };
      return query;
    },
  }),
}));

import { readXDay } from "./reader";

describe("X reader date projection", () => {
  beforeEach(() => {
    databaseMocks.rows.clear();
    databaseMocks.filters.length = 0;
    databaseMocks.rows.set("sources", [
      { id: "source-a", source_key: "alpha", display_name: "Alpha" },
      { id: "source-b", source_key: "beta", display_name: "Beta" },
    ]);
    databaseMocks.rows.set("x_daily_viewpoint_segments", [
      { source_id: "source-a", natural_date: "2099-01-02", occurred_from_at: "2099-01-02T08:00:00.000Z", occurred_through_at: "2099-01-02T08:00:00.000Z", window_viewpoints: ["Alpha earlier"], post_analysis_refs: [], evidence_refs: ["internal"] },
      { source_id: "source-b", natural_date: "2099-01-02", occurred_from_at: "2099-01-02T12:00:00.000Z", occurred_through_at: "2099-01-02T12:00:00.000Z", window_viewpoints: ["Beta latest"], post_analysis_refs: [], evidence_refs: [] },
      { source_id: "source-a", natural_date: "2099-01-01", occurred_from_at: "2099-01-01T08:00:00.000Z", occurred_through_at: "2099-01-01T08:00:00.000Z", window_viewpoints: ["Yesterday"], post_analysis_refs: [], evidence_refs: [] },
    ]);
    databaseMocks.rows.set("x_collection_batches", [
      { id: "batch-16", natural_date: "2099-01-02", cutoff_at: "2099-01-02T08:00:00.000Z", status: "succeeded" },
      { id: "batch-20", natural_date: "2099-01-02", cutoff_at: "2099-01-02T12:00:00.000Z", status: "succeeded" },
      { id: "batch-pending", natural_date: "2099-01-01", cutoff_at: "2099-01-01T12:00:00.000Z", status: "judgement_pending" },
      { id: "batch-failed", natural_date: "2099-01-01", cutoff_at: "2099-01-01T08:00:00.000Z", status: "judgement_failed" },
    ]);
    databaseMocks.rows.set("x_daily_judgement_versions", [
      { batch_id: "batch-16", revision: 1, coverage_status: "partial", output: { stock_viewpoints: [], market_industry_viewpoints: [], uncertainties: [] } },
      { batch_id: "batch-20", revision: 1, coverage_status: "complete", output: { stock_viewpoints: [{ statement: "stale", supporting_source_ids: ["source-a"], dissenting_source_ids: [], analysis_ids: ["analysis-1"], evidence_post_ids: ["post-1"], uncertainties: [] }], market_industry_viewpoints: [], uncertainties: [] } },
      { batch_id: "batch-20", revision: 2, coverage_status: "complete", output: { stock_viewpoints: [{ statement: "latest", supporting_source_ids: ["source-b"], dissenting_source_ids: ["source-a"], analysis_ids: ["analysis-2"], evidence_post_ids: ["post-2"], uncertainties: ["uncertain"] }], market_industry_viewpoints: [], uncertainties: [] } },
    ]);
    databaseMocks.rows.set("x_collection_batch_sources", [
      { batch_id: "batch-16", source_id: "source-a", source_display_name: "Alpha", settlement_status: "excluded" },
      { batch_id: "batch-20", source_id: "source-a", source_display_name: "Alpha", settlement_status: "included" },
      { batch_id: "batch-20", source_id: "source-b", source_display_name: "Beta", settlement_status: "included" },
    ]);
    databaseMocks.rows.set("sync_tasks", []);
  });

  it("returns newest-first date blocks and only a safe latest judgement revision", async () => {
    const result = await readXDay();
    const serialized = JSON.stringify(result);

    expect(result.map((day) => day.naturalDate)).toEqual(["2099-01-02", "2099-01-01"]);
    expect(result[0]?.judgement.batches.map((batch) => batch.cutoffAt)).toEqual(["2099-01-02T12:00:00.000Z", "2099-01-02T08:00:00.000Z"]);
    expect(result[0]?.judgement.batches[0]).toMatchObject({ revision: 2, stockViewpoints: [{ statement: "latest", supportingDisplayNames: ["Beta"], dissentingDisplayNames: ["Alpha"] }] });
    expect(result[0]?.judgement.batches[1]).toMatchObject({ coverageStatus: "partial", excludedSourceCount: 1 });
    expect(result[1]?.judgement.batches.map((batch) => batch.status)).toEqual(["judgement_pending", "judgement_failed"]);
    for (const forbidden of ["analysis_ids", "evidence_post_ids", "analysis-2", "post-2", "provider", "task", "evidence_refs"]) expect(serialized).not.toContain(forbidden);
  });

  it("hides cross-blogger judgement details when a single source is requested", async () => {
    const result = await readXDay({ sourceKey: "alpha" });

    expect(result).toHaveLength(2);
    expect(result.every((day) => day.judgement.visible === false && day.judgement.batches.length === 0)).toBe(true);
  });
});
