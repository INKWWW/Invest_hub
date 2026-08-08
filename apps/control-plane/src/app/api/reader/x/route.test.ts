import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const readerMocks = vi.hoisted(() => ({ readXDay: vi.fn() }));

vi.mock("../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../lib/db/repositories/reader", () => readerMocks);

import { GET } from "./route";

const rawContentSentinel = "FORBIDDEN_RAW_X_CONTENT_SENTINEL";
const localPathSentinel = "/private/reader-unsafe/evidence.json";

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
      judgement: {
        visible: true,
        batches: [{
          cutoffAt: "2099-01-02T12:00:00.000Z",
          coverageStatus: "complete",
          status: "succeeded",
          revision: 2,
          provider: "must not escape",
          prompt: "must not escape",
          task: "must not escape",
          analysis_ids: ["private-analysis-id"],
          evidence_post_ids: ["private-post-id"],
          local_path: localPathSentinel,
          raw_content: rawContentSentinel,
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
            stockViewpoints: [{
              statement: "Safe prior revision.",
              supportingDisplayNames: ["Alpha"],
              dissentingDisplayNames: [],
              uncertainties: ["Earlier uncertainty"],
              analysis_ids: ["private-prior-analysis-id"],
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
          stockViewpoints: [expect.objectContaining({ statement: "Only the latest safe judgement is visible." })],
          revisionHistory: [expect.objectContaining({
            revision: 1,
            coverageStatus: "partial",
            stockViewpoints: [expect.objectContaining({ statement: "Safe prior revision." })],
          })],
        })] }),
        bloggers: [expect.objectContaining({ source: { sourceKey: "alpha", displayName: "Alpha" }, segments: [expect.objectContaining({ analyses: [expect.objectContaining({ postLink: "https://x.com/alpha/status/1", postedAt: "2099-01-02T08:30:00.000Z", postType: "quote" })] })] })],
      }),
    ]) });
    expect(readerMocks.readXDay).toHaveBeenCalledWith({ sourceKey: undefined, date: undefined });
    for (const forbidden of [rawContentSentinel, localPathSentinel, "analysis_ids", "evidence_post_ids", "provider", "prompt", "task", "raw_content", "input_snapshot"]) {
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
