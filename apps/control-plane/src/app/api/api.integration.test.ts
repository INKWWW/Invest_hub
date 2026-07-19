import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({
  getCurrentUser: vi.fn(),
}));
const inviteMocks = vi.hoisted(() => ({
  createOneTimeInvite: vi.fn(),
  hashInviteCode: vi.fn((code: string) => `hash:${code}`),
  consumeInvite: vi.fn(),
  consumeWorkerInvite: vi.fn(),
}));
const workerMocks = vi.hoisted(() => ({
  authenticateWorker: vi.fn(),
}));
const workerRepositoryMocks = vi.hoisted(() => ({
  registerWorker: vi.fn(),
  updateWorkerHeartbeat: vi.fn(),
}));
const taskMocks = vi.hoisted(() => ({
  acceptTaskResult: vi.fn(),
  createDiscordSyncTask: vi.fn(),
  getTaskDetail: vi.fn(),
  listRecentTasks: vi.fn(),
  persistWorkerExecution: vi.fn(),
  recordTaskFailure: vi.fn(),
}));
const sourceMocks = vi.hoisted(() => ({
  listSources: vi.fn(),
  updateSourceAdministration: vi.fn(),
  upsertDiscordSource: vi.fn(),
}));
const ruleMocks = vi.hoisted(() => ({
  replaceSourceRules: vi.fn(),
}));
const loginMocks = vi.hoisted(() => ({
  loginWithPassword: vi.fn(),
}));
const readerMocks = vi.hoisted(() => ({
  readDiscordDay: vi.fn(),
}));

vi.mock("../../lib/auth/current-user", () => authMocks);
vi.mock("../../lib/auth/invites", () => inviteMocks);
vi.mock("../../lib/auth/worker", () => workerMocks);
vi.mock("../../lib/auth/login", () => loginMocks);
vi.mock("../../lib/db/repositories/workers", () => workerRepositoryMocks);
vi.mock("../../lib/db/repositories/tasks", () => taskMocks);
vi.mock("../../lib/db/repositories/sources", () => sourceMocks);
vi.mock("../../lib/db/repositories/rules", () => ruleMocks);
vi.mock("../../lib/db/repositories/reader", () => readerMocks);

import { POST as postAdminInvite } from "./admin/invites/route";
import { POST as postLogin } from "./auth/login/route";
import { POST as postEnrol } from "./worker/enrol/route";
import { POST as postHeartbeat } from "./worker/heartbeat/route";
import { POST as postPersist } from "./worker/tasks/[taskId]/persist/route";
import { POST as postResult } from "./worker/tasks/[taskId]/result/route";
import { GET as getAdminTaskDetail } from "./admin/tasks/[taskId]/route";
import { PATCH as patchAdminSource } from "./admin/sources/route";
import { POST as postAdminRule } from "./admin/rules/route";
import { POST as postAdminTask } from "./admin/tasks/route";
import { GET as getDiscordReader } from "./reader/discord/route";

function jsonRequest(path: string, body: unknown, headers: Record<string, string> = {}) {
  return new Request(`http://localhost${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const validTaskResult = {
  contract_version: "v0",
  task_id: "task-1",
  attempt: 1,
  status: "succeeded",
  safe_checkpoint: "message-2",
  raw_count: 2,
  canonical_count: 2,
  duplicate_count: 0,
  unresolved_count: 0,
  unparsed_media_count: 0,
  structured_run_ids: [],
  telemetry: { elapsed_ms: 10, retry_count: 0, failure_class: null },
};

const validPersistencePayload = {
  contract_version: "v0",
  task_id: "task-1",
  attempt: 1,
  source_id: "discord-v0-test",
  raw_messages: [
    {
      external_message_id: "message-1",
      occurred_at: "2099-01-01T00:00:00.000Z",
      local_raw_ref: "local://v0/raw/message-1.json",
      payload_hash: "a".repeat(64),
      retention_expires_at: "2100-01-01T00:00:00.000Z",
    },
  ],
  canonical_messages: [
    {
      external_message_id: "message-1",
      occurred_at: "2099-01-01T00:00:00.000Z",
      author_display: "fixture-author",
      content: "fixture content",
      has_unparsed_media: false,
      metadata: {},
    },
  ],
  structured_runs: [
    {
      chunk_key: "chunk-1",
      provider: "mock",
      parameter_version: "v0-test-1",
      input_message_ids: ["message-1"],
      media_source_message_ids: [],
      output: { topics: [] },
    },
  ],
};

describe("v0 control-plane API authorization", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-1", role: "user", email: "user@example.invalid" });
    workerMocks.authenticateWorker.mockResolvedValue(null);
  });

  it("blocks ordinary users from admin invite creation without revealing records", async () => {
    const response = await postAdminInvite(jsonRequest("/api/admin/invites", { purpose: "user" }));
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "forbidden" });
    expect(inviteMocks.createOneTimeInvite).not.toHaveBeenCalled();
  });

  it("blocks ordinary users from admin task detail without reading evidence", async () => {
    const response = await getAdminTaskDetail(new Request("http://localhost/api/admin/tasks/task-1"), {
      params: Promise.resolve({ taskId: "task-1" }),
    });
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "forbidden" });
    expect(taskMocks.getTaskDetail).not.toHaveBeenCalled();
  });

  it("allows an authenticated ordinary user to read only the safe Discord reader DTO", async () => {
    readerMocks.readDiscordDay.mockResolvedValue([{
      source: { sourceKey: "source-1", displayName: "Fixture source" },
      naturalDate: "2099-01-01",
      dailySummary: { id: "daily-1", version: 1, output: { topics: [] }, coverage: {} },
      batches: [],
      messages: [{ externalMessageId: "message-1", occurredAt: "2099-01-01T00:00:00Z", authorDisplay: "Author", content: "fixture", hasUnparsedMedia: false, unresolved: false }],
    }]);
    const response = await getDiscordReader(new Request("http://localhost/api/reader/discord?source=source-1&date=2099-01-01"));

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.days[0].messages[0].content).toBe("fixture");
    expect(JSON.stringify(body)).not.toContain("local_raw_ref");
    expect(JSON.stringify(body)).not.toContain("device_secret_hash");
  });

  it("blocks ordinary users from changing rules, source bindings, and history scopes", async () => {
    const rule = await postAdminRule(jsonRequest("/api/admin/rules", {
      source_id: "source-1",
      global_target_author_ids: [],
      source_target_author_ids: [],
      source_excluded_author_ids: [],
    }));
    const source = await patchAdminSource(jsonRequest("/api/admin/sources", {
      source_id: "source-1",
      enabled: true,
      authorized_worker_id: "worker-1",
    }));
    const task = await postAdminTask(jsonRequest("/api/admin/tasks", {
      source_id: "source-1",
      parameter_version: "v1-source-1",
      scope: { mode: "history", max_pages: 9 },
    }));

    expect(rule.status).toBe(403);
    expect(source.status).toBe(403);
    expect(task.status).toBe(403);
    expect(ruleMocks.replaceSourceRules).not.toHaveBeenCalled();
    expect(sourceMocks.updateSourceAdministration).not.toHaveBeenCalled();
    expect(taskMocks.createDiscordSyncTask).not.toHaveBeenCalled();
  });

  it("validates finite task scopes and creates regular tasks with the five-page default", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    taskMocks.createDiscordSyncTask.mockResolvedValue({ id: "task-1", collection_scope: { mode: "incremental", max_pages: 5 } });

    const invalid = await postAdminTask(jsonRequest("/api/admin/tasks", {
      source_id: "source-1",
      parameter_version: "v1-source-1",
      scope: { mode: "history", max_pages: 0 },
    }));
    expect(invalid.status).toBe(422);

    const created = await postAdminTask(jsonRequest("/api/admin/tasks", {
      source_id: "source-1",
      parameter_version: "v1-source-1",
    }));
    expect(created.status).toBe(201);
    expect(taskMocks.createDiscordSyncTask).toHaveBeenCalledWith({
      sourceId: "source-1",
      parameterVersion: "v1-source-1",
      requestedBy: "admin-1",
      scope: { mode: "incremental", maxPages: 5 },
    });
  });

  it("rejects source administration payloads that try to include collection secrets or URLs", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });

    const response = await patchAdminSource(jsonRequest("/api/admin/sources", {
      source_id: "source-1",
      enabled: true,
      authorized_worker_id: "worker-1",
      channel_url: "https://discord.example.invalid/channels/private",
    }));

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_source_administration" });
    expect(sourceMocks.updateSourceAdministration).not.toHaveBeenCalled();
  });

  it("returns a one-time invite code only to an admin", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    inviteMocks.createOneTimeInvite.mockResolvedValue({
      inviteId: "invite-1",
      code: "one-time-code",
      purpose: "worker",
      expiresAt: "2099-01-01T00:00:00.000Z",
    });

    const response = await postAdminInvite(
      jsonRequest("/api/admin/invites", { purpose: "worker", expires_in_hours: 24 }),
    );
    expect(response.status).toBe(201);
    const body = await response.json();
    expect(body).toMatchObject({ invite_id: "invite-1", code: "one-time-code", purpose: "worker" });
    expect(body).not.toHaveProperty("code_hash");
  });

  it("consumes a worker enrolment code once and rejects replay", async () => {
    inviteMocks.consumeWorkerInvite
      .mockResolvedValueOnce({ invite_id: "invite-1", purpose: "worker", role: "user" })
      .mockResolvedValueOnce(null);
    workerRepositoryMocks.registerWorker.mockResolvedValue({ id: "worker-1", status: "enrolled" });

    const requestBody = { code: "one-time-code", name: "local-worker" };
    const first = await postEnrol(jsonRequest("/api/worker/enrol", requestBody));
    expect(first.status).toBe(201);
    const firstBody = await first.json();
    expect(firstBody.worker_id).toBeTypeOf("string");
    expect(firstBody.device_secret.length).toBeGreaterThanOrEqual(32);
    expect(firstBody).not.toHaveProperty("device_secret_hash");

    const replay = await postEnrol(jsonRequest("/api/worker/enrol", requestBody));
    expect(replay.status).toBe(409);
    expect(await replay.json()).toEqual({ error: "invite_replayed" });
  });

  it("rejects heartbeat without a Worker secret", async () => {
    const response = await postHeartbeat(jsonRequest("/api/worker/heartbeat", { status: "idle" }));
    expect(response.status).toBe(401);
  });

  it("reports a next heartbeat deadline for an authenticated Worker", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "enrolled" });
    workerRepositoryMocks.updateWorkerHeartbeat.mockResolvedValue({ id: "worker-1", status: "online" });

    const response = await postHeartbeat(
      jsonRequest("/api/worker/heartbeat", {
        contract_version: "v0",
        worker_id: "worker-1",
        sent_at: "2099-01-01T00:00:00.000Z",
        status: "idle",
        capabilities: ["discord_sync"],
      }, { authorization: "Bearer device-secret" }),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ worker_id: "worker-1", heartbeat_interval_seconds: 60 });
  });

  it("maps an attempt/lease mismatch to 409", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.acceptTaskResult.mockRejectedValue({ code: "40001", message: "lease_mismatch" });
    const response = await postResult(
      jsonRequest("/api/worker/tasks/task-1/result", validTaskResult, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "lease_mismatch" });
  });

  it("accepts a valid Worker persistence payload without returning its local reference", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.persistWorkerExecution.mockResolvedValue({
      persisted: true,
      structured_run_ids: ["run-1"],
      summary_batch_ids: ["batch-1"],
      daily_summary_ids: ["daily-1"],
    });

    const response = await postPersist(
      jsonRequest("/api/worker/tasks/task-1/persist", validPersistencePayload, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      persisted: true,
      structured_run_ids: ["run-1"],
      summary_batch_ids: ["batch-1"],
      daily_summary_ids: ["daily-1"],
    });
    expect(taskMocks.persistWorkerExecution).toHaveBeenCalledWith("task-1", 1, "worker-1", validPersistencePayload);
  });

  it("maps a conflicting duplicate result to 409", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.acceptTaskResult.mockRejectedValue({ code: "23505", message: "conflicting_duplicate_result" });
    const response = await postResult(
      jsonRequest("/api/worker/tasks/task-1/result", validTaskResult, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "conflicting_duplicate_result" });
  });

  it("refuses a result whose summary receipt IDs do not match persisted evidence", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.acceptTaskResult.mockRejectedValue({ code: "55000", message: "summary_receipt_mismatch" });
    const response = await postResult(
      jsonRequest("/api/worker/tasks/task-1/result", {
        ...validTaskResult,
        summary_batch_ids: ["wrong-batch"],
        daily_summary_ids: ["wrong-daily"],
      }, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "summary_receipt_mismatch" });
  });

  it("does not expose a device secret or prompt in a successful result response", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.acceptTaskResult.mockResolvedValue({ status: "succeeded", idempotent: false });
    const response = await postResult(
      jsonRequest("/api/worker/tasks/task-1/result", validTaskResult, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ status: "succeeded", idempotent: false });
    expect(JSON.stringify(body)).not.toContain("device-secret");
    expect(JSON.stringify(body)).not.toContain("prompt");
  });

  it("surfaces login failure without creating a session", async () => {
    loginMocks.loginWithPassword.mockResolvedValue({ ok: false, error: "invalid_credentials" });
    const response = await postLogin(jsonRequest("/api/auth/login", {
      email: "user@example.invalid",
      password: "wrong-password",
    }));
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "invalid_credentials" });
  });
});
