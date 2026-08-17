import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const readerMocks = vi.hoisted(() => ({ readXDay: vi.fn() }));

vi.mock("../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../lib/db/repositories/reader", () => readerMocks);

import { GET } from "./route";

const rawContentSentinel = "FORBIDDEN_RAW_X_CONTENT_SENTINEL";
const localPathSentinel = "/private/reader-unsafe/evidence.json";
const v5FieldNames = ["aiSynthesis", "securityIndustryTheses", "marketStructureTheses", "strategyMindsetTheses"];

function v5LeakPayload(marker: string) {
  return {
    aiSynthesis: {
      crossBloggerIntegrations: [{ headline: marker, synthesis: marker, commonPoints: [], conflictPoints: [], uncertainties: [] }],
      aiAssessments: [],
    },
    securityIndustryTheses: [{ headline: marker, synthesis: marker, scenarioBranches: [], attributedActions: [], supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties: [] }],
    marketStructureTheses: [],
    strategyMindsetTheses: [],
  };
}

describe("GET /api/reader/x", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "ordinary-user", role: "user" });
    readerMocks.readXDay.mockResolvedValue([{
      naturalDate: "2099-01-02",
      provider: "must not escape",
      prompt: "must not escape",
      task: "must not escape",
      rawContent: rawContentSentinel,
      execution_health_status: "unavailable",
      execution_failure_category: "configuration_error",
      collectionGaps: [{
        source: { sourceKey: "gap-only", displayName: "Gap Only" },
        gaps: [{ startAt: "2099-01-02T04:00:00.000Z", endAt: "2099-01-02T08:00:00.000Z" }],
      }],
      judgement: {
        visible: true,
        batches: [{
          cutoffAt: "2099-01-02T12:00:00.000Z",
          coverageStatus: "complete",
          status: "succeeded",
          revision: 2,
          presentationKind: "v5",
          provider: "must not escape",
          prompt: "must not escape",
          task: "must not escape",
          thesis_id: "security-01",
          integration_id: "integration-01",
          assessment_id: "assessment-01",
          source_ids: ["source-alpha", "source-beta"],
          related_thesis_ids: ["market-01"],
          analysis_ids: ["private-analysis-id"],
          evidence_post_ids: ["private-post-id"],
          analysis_id: "analysis-17",
          batch_id: "BATCH-42",
          run_id: "run-9",
          segment_id: "SEGMENT-3",
          local_path: localPathSentinel,
          raw_content: rawContentSentinel,
          aiSynthesis: {
            crossBloggerIntegrations: [{
              headline: "Safe integration",
              synthesis: "Readable synthesis",
              commonPoints: [{
                statement: "Readable common point",
                displayNames: ["Alpha", "Beta", { source_id: "injected-source-id", unknown: "must drop" }],
                source_ids: ["source-alpha", "source-beta"],
                related_thesis_ids: ["security-01", "market-01"],
              }],
              conflictPoints: [{
                issue: "Readable conflict issue",
                positions: [{
                  position: "Readable Alpha position",
                  displayNames: ["Alpha", { evidence_post_id: "injected-evidence-id", unknown: "must drop" }],
                  source_ids: ["source-alpha"],
                  related_thesis_ids: ["security-01"],
                }],
              }],
              related_thesis_ids: ["security-01", "market-01"],
              integration_id: "integration-01",
              analysis_id: "analysis-17",
              batch_id: "BATCH-42",
              run_id: "run-9",
              segment_id: "SEGMENT-3",
              uncertainties: [],
            }, { integration_id: "injected-integration-id", unknown: "must drop" }],
            aiAssessments: [{
              headline: "Safe assessment",
              judgement: "Readable judgement",
              importanceReason: "Readable reason",
              reasoning: "Readable reasoning",
              keyAssumptions: [],
              risks: [],
              watchVariables: [],
              uncertainties: [],
              assessment_id: "assessment-01",
              related_thesis_ids: ["market-01"],
            }, { assessment_id: "injected-assessment-id", unknown: "must drop" }],
          },
          securityIndustryTheses: [{
            headline: "Safe thesis",
            synthesis: "Readable thesis synthesis",
            scenarioBranches: [{ condition: "Readable condition", outcome: "Readable outcome", uncertainties: [{ thesis_id: "injected-thesis-id" }, "Readable branch uncertainty"], analysis_ids: ["private-analysis-id"], evidence_post_ids: ["private-post-id"] }, { thesis_id: "injected-nested-thesis-id" }],
            attributedActions: [{ displayName: "Alpha", actionIntent: "watch", actionScope: "Readable scope", actionScopeStatus: "specified", conditions: [{ analysis_id: "injected-analysis-id" }, "Readable action condition"], uncertainties: [], source_id: "source-alpha", analysis_ids: ["private-analysis-id"], evidence_post_ids: ["private-post-id"] }, { assessment_id: "injected-nested-assessment-id" }],
            supportingDisplayNames: ["Alpha", { source_id: "injected-source-id", unknown: "must drop" }],
            dissentingDisplayNames: [],
            uncertainties: [{ evidence_post_id: "injected-evidence-id" }, "Readable thesis uncertainty"],
            thesis_id: "security-01",
          }],
          marketStructureTheses: [{
            headline: "Safe market thesis",
            synthesis: "Readable market thesis synthesis",
            scenarioBranches: [],
            attributedActions: [],
            supportingDisplayNames: ["Beta"],
            dissentingDisplayNames: [],
            uncertainties: [],
            thesis_id: "market-01",
          }],
          strategyMindsetTheses: [],
          stockViewpoints: [{
            statement: "Only the latest safe judgement is visible.",
            supportingDisplayNames: ["Beta"],
            dissentingDisplayNames: ["Alpha"],
            uncertainties: [],
            analysis_ids: ["private-analysis-id"],
            evidence_post_ids: ["private-post-id"],
          }],
          marketIndustryViewpoints: [],
          uncertainties: [],
          excludedSourceCount: 0,
          revisionHistory: [{
            revision: 1,
            coverageStatus: "partial",
            presentationKind: "legacy",
            stockViewpoints: [{
              statement: "Safe prior revision.",
              conditions: [{ evidence_post_id: "injected-history-evidence-id" }, "Prior condition"],
              supportingDisplayNames: ["Alpha", { source_id: "injected-history-source-id" }],
              dissentingDisplayNames: [],
              uncertainties: [{ analysis_id: "injected-history-analysis-id" }, "Earlier uncertainty"],
              analysis_ids: ["private-prior-analysis-id"],
              analysis_id: "analysis-17",
              batch_id: "batch-42",
              run_id: "run-9",
              segment_id: "segment-3",
              source_id: "source-hidden",
              raw_content: rawContentSentinel,
            }],
            marketIndustryViewpoints: [],
            uncertainties: [],
            provider: "must not escape",
            input_snapshot: { raw_content: rawContentSentinel },
          }],
        }],
      },
      bloggers: [{
        source: { sourceKey: "alpha", displayName: "Alpha", raw_content: rawContentSentinel },
        status: "succeeded",
        timedOut: true,
        lateArrival: true,
        collectionGaps: [{ startAt: "2099-01-02T04:00:00.000Z", endAt: "2099-01-02T08:00:00.000Z" }],
        segments: [{
          occurredFromAt: "2099-01-02T08:00:00.000Z",
          occurredThroughAt: "2099-01-02T12:00:00.000Z",
          viewpoints: ["Safe viewpoint"],
          uncertainties: [],
          local_path: localPathSentinel,
          analyses: [{
            postLink: "https://x.com/alpha/status/1",
            bloggerViewpoint: "Safe analysis",
            postedAt: "2099-01-02T08:30:00.000Z",
            postType: "quote",
            arguments: ["Safe argument"],
            quotedPostViewpoint: null,
            uncertainties: [],
            raw_content: rawContentSentinel,
            provider: "must not escape",
          }],
        }],
      }],
    }]);
  });

  it("returns the Reader-safe DTO for an ordinary user without internal payload fields", async () => {
    const response = await GET(new Request("http://localhost/api/reader/x?source=all&date=all"));
    const body = await response.json();
    const serialized = JSON.stringify(body);

    expect(response.status).toBe(200);
    expect(body).toEqual({ status: "ok", days: expect.arrayContaining([
      expect.objectContaining({
        naturalDate: "2099-01-02",
        judgement: expect.objectContaining({ batches: [expect.objectContaining({
          revision: 2,
          presentationKind: "v5",
          aiSynthesis: {
            crossBloggerIntegrations: [expect.objectContaining({
              headline: "Safe integration",
              synthesis: "Readable synthesis",
              commonPoints: [{ statement: "Readable common point", displayNames: ["Alpha", "Beta"] }],
              conflictPoints: [{
                issue: "Readable conflict issue",
                positions: [{ position: "Readable Alpha position", displayNames: ["Alpha"] }],
              }],
              uncertainties: [],
            })],
            aiAssessments: [expect.objectContaining({
              headline: "Safe assessment",
              judgement: "Readable judgement",
              importanceReason: "Readable reason",
              reasoning: "Readable reasoning",
              keyAssumptions: [],
              risks: [],
              watchVariables: [],
              uncertainties: [],
            })],
          },
          securityIndustryTheses: [{
            headline: "Safe thesis",
            synthesis: "Readable thesis synthesis",
            scenarioBranches: [{ condition: "Readable condition", outcome: "Readable outcome", uncertainties: ["Readable branch uncertainty"] }],
            attributedActions: [{
              displayName: "Alpha",
              actionIntent: "watch",
              actionScope: "Readable scope",
              actionScopeStatus: "specified",
              conditions: ["Readable action condition"],
              uncertainties: [],
            }],
            supportingDisplayNames: ["Alpha"],
            dissentingDisplayNames: [],
            uncertainties: ["Readable thesis uncertainty"],
          }],
          marketStructureTheses: [{
            headline: "Safe market thesis",
            synthesis: "Readable market thesis synthesis",
            scenarioBranches: [],
            attributedActions: [],
            supportingDisplayNames: ["Beta"],
            dissentingDisplayNames: [],
            uncertainties: [],
          }],
          strategyMindsetTheses: [],
          stockViewpoints: [expect.objectContaining({ statement: "Only the latest safe judgement is visible." })],
          revisionHistory: [expect.objectContaining({
            revision: 1,
            coverageStatus: "partial",
            stockViewpoints: [expect.objectContaining({
              statement: "Safe prior revision.",
              conditions: ["Prior condition"],
              supportingDisplayNames: ["Alpha"],
              uncertainties: ["Earlier uncertainty"],
            })],
          })],
        })] }),
        collectionGaps: [{ source: { sourceKey: "gap-only", displayName: "Gap Only" }, gaps: [{ startAt: "2099-01-02T04:00:00.000Z", endAt: "2099-01-02T08:00:00.000Z" }] }],
        bloggers: [expect.objectContaining({
          source: { sourceKey: "alpha", displayName: "Alpha" },
          timedOut: true,
          lateArrival: true,
          collectionGaps: [{ startAt: "2099-01-02T04:00:00.000Z", endAt: "2099-01-02T08:00:00.000Z" }],
          segments: [expect.objectContaining({ analyses: [expect.objectContaining({ postLink: "https://x.com/alpha/status/1", postedAt: "2099-01-02T08:30:00.000Z", postType: "quote" })] })],
        })],
      }),
    ]) });
    expect(readerMocks.readXDay).toHaveBeenCalledWith({ sourceKey: undefined, date: undefined });
    for (const forbidden of [
      rawContentSentinel,
      localPathSentinel,
      "analysis_ids",
      "evidence_post_ids",
      "provider",
      "prompt",
      "task",
      "raw_content",
      "input_snapshot",
      "thesis_id",
      "integration_id",
      "assessment_id",
      "related_thesis_ids",
      "source_ids",
      "source-alpha",
      "source-beta",
      "security-01",
      "market-01",
      "injected-source-id",
      "injected-evidence-id",
      "injected-thesis-id",
      "injected-analysis-id",
      "injected-integration-id",
      "injected-assessment-id",
      "injected-nested-thesis-id",
      "injected-nested-assessment-id",
      "injected-history-source-id",
      "injected-history-evidence-id",
      "injected-history-analysis-id",
      "analysis-17",
      "BATCH-42",
      "run-9",
      "SEGMENT-3",
      "batch-42",
      "segment-3",
      "thesis-99",
      "source-hidden",
      "post-hidden@2",
      "integration-hidden",
      "assessment-hidden",
      "must drop",
      "execution_health_status",
      "execution_failure_category",
      "unavailable",
      "configuration_error",
    ]) {
      expect(serialized).not.toContain(forbidden);
    }
  });

  it("rejects an anonymous request before reading X data", async () => {
    authMocks.getCurrentUser.mockResolvedValue(null);

    const response = await GET(new Request("http://localhost/api/reader/x"));

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(readerMocks.readXDay).not.toHaveBeenCalled();
  });

  it("normalizes an unsupported action scope status to null", async () => {
    const [day] = await readerMocks.readXDay();
    const [batch] = day.judgement.batches;
    const [viewpoint] = batch.stockViewpoints;
    readerMocks.readXDay.mockResolvedValue([{
      ...day,
      judgement: {
        ...day.judgement,
        batches: [{
          ...batch,
          stockViewpoints: [{ ...viewpoint, actionScopeStatus: "unsupported" }],
        }],
      },
    }]);

    const response = await GET(new Request("http://localhost/api/reader/x"));
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.days[0].judgement.batches[0].stockViewpoints[0].actionScopeStatus).toBeNull();
  });

  it("does not expose v5 keys when a legacy current revision and history carry v5-shaped content", async () => {
    const [day] = await readerMocks.readXDay();
    const [batch] = day.judgement.batches;
    const [historyRevision] = batch.revisionHistory;
    const marker = "LEGACY_V5_CONTENT_MUST_NOT_ESCAPE";
    const payload = v5LeakPayload(marker);

    readerMocks.readXDay.mockResolvedValue([{
      ...day,
      judgement: {
        ...day.judgement,
        batches: [{
          ...batch,
          presentationKind: "legacy",
          ...payload,
          revisionHistory: [{ ...historyRevision, presentationKind: "legacy", ...payload }],
        }],
      },
    }]);

    const response = await GET(new Request("http://localhost/api/reader/x"));
    const body = await response.json();
    const legacyBatch = body.days[0].judgement.batches[0];
    const legacyHistory = legacyBatch.revisionHistory[0];

    expect(response.status).toBe(200);
    expect(legacyBatch.presentationKind).toBe("legacy");
    expect(legacyBatch.stockViewpoints).toEqual(expect.any(Array));
    expect(legacyHistory.presentationKind).toBe("legacy");
    expect(legacyHistory.stockViewpoints).toEqual(expect.any(Array));
    for (const field of v5FieldNames) {
      expect(legacyBatch).not.toHaveProperty(field);
      expect(legacyHistory).not.toHaveProperty(field);
    }
    expect(JSON.stringify(body)).not.toContain(marker);
  });

  it("fails closed to a legacy projection for unknown or malformed presentation kinds", async () => {
    const [day] = await readerMocks.readXDay();
    const [batch] = day.judgement.batches;
    const [historyRevision] = batch.revisionHistory;
    const marker = "UNKNOWN_V5_CONTENT_MUST_NOT_ESCAPE";
    const payload = v5LeakPayload(marker);

    readerMocks.readXDay.mockResolvedValue([{
      ...day,
      judgement: {
        ...day.judgement,
        batches: [{
          ...batch,
          presentationKind: "future-v6",
          ...payload,
          revisionHistory: [{ ...historyRevision, presentationKind: { kind: "v5" }, ...payload }],
        }],
      },
    }]);

    const response = await GET(new Request("http://localhost/api/reader/x"));
    const body = await response.json();
    const malformedBatch = body.days[0].judgement.batches[0];
    const malformedHistory = malformedBatch.revisionHistory[0];

    expect(response.status).toBe(200);
    expect(malformedBatch.presentationKind).toBe("legacy");
    expect(malformedHistory.presentationKind).toBe("legacy");
    for (const field of v5FieldNames) {
      expect(malformedBatch).not.toHaveProperty(field);
      expect(malformedHistory).not.toHaveProperty(field);
    }
    expect(JSON.stringify(body)).not.toContain(marker);
  });

  it("passes supported source and date filters to the Reader projection", async () => {
    const response = await GET(new Request("http://localhost/api/reader/x?source=alpha&date=2099-01-02"));

    expect(response.status).toBe(200);
    expect(readerMocks.readXDay).toHaveBeenCalledWith({ sourceKey: "alpha", date: "2099-01-02" });
  });

  it("normalizes an absent revision history to an empty safe list", async () => {
    const [day] = await readerMocks.readXDay();
    readerMocks.readXDay.mockResolvedValue([{
      ...day,
      judgement: { visible: true, batches: [{ ...day.judgement.batches[0], revisionHistory: undefined }] },
    }]);

    const response = await GET(new Request("http://localhost/api/reader/x"));
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.days[0].judgement.batches[0].revisionHistory).toEqual([]);
  });

  it("does not expose no-new coverage when the repository has no persisted revision", async () => {
    const [day] = await readerMocks.readXDay();
    readerMocks.readXDay.mockResolvedValue([{
      ...day,
      judgement: { visible: true, batches: [{
        ...day.judgement.batches[0],
        status: "judgement_pending",
        revision: 0,
        coverageStatus: "no_new_information",
        stockViewpoints: [],
        marketIndustryViewpoints: [],
        uncertainties: [],
        revisionHistory: [],
      }] },
    }]);

    const response = await GET(new Request("http://localhost/api/reader/x"));
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.days[0].judgement.batches[0]).toMatchObject({
      status: "judgement_pending",
      revision: 0,
      coverageStatus: null,
    });
  });

  it.each(["not-a-date", "2099-02-29", "2099-04-31", "0000-01-01"])("rejects invalid calendar date %s before reading X data", async (date) => {
    const response = await GET(new Request(`http://localhost/api/reader/x?date=${date}`));

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_reader_query" });
    expect(readerMocks.readXDay).not.toHaveBeenCalled();
  });
});
