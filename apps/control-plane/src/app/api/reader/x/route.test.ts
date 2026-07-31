import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const readerMocks = vi.hoisted(() => ({ readXDay: vi.fn() }));

vi.mock("../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../lib/db/repositories/reader", () => readerMocks);

import { GET } from "./route";

const rawContentSentinel = "FORBIDDEN_RAW_X_CONTENT_SENTINEL";

describe("GET /api/reader/x", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "ordinary-user", role: "user" });
    readerMocks.readXDay.mockResolvedValue([{
      naturalDate: "2099-01-02",
      judgement: {
        visible: true,
        batches: [{
          cutoffAt: "2099-01-02T12:00:00.000Z",
          coverageStatus: "complete",
          status: "succeeded",
          revision: 2,
          stockViewpoints: [{
            statement: "Only the latest safe judgement is visible.",
            supportingDisplayNames: ["Beta"],
            dissentingDisplayNames: ["Alpha"],
            uncertainties: [],
          }],
          marketIndustryViewpoints: [],
          uncertainties: [],
          excludedSourceCount: 0,
        }],
      },
      bloggers: [],
    }]);
  });

  it("returns the Reader-safe DTO for an ordinary user without internal payload fields", async () => {
    const response = await GET(new Request("http://localhost/api/reader/x?source=all&date=all"));
    const body = await response.json();
    const serialized = JSON.stringify(body);

    expect(response.status).toBe(200);
    expect(body).toEqual({ status: "ok", days: expect.arrayContaining([
      expect.objectContaining({ naturalDate: "2099-01-02" }),
    ]) });
    expect(readerMocks.readXDay).toHaveBeenCalledWith({ sourceKey: undefined, date: undefined });
    for (const forbidden of [rawContentSentinel, "analysis_ids", "evidence_post_ids", "provider", "prompt", "task"]) {
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

  it("rejects an invalid date filter before reading X data", async () => {
    const response = await GET(new Request("http://localhost/api/reader/x?date=not-a-date"));

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_reader_query" });
    expect(readerMocks.readXDay).not.toHaveBeenCalled();
  });
});
