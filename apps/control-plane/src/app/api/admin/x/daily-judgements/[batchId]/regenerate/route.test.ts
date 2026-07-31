import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const dailyJudgementMocks = vi.hoisted(() => ({ regenerateXDailyJudgement: vi.fn() }));

vi.mock("../../../../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../../../../lib/db/repositories/x-daily-judgements", () => dailyJudgementMocks);

import { POST } from "./route";

const batchId = "11111111-1111-4111-8111-111111111111";

function jsonRequest(body: unknown) {
  return new Request(`http://localhost/api/admin/x/daily-judgements/${batchId}/regenerate`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/admin/x/daily-judgements/:batchId/regenerate", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue(null);
  });

  it("rejects an unauthenticated request before invoking regeneration", async () => {
    const response = await POST(jsonRequest({}), { params: Promise.resolve({ batchId }) });

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(dailyJudgementMocks.regenerateXDailyJudgement).not.toHaveBeenCalled();
  });

  it("rejects an ordinary user before invoking regeneration", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "actor-1", role: "user", email: "user@example.invalid" });

    const response = await POST(jsonRequest({}), { params: Promise.resolve({ batchId }) });

    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "forbidden" });
    expect(dailyJudgementMocks.regenerateXDailyJudgement).not.toHaveBeenCalled();
  });

  it.each([
    ["invalid batch id", "not-a-uuid", {}],
    ["non-empty body", batchId, { accidental: true }],
  ])("rejects a %s without invoking regeneration", async (_name, requestedBatchId, body) => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "22222222-2222-4222-8222-222222222222", role: "admin", email: "admin@example.invalid" });

    const response = await POST(jsonRequest(body), { params: Promise.resolve({ batchId: requestedBatchId }) });

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_daily_judgement_regeneration" });
    expect(dailyJudgementMocks.regenerateXDailyJudgement).not.toHaveBeenCalled();
  });

  it("queues an admin regeneration and returns only its safe identity", async () => {
    const actorId = "22222222-2222-4222-8222-222222222222";
    authMocks.getCurrentUser.mockResolvedValue({ id: actorId, role: "admin", email: "admin@example.invalid" });
    dailyJudgementMocks.regenerateXDailyJudgement.mockResolvedValue({
      runId: "33333333-3333-4333-8333-333333333333", status: "queued", attempt: 0,
      provider: "must not be returned",
    });

    const response = await POST(jsonRequest({}), { params: Promise.resolve({ batchId }) });

    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({
      runId: "33333333-3333-4333-8333-333333333333", status: "queued", attempt: 0,
    });
    expect(dailyJudgementMocks.regenerateXDailyJudgement).toHaveBeenCalledWith(batchId, actorId);
  });
});
