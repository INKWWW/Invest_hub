import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ authenticateWorker: vi.fn() }));
const demoMocks = vi.hoisted(() => ({ findNextQueuedDemoRunId: vi.fn() }));

vi.mock("../../../../../lib/auth/worker", () => authMocks);
vi.mock("../../../../../lib/db/repositories/agent-demo-runs", () => demoMocks);

import { POST } from "./route";

describe("POST /api/worker/agent-demo/next", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.authenticateWorker.mockResolvedValue({ id: "worker-one" });
  });

  it("returns the oldest queued Demo run for the polling Worker", async () => {
    demoMocks.findNextQueuedDemoRunId.mockResolvedValue("00000000-0000-0000-0000-000000000101");

    const response = await POST(new Request("http://localhost", { method: "POST" }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ run_id: "00000000-0000-0000-0000-000000000101" });
    expect(demoMocks.findNextQueuedDemoRunId).toHaveBeenCalledOnce();
  });

  it("returns no content when there is no queued Demo run", async () => {
    demoMocks.findNextQueuedDemoRunId.mockResolvedValue(null);

    const response = await POST(new Request("http://localhost", { method: "POST" }));

    expect(response.status).toBe(204);
  });
});
