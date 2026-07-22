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
  getWindowDailyFactContext: vi.fn(),
  resolveWindowedAuthorProfiles: vi.fn(),
  listRecentTasks: vi.fn(),
  persistWorkerExecution: vi.fn(),
  persistWindowedCapturePage: vi.fn(),
  recordWindowedCaptureSegment: vi.fn(),
  completeWindowedCaptureRange: vi.fn(),
  recordTaskFailure: vi.fn(),
  scheduleDiscordSyncTasks: vi.fn(),
  scheduleDueDiscordTasks: vi.fn(),
  isScheduleWindowKey: (value: unknown) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T(?:08:00|20:50)\+08:00$/.test(value),
}));
const windowedSyncMocks = vi.hoisted(() => ({
  createManualDiscordRefresh: vi.fn(),
  getSourceCoverage: vi.fn(),
  initializeSourceCoverage: vi.fn(),
  WindowedSyncError: class WindowedSyncError extends Error {},
}));
const authorProfileMocks = vi.hoisted(() => ({
  deleteSourceAuthorProfile: vi.fn(),
  listObservedAuthors: vi.fn(),
  listSourceAuthorProfiles: vi.fn(),
  saveSourceAuthorProfile: vi.fn(),
  SourceAuthorProfileError: class SourceAuthorProfileError extends Error {},
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
const logoutMocks = vi.hoisted(() => ({
  signOutCurrentUser: vi.fn(),
}));
const readerMocks = vi.hoisted(() => ({
  readDiscordDay: vi.fn(),
}));

vi.mock("../../lib/auth/current-user", () => authMocks);
vi.mock("../../lib/auth/invites", () => inviteMocks);
vi.mock("../../lib/auth/worker", () => workerMocks);
vi.mock("../../lib/auth/login", () => loginMocks);
vi.mock("../../lib/auth/logout", () => logoutMocks);
vi.mock("../../lib/db/repositories/workers", () => workerRepositoryMocks);
vi.mock("../../lib/db/repositories/tasks", () => taskMocks);
vi.mock("../../lib/db/repositories/windowed-sync", () => windowedSyncMocks);
vi.mock("../../lib/db/repositories/author-profiles", () => authorProfileMocks);
vi.mock("../../lib/db/repositories/sources", () => sourceMocks);
vi.mock("../../lib/db/repositories/rules", () => ruleMocks);
vi.mock("../../lib/db/repositories/reader", () => readerMocks);

import { POST as postAdminInvite } from "./admin/invites/route";
import { POST as postLogin } from "./auth/login/route";
import { POST as postLogout } from "./auth/logout/route";
import { POST as postEnrol } from "./worker/enrol/route";
import { POST as postHeartbeat } from "./worker/heartbeat/route";
import { POST as postPersist } from "./worker/tasks/[taskId]/persist/route";
import { POST as postResult } from "./worker/tasks/[taskId]/result/route";
import { POST as postCaptureSegment } from "./worker/tasks/[taskId]/capture-segments/route";
import { POST as postRangeComplete } from "./worker/tasks/[taskId]/range-complete/route";
import { GET as getAdminTaskDetail } from "./admin/tasks/[taskId]/route";
import { PATCH as patchAdminSource } from "./admin/sources/route";
import { POST as postAdminRule } from "./admin/rules/route";
import { POST as postAdminTask } from "./admin/tasks/route";
import { GET as getCoverage, POST as postCoverageInitialization } from "./admin/sources/[sourceId]/coverage/route";
import {
  GET as getAuthorProfiles,
  POST as postAuthorProfile,
} from "./admin/sources/[sourceId]/author-profiles/route";
import { GET as getObservedAuthors } from "./admin/sources/[sourceId]/observed-authors/route";
import { POST as postManualDiscordRefresh } from "./admin/discord/manual-refresh/route";
import { GET as getDiscordReader } from "./reader/discord/route";
import { POST as postScheduleTick } from "./worker/schedule/tick/route";
import { GET as getDailyFactContext } from "./worker/tasks/[taskId]/daily-fact-context/route";
import { POST as postResolveAuthorProfiles } from "./worker/tasks/[taskId]/resolve-author-profiles/route";

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
      status: "succeeded",
      dailySummary: { version: 1, presentation: { kind: "legacy", topics: [], warnings: [], mediaUnparsed: false }, history: [] },
      batches: [],
    }]);
    const response = await getDiscordReader(new Request("http://localhost/api/reader/discord?source=source-1&date=2099-01-01"));

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.days[0]).not.toHaveProperty("messages");
    expect(body.days[0].source).not.toHaveProperty("source_id");
    expect(JSON.stringify(body)).not.toContain("local_raw_ref");
    expect(JSON.stringify(body)).not.toContain("fixture");
    expect(JSON.stringify(body)).not.toContain("provider");
    expect(JSON.stringify(body)).not.toContain("cursor");
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
      display_name: "Research community · #daily",
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

  it("blocks ordinary users from V1.1 coverage, author configuration, and manual refresh APIs", async () => {
    const params = { params: Promise.resolve({ sourceId: "source-1" }) };
    const coverage = await postCoverageInitialization(
      jsonRequest("/api/admin/sources/source-1/coverage", { coverage_start_at: "2026-07-22T00:00:00Z" }),
      params,
    );
    const authors = await getAuthorProfiles(new Request("http://localhost/api/admin/sources/source-1/author-profiles"), params);
    const observed = await getObservedAuthors(new Request("http://localhost/api/admin/sources/source-1/observed-authors"), params);
    const manual = await postManualDiscordRefresh(jsonRequest("/api/admin/discord/manual-refresh", { source_id: "source-1" }));

    expect(coverage.status).toBe(403);
    expect(authors.status).toBe(403);
    expect(observed.status).toBe(403);
    expect(manual.status).toBe(403);
    expect(windowedSyncMocks.initializeSourceCoverage).not.toHaveBeenCalled();
    expect(windowedSyncMocks.createManualDiscordRefresh).not.toHaveBeenCalled();
    expect(authorProfileMocks.listSourceAuthorProfiles).not.toHaveBeenCalled();
    expect(authorProfileMocks.listObservedAuthors).not.toHaveBeenCalled();
  });

  it("requires an explicit legacy scope instead of silently creating a five-page task", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    taskMocks.createDiscordSyncTask.mockResolvedValue({ id: "task-1", collection_scope: { mode: "history", max_pages: 9 } });

    const invalid = await postAdminTask(jsonRequest("/api/admin/tasks", {
      source_id: "source-1",
      parameter_version: "v1-source-1",
      scope: { mode: "history", max_pages: 0 },
    }));
    expect(invalid.status).toBe(422);

    const missingScope = await postAdminTask(jsonRequest("/api/admin/tasks", {
      source_id: "source-1",
      parameter_version: "v1-source-1",
    }));
    expect(missingScope.status).toBe(422);
    expect(taskMocks.createDiscordSyncTask).not.toHaveBeenCalled();

    const created = await postAdminTask(jsonRequest("/api/admin/tasks", {
      source_id: "source-1",
      parameter_version: "v1-source-1",
      scope: { mode: "history", max_pages: 9 },
    }));
    expect(created.status).toBe(201);
    expect(taskMocks.createDiscordSyncTask).toHaveBeenCalledWith({
      sourceId: "source-1",
      parameterVersion: "v1-source-1",
      requestedBy: "admin-1",
      scope: { mode: "history", maxPages: 9 },
    });
  });

  it("allows admins to initialize coverage, configure direct author selectors, and queue a safe manual refresh", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    windowedSyncMocks.initializeSourceCoverage.mockResolvedValue({
      sourceId: "source-1",
      coverageStartAt: "2026-07-22T00:00:00Z",
      coverageThroughAt: "2026-07-22T00:00:00Z",
    });
    authorProfileMocks.listObservedAuthors.mockResolvedValue([{
      authorId: "discord-stable-author-1",
      authorDisplay: "Observed author",
      authorHandle: "observed-author",
    }]);
    authorProfileMocks.saveSourceAuthorProfile.mockResolvedValue({
      id: "profile-1",
      sourceId: "source-1",
      requestedAuthor: "Priority author",
      resolutionStatus: "pending",
      authorId: null,
      authorDisplay: "Priority author",
      authorHandle: null,
      enabled: true,
    });
    windowedSyncMocks.createManualDiscordRefresh.mockResolvedValue({
      id: "window-task-1",
      sourceId: "source-1",
      status: "queued",
      trigger: "manual",
      startAt: "2026-07-22T00:00:00Z",
      endAt: "2026-07-22T03:00:00Z",
      queuedAt: "2026-07-22T03:00:00Z",
      idempotent: false,
    });
    const params = { params: Promise.resolve({ sourceId: "source-1" }) };

    const coverage = await postCoverageInitialization(
      jsonRequest("/api/admin/sources/source-1/coverage", { coverage_start_at: "2026-07-22T00:00:00Z" }),
      params,
    );
    expect(coverage.status).toBe(200);
    expect(await coverage.json()).toEqual({
      coverage: {
        source_id: "source-1",
        coverage_start_at: "2026-07-22T00:00:00Z",
        coverage_through_at: "2026-07-22T00:00:00Z",
      },
    });

    const observed = await getObservedAuthors(new Request("http://localhost/api/admin/sources/source-1/observed-authors"), params);
    expect(observed.status).toBe(200);
    expect(await observed.json()).toEqual({ authors: [{
      author_id: "discord-stable-author-1",
      author_display: "Observed author",
      author_handle: "observed-author",
    }] });

    const invalidProfile = await postAuthorProfile(
      jsonRequest("/api/admin/sources/source-1/author-profiles", { requested_author: "Priority author", author_id: "discord-stable-author-1" }),
      params,
    );
    expect(invalidProfile.status).toBe(422);
    expect(authorProfileMocks.saveSourceAuthorProfile).not.toHaveBeenCalled();

    const profile = await postAuthorProfile(
      jsonRequest("/api/admin/sources/source-1/author-profiles", { requested_author: "Priority author" }),
      params,
    );
    expect(profile.status).toBe(201);
    expect(await profile.json()).toEqual({ author_profile: {
      id: "profile-1",
      source_id: "source-1",
      requested_author: "Priority author",
      resolution_status: "pending",
      author_id: null,
      author_display: "Priority author",
      author_handle: null,
      enabled: true,
    } });
    expect(authorProfileMocks.saveSourceAuthorProfile).toHaveBeenCalledWith({
      sourceId: "source-1",
      requestedAuthor: "Priority author",
      actorId: "admin-1",
    });

    const manual = await postManualDiscordRefresh(jsonRequest("/api/admin/discord/manual-refresh", { source_id: "source-1" }));
    expect(manual.status).toBe(202);
    const manualBody = await manual.json();
    expect(manualBody).toEqual({ task: {
      id: "window-task-1",
      source_id: "source-1",
      status: "queued",
      trigger: "manual",
      start_at: "2026-07-22T00:00:00Z",
      end_at: "2026-07-22T03:00:00Z",
      queued_at: "2026-07-22T03:00:00Z",
      idempotent: false,
    } });
    expect(JSON.stringify(manualBody)).not.toContain("cursor");
  });

  it("keeps coverage read failures generic while recording safe diagnostics", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    windowedSyncMocks.getSourceCoverage.mockRejectedValue({ code: "42P01", message: "relation is unavailable" });
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);

    const response = await getCoverage(
      new Request("http://localhost/api/admin/sources/source-1/coverage"),
      { params: Promise.resolve({ sourceId: "source-1" }) },
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "coverage_read_failed" });
    expect(errorSpy).toHaveBeenCalledWith("coverage_read_failed", { code: "42P01", message: "relation is unavailable" });
    errorSpy.mockRestore();
  });

  it("rejects source administration payloads that try to include collection secrets or URLs", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });

    const response = await patchAdminSource(jsonRequest("/api/admin/sources", {
      source_id: "source-1",
      display_name: "Research community · #daily",
      enabled: true,
      authorized_worker_id: "worker-1",
      channel_url: "https://discord.example.invalid/channels/private",
    }));

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_source_administration" });
    expect(sourceMocks.updateSourceAdministration).not.toHaveBeenCalled();
  });

  it("rejects numeric source labels in administrator source updates", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });

    const response = await patchAdminSource(jsonRequest("/api/admin/sources", {
      source_id: "source-1",
      display_name: "Discord Source 01",
      enabled: true,
      authorized_worker_id: "worker-1",
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

  it("lets the control plane calculate due scheduled windows without a Worker-submitted key", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.scheduleDueDiscordTasks.mockResolvedValue({
      scheduled_at: "2099-01-01T00:00:00Z",
      tasks: [{ id: "scheduled-task-1", source_id: "source-1", idempotent: false }],
    });

    const first = await postScheduleTick(
      jsonRequest("/api/worker/schedule/tick", {}, { authorization: "Bearer device-secret" }),
    );
    expect(first.status).toBe(200);
    expect(await first.json()).toMatchObject({ tasks: [{ id: "scheduled-task-1", source_id: "source-1" }] });
    expect(taskMocks.scheduleDueDiscordTasks).toHaveBeenCalledWith("worker-1");
    expect(taskMocks.scheduleDiscordSyncTasks).not.toHaveBeenCalled();
  });

  it("rejects unauthenticated Workers and client-supplied schedule ranges", async () => {
    const unauthenticated = await postScheduleTick(jsonRequest("/api/worker/schedule/tick", {}));
    expect(unauthenticated.status).toBe(401);

    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    const invalid = await postScheduleTick(
      jsonRequest("/api/worker/schedule/tick", { window_key: "not-a-window" }, { authorization: "Bearer device-secret" }),
    );
    expect(invalid.status).toBe(422);
    expect(taskMocks.scheduleDueDiscordTasks).not.toHaveBeenCalled();
  });

  it("returns only safe daily fact context to the Worker holding the current lease", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.getWindowDailyFactContext.mockResolvedValue({
      message_catalog: [{
        external_message_id: "message-1",
        natural_date: "2099-01-01",
        author_id: "author-1",
        author_display: "Observed Author",
        has_unparsed_media: false,
      }],
      prior_batches: [],
    });

    const response = await getDailyFactContext(
      new Request("http://localhost/api/worker/tasks/task-1/daily-fact-context?attempt=2"),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(expect.objectContaining({ message_catalog: expect.any(Array) }));
    expect(taskMocks.getWindowDailyFactContext).toHaveBeenCalledWith("task-1", 2, "worker-1");

    const invalid = await getDailyFactContext(
      new Request("http://localhost/api/worker/tasks/task-1/daily-fact-context?attempt=0"),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );
    expect(invalid.status).toBe(422);
  });

  it("resolves configured author selectors after page persistence without returning messages", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.resolveWindowedAuthorProfiles.mockResolvedValue({ author_profiles: [{
      profile_id: "profile-1",
      requested_author: "Priority author",
      resolution_status: "resolved",
      author_id: "stable-author-1",
      author_display: "Priority author",
      author_handle: null,
      enabled: true,
    }] });

    const response = await postResolveAuthorProfiles(
      jsonRequest("/api/worker/tasks/task-1/resolve-author-profiles", { attempt: 2 }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ author_profiles: [expect.objectContaining({ profile_id: "profile-1" })] });
    expect(taskMocks.resolveWindowedAuthorProfiles).toHaveBeenCalledWith("task-1", 2, "worker-1");
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

  it("persists verified capture segments and completes window ranges without using a safe checkpoint result", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.recordWindowedCaptureSegment.mockResolvedValue({
      task_id: "task-window-1",
      idempotent: false,
      resume_cursor: "cursor-001",
    });
    taskMocks.completeWindowedCaptureRange.mockResolvedValue({
      status: "succeeded",
      idempotent: false,
      task_id: "task-window-1",
      attempt: 1,
      coverage_through_at: "2026-07-22T08:00:00Z",
    });

    const segment = await postCaptureSegment(
      jsonRequest("/api/worker/tasks/task-window-1/capture-segments", {
        contract_version: "v0",
        task_id: "task-window-1",
        attempt: 1,
        capture_segment: {
          idempotency_key: "page-001",
          request_cursor: null,
          next_cursor: "cursor-001",
          oldest_occurred_at: "2026-07-22T00:00:00Z",
          newest_occurred_at: "2026-07-22T08:00:00Z",
          response_matched: true,
          response_fresh: true,
        },
      }, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-window-1" }) },
    );
    expect(segment.status).toBe(200);
    expect(await segment.json()).toEqual({ task_id: "task-window-1", idempotent: false, resume_cursor: "cursor-001" });
    expect(taskMocks.recordWindowedCaptureSegment).toHaveBeenCalledWith("task-window-1", 1, "worker-1", {
      idempotency_key: "page-001",
      request_cursor: null,
      next_cursor: "cursor-001",
      oldest_occurred_at: "2026-07-22T00:00:00Z",
      newest_occurred_at: "2026-07-22T08:00:00Z",
      response_matched: true,
      response_fresh: true,
    });

    const completion = await postRangeComplete(
      jsonRequest("/api/worker/tasks/task-window-1/range-complete", {
        contract_version: "v0",
        task_id: "task-window-1",
        attempt: 1,
        range_complete: true,
        capture_range: {
          mode: "window",
          trigger: "manual",
          timezone: "Asia/Shanghai",
          start_at: "2026-07-22T00:00:00Z",
          end_at: "2026-07-22T08:00:00Z",
          scheduled_window_key: null,
        },
        boundary: { kind: "oldest_at_or_before_start", observed_at: "2026-07-22T00:00:00Z" },
        summary_batch_ids: [],
        daily_summary_ids: [],
        no_new_data: true,
      }, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-window-1" }) },
    );
    expect(completion.status).toBe(200);
    expect(await completion.json()).toEqual({
      status: "succeeded",
      idempotent: false,
      task_id: "task-window-1",
      attempt: 1,
      coverage_through_at: "2026-07-22T08:00:00Z",
    });
    expect(taskMocks.completeWindowedCaptureRange).toHaveBeenCalledWith("task-window-1", 1, "worker-1", expect.objectContaining({ range_complete: true }));
  });

  it("does not advance a range when its persistence receipt is absent", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.completeWindowedCaptureRange.mockRejectedValue({ code: "55000", message: "persistence_not_confirmed" });

    const response = await postRangeComplete(
      jsonRequest("/api/worker/tasks/task-window-1/range-complete", {
        contract_version: "v0",
        task_id: "task-window-1",
        attempt: 1,
        range_complete: true,
        capture_range: {
          mode: "window", trigger: "manual", timezone: "Asia/Shanghai",
          start_at: "2026-07-22T00:00:00Z", end_at: "2026-07-22T08:00:00Z", scheduled_window_key: null,
        },
        boundary: { kind: "oldest_at_or_before_start", observed_at: "2026-07-22T00:00:00Z" },
        summary_batch_ids: [], daily_summary_ids: [], no_new_data: true,
      }, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-window-1" }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "persistence_not_confirmed" });
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

  it("persists one window page and its resume segment atomically", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    const payload = {
      ...validPersistencePayload,
      structured_runs: [],
      capture_segment: {
        idempotency_key: "page:1",
        request_cursor: null,
        next_cursor: "cursor-1",
        oldest_occurred_at: "2099-01-01T00:00:00.000Z",
        newest_occurred_at: "2099-01-01T00:00:00.000Z",
        response_matched: true,
        response_fresh: true,
      },
    };
    taskMocks.persistWindowedCapturePage.mockResolvedValue({
      persisted: true,
      idempotent: false,
      resume_cursor: "cursor-1",
    });

    const response = await postPersist(
      jsonRequest("/api/worker/tasks/task-1/persist", payload, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ persisted: true, idempotent: false, resume_cursor: "cursor-1" });
    expect(taskMocks.persistWindowedCapturePage).toHaveBeenCalledWith("task-1", 1, "worker-1", payload);
    expect(taskMocks.persistWorkerExecution).not.toHaveBeenCalled();
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

  it("clears the current session through the logout API without returning authentication data", async () => {
    logoutMocks.signOutCurrentUser.mockResolvedValue({ ok: true });

    const response = await postLogout(new Request("http://localhost/api/auth/logout", { method: "POST" }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    expect(logoutMocks.signOutCurrentUser).toHaveBeenCalledOnce();
  });
});
