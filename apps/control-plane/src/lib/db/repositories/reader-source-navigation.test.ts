import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  rows: new Map<string, unknown[]>(),
  filters: [] as Array<{ table: string; field: string; value: unknown }>,
  ins: [] as Array<{ table: string; field: string; values: unknown[] }>,
  selects: [] as Array<{ table: string; columns: string }>,
}));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({
    from(table: string) {
      const queryIns: Array<{ field: string; values: unknown[] }> = [];
      const query = {
        select: (columns: string) => { databaseMocks.selects.push({ table, columns }); return query; },
        eq: (field: string, value: unknown) => { databaseMocks.filters.push({ table, field, value }); return query; },
        in: (field: string, values: unknown[]) => { databaseMocks.ins.push({ table, field, values }); queryIns.push({ field, values }); return query; },
        order: () => query,
        then: (resolve: (value: { data: unknown[]; error: null }) => unknown) => {
          const rows = (databaseMocks.rows.get(table) ?? []).filter((row) => queryIns.every(({ field, values }) => (
            row && typeof row === "object" && values.includes((row as Record<string, unknown>)[field])
          )));
          return resolve({ data: rows, error: null });
        },
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
    databaseMocks.ins.length = 0;
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
      { batch_id: "batch-16", revision: 1, coverage_status: "partial", output: { stock_viewpoints: [{ statement: "sixteen", supporting_source_ids: ["source-a"], dissenting_source_ids: [], analysis_ids: ["analysis-16"], evidence_post_ids: ["post-16"], uncertainties: [] }], market_industry_viewpoints: [], uncertainties: [] } },
      { batch_id: "batch-20", revision: 1, coverage_status: "complete", output: { stock_viewpoints: [{ statement: "stale", supporting_source_ids: ["source-a"], dissenting_source_ids: [], analysis_ids: ["analysis-1"], evidence_post_ids: ["post-1"], uncertainties: [] }], market_industry_viewpoints: [], uncertainties: [] } },
      { batch_id: "batch-20", revision: 2, coverage_status: "complete", output: { stock_viewpoints: [{ statement: "latest", supporting_source_ids: ["source-b"], dissenting_source_ids: ["source-a"], analysis_ids: ["analysis-2"], evidence_post_ids: ["post-2"], uncertainties: ["uncertain"] }], market_industry_viewpoints: [], uncertainties: [] } },
    ]);
    databaseMocks.rows.set("x_collection_batch_sources", [
      { batch_id: "batch-16", source_id: "source-a", source_display_name: "Alpha at sixteen", x_sync_task_id: "task-a-16", settlement_status: "excluded" },
      { batch_id: "batch-16", source_id: "source-c", source_display_name: "Gamma archived", x_sync_task_id: "task-c-16", settlement_status: "included" },
      { batch_id: "batch-20", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: "task-a-20", settlement_status: "included" },
      { batch_id: "batch-20", source_id: "source-b", source_display_name: "Beta", x_sync_task_id: "task-b-20", settlement_status: "no_new_information" },
      { batch_id: "batch-pending", source_id: "source-a", source_display_name: "Alpha", x_sync_task_id: "task-a-pending", settlement_status: "pending" },
      { batch_id: "batch-pending", source_id: "source-b", source_display_name: "Beta", x_sync_task_id: "task-b-failed", settlement_status: "excluded" },
      { batch_id: "batch-pending", source_id: "source-c", source_display_name: "Gamma archived", x_sync_task_id: "task-c-delayed", settlement_status: "excluded" },
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

  it("retains archived history, builds snapshot placeholders, and projects safe revision history", async () => {
    const result = await readXDay();
    const serialized = JSON.stringify(result);

    expect(result.map((day) => day.naturalDate)).toEqual(["2099-01-02", "2099-01-01"]);
    expect(result[0]?.judgement.batches.map((batch) => batch.cutoffAt)).toEqual(["2099-01-02T12:00:00.000Z", "2099-01-02T08:00:00.000Z"]);
    expect(result[0]?.judgement.batches[0]).toMatchObject({
      revision: 2,
      stockViewpoints: [{ statement: "latest", supportingDisplayNames: ["Beta"], dissentingDisplayNames: ["Alpha"] }],
      revisionHistory: [{ revision: 1, coverageStatus: "complete", stockViewpoints: [{ statement: "stale", supportingDisplayNames: ["Alpha"] }] }],
    });
    expect(result[0]?.judgement.batches[1]).toMatchObject({ coverageStatus: "partial", excludedSourceCount: 1, stockViewpoints: [{ statement: "sixteen", supportingDisplayNames: ["Alpha at sixteen"] }] });
    expect(result[1]?.judgement.batches.map((batch) => batch.status)).toEqual(["judgement_pending", "judgement_failed"]);
    expect(result[0]?.bloggers).toEqual(expect.arrayContaining([
      expect.objectContaining({ source: { sourceKey: "alpha", displayName: "Alpha" }, status: "succeeded" }),
      expect.objectContaining({ source: { sourceKey: "beta", displayName: "Beta" }, status: "no_new_messages", segments: [] }),
      expect.objectContaining({ source: { sourceKey: "gamma", displayName: "Gamma archived" }, status: "succeeded", segments: [expect.objectContaining({ viewpoints: ["Archived Gamma viewpoint"] })] }),
    ]));
    expect(result[1]?.bloggers).toEqual(expect.arrayContaining([
      expect.objectContaining({ source: { sourceKey: "alpha", displayName: "Alpha" }, status: "processing", segments: [] }),
      expect.objectContaining({ source: { sourceKey: "beta", displayName: "Beta" }, status: "failed", segments: [] }),
      expect.objectContaining({ source: { sourceKey: "gamma", displayName: "Gamma archived" }, status: "partial_failure", segments: [] }),
    ]));
    expect(databaseMocks.filters).not.toContainEqual({ table: "sources", field: "enabled", value: true });
    for (const forbidden of ["analysis_ids", "evidence_post_ids", "analysis-2", "post-2", "provider", "task-a-20", "task-global-latest", "evidence_refs"]) expect(serialized).not.toContain(forbidden);
  });

  it("selects no unused internal evidence or segment identity fields", async () => {
    await readXDay();

    const projections = databaseMocks.selects.map((select) => `${select.table}:${select.columns}`).join("|");
    expect(projections).not.toContain("evidence_refs");
    expect(projections).not.toContain("x_daily_viewpoint_segments:id,");
    expect(databaseMocks.selects).toContainEqual({ table: "sync_tasks", columns: "id,status" });
    expect(databaseMocks.selects).toContainEqual({ table: "task_attempts", columns: "task_id,result,updated_at" });
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
