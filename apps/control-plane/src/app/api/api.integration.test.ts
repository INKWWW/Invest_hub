import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({
  getCurrentUser: vi.fn(),
}));
const inviteMocks = vi.hoisted(() => ({
  createOneTimeInvite: vi.fn(),
  createOneTimeUserInvite: vi.fn(),
  createOneTimeWorkerInvite: vi.fn(),
  listRecentUserInvites: vi.fn(),
  redeemInviteAccount: vi.fn(),
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
  scheduleDueSourceTasks: vi.fn(),
  isScheduleWindowKey: (value: unknown) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T(?:08:00|20:50)\+08:00$/.test(value),
}));
const xDailyJudgementMocks = vi.hoisted(() => ({
  claimNextXDailyJudgement: vi.fn(),
  getXDailyJudgementContext: vi.fn(),
  completeXDailyJudgement: vi.fn(),
  failXDailyJudgement: vi.fn(),
}));
const xVerificationReplayMocks = vi.hoisted(() => ({
  createXVerificationReplay: vi.fn(),
  claimXVerificationReplay: vi.fn(),
  getXVerificationReplayContext: vi.fn(),
  completeXVerificationReplay: vi.fn(),
  failXVerificationReplay: vi.fn(),
}));
const xVerificationAcceptanceMocks = vi.hoisted(() => ({
  getXVerificationAcceptanceContext: vi.fn(),
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
  getSourceType: vi.fn(),
  listSources: vi.fn(),
  updateSourceAdministration: vi.fn(),
  upsertDiscordSource: vi.fn(),
}));
const xIdentityMocks = vi.hoisted(() => ({
  resolveXSourceIdentity: vi.fn(),
}));
const xSourceMocks = vi.hoisted(() => ({
  createXSource: vi.fn(),
  removeXSource: vi.fn(),
  XSourceError: class XSourceError extends Error {},
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
  readXDay: vi.fn(),
}));

vi.mock("../../lib/auth/current-user", () => authMocks);
vi.mock("../../lib/auth/invites", () => inviteMocks);
vi.mock("../../lib/auth/worker", () => workerMocks);
vi.mock("../../lib/auth/login", () => loginMocks);
vi.mock("../../lib/auth/logout", () => logoutMocks);
vi.mock("../../lib/db/repositories/workers", () => workerRepositoryMocks);
vi.mock("../../lib/db/repositories/tasks", () => taskMocks);
vi.mock("../../lib/db/repositories/x-daily-judgements", () => xDailyJudgementMocks);
vi.mock("../../lib/db/repositories/x-v3-verification-replays", () => xVerificationReplayMocks);
vi.mock("../../lib/db/repositories/x-v3-verification-acceptance-runs", () => xVerificationAcceptanceMocks);
vi.mock("../../lib/db/repositories/windowed-sync", () => windowedSyncMocks);
vi.mock("../../lib/db/repositories/author-profiles", () => authorProfileMocks);
vi.mock("../../lib/db/repositories/sources", () => sourceMocks);
vi.mock("../../lib/db/repositories/x-identities", () => xIdentityMocks);
vi.mock("../../lib/db/repositories/x-sources", () => xSourceMocks);
vi.mock("../../lib/db/repositories/rules", () => ruleMocks);
vi.mock("../../lib/db/repositories/reader", () => readerMocks);

import { GET as getAdminInvites, POST as postAdminInvite } from "./admin/invites/route";
import { POST as postLogin } from "./auth/login/route";
import { POST as postLogout } from "./auth/logout/route";
import { POST as postEnrol } from "./worker/enrol/route";
import { POST as postHeartbeat } from "./worker/heartbeat/route";
import { POST as postPersist } from "./worker/tasks/[taskId]/persist/route";
import { POST as postResult } from "./worker/tasks/[taskId]/result/route";
import { POST as postCaptureSegment } from "./worker/tasks/[taskId]/capture-segments/route";
import { POST as postRangeComplete } from "./worker/tasks/[taskId]/range-complete/route";
import { GET as getAdminTaskDetail } from "./admin/tasks/[taskId]/route";
import { PATCH as patchAdminSource, POST as postAdminSource } from "./admin/sources/route";
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
import { GET as getXReader } from "./reader/x/route";
import { POST as postScheduleTick } from "./worker/schedule/tick/route";
import { GET as getDailyFactContext } from "./worker/tasks/[taskId]/daily-fact-context/route";
import { POST as postResolveAuthorProfiles } from "./worker/tasks/[taskId]/resolve-author-profiles/route";
import { POST as postResolveXIdentity } from "./worker/x-sources/[sourceId]/resolve-identity/route";
import { DELETE as deleteXSource } from "./admin/x/sources/[sourceId]/route";
import { POST as postAdminXSource } from "./admin/x/sources/route";
import { POST as postAuthInvite } from "./auth/invite/route";
import { POST as postXDailyJudgementClaim } from "./worker/x-daily-judgements/claim/route";
import { POST as postXDailyJudgementContext } from "./worker/x-daily-judgements/[runId]/context/route";
import { POST as postXDailyJudgementComplete } from "./worker/x-daily-judgements/[runId]/complete/route";
import { POST as postXDailyJudgementFailure } from "./worker/x-daily-judgements/[runId]/failure/route";
import { POST as postCreateXVerificationReplay } from "./admin/x/v3-verification-replays/route";
import { POST as postClaimXVerificationReplay } from "./worker/x-v3-verification-replays/[replayId]/claim/route";
import { POST as postXVerificationReplayContext } from "./worker/x-v3-verification-replays/[replayId]/context/route";
import { POST as postXVerificationReplayComplete } from "./worker/x-v3-verification-replays/[replayId]/complete/route";
import { POST as postXVerificationReplayFailure } from "./worker/x-v3-verification-replays/[replayId]/failure/route";
import { POST as postXVerificationAcceptanceContext } from "./worker/x-v3-verification-acceptance-runs/[acceptanceRunId]/context/route";

function jsonRequest(path: string, body: unknown, headers: Record<string, string> = {}, method = "POST") {
  return new Request(`http://localhost${path}`, {
    method,
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

function rawJsonRequest(path: string, body: string, headers: Record<string, string> = {}) {
  return new Request(`http://localhost${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body,
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

const xIdentitySourceId = "11111111-1111-4111-8111-111111111111";

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
    vi.stubEnv("INVITE_CODE_PEPPER", "fixture-invite-pepper");
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-1", role: "user", email: "user@example.invalid" });
    workerMocks.authenticateWorker.mockResolvedValue(null);
  });

  it("rejects unauthenticated X identity resolution without invoking the repository", async () => {
    const response = await postResolveXIdentity(
      jsonRequest(`/api/worker/x-sources/${xIdentitySourceId}/resolve-identity`, {
        parameter_version: "v2-identity",
        account_id: "fixture_handle",
      }),
      { params: Promise.resolve({ sourceId: xIdentitySourceId }) },
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(xIdentityMocks.resolveXSourceIdentity).not.toHaveBeenCalled();
  });

  it.each([
    { parameter_version: "v2-identity" },
    { parameter_version: "v2-identity", account_id: "fixture_handle", unexpected: true },
    { parameter_version: "v2-identity", account_id: "@fixture_handle" },
    { parameter_version: "v2-identity", account_id: "Fixture_Handle" },
  ])("rejects an invalid X identity resolution payload", async (body) => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });

    const response = await postResolveXIdentity(
      jsonRequest(`/api/worker/x-sources/${xIdentitySourceId}/resolve-identity`, body),
      { params: Promise.resolve({ sourceId: xIdentitySourceId }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_identity_resolution" });
    expect(xIdentityMocks.resolveXSourceIdentity).not.toHaveBeenCalled();
  });

  it("rejects malformed X identity resolution JSON without invoking the repository", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });

    const response = await postResolveXIdentity(
      rawJsonRequest(`/api/worker/x-sources/${xIdentitySourceId}/resolve-identity`, "{invalid"),
      { params: Promise.resolve({ sourceId: xIdentitySourceId }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_identity_resolution" });
    expect(xIdentityMocks.resolveXSourceIdentity).not.toHaveBeenCalled();
  });

  it("passes an authenticated Worker identity resolution request to the repository and returns only the identity DTO", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xIdentityMocks.resolveXSourceIdentity.mockResolvedValue({
      sourceId: xIdentitySourceId,
      accountId: "fixture_handle",
      resolutionStatus: "resolved",
      parameterVersion: "v2-identity",
      idempotent: false,
    });

    const response = await postResolveXIdentity(
      jsonRequest(`/api/worker/x-sources/${xIdentitySourceId}/resolve-identity`, {
        parameter_version: "v2-identity",
        account_id: "fixture_handle",
      }, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ sourceId: xIdentitySourceId }) },
    );

    expect(response.status).toBe(200);
    const body = await response.clone().text();
    expect(body).not.toContain("profile");
    expect(body).not.toContain("url");
    expect(body).not.toContain("cookie");
    expect(body).not.toContain("source_key");
    expect(body).not.toContain("account_id");
    expect(body).not.toContain("fixture_handle");
    expect(await response.json()).toEqual({
      identity: {
        resolution_status: "resolved",
        parameter_version: "v2-identity",
        idempotent: false,
      },
    });
    expect(xIdentityMocks.resolveXSourceIdentity).toHaveBeenCalledWith({
      sourceId: xIdentitySourceId,
      workerId: "worker-1",
      parameterVersion: "v2-identity",
      accountId: "fixture_handle",
    });
  });

  it("maps an unauthorized Worker identity resolution to a fixed forbidden response", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xIdentityMocks.resolveXSourceIdentity.mockRejectedValue({ message: "worker_not_authorized" });

    const response = await postResolveXIdentity(
      jsonRequest(`/api/worker/x-sources/${xIdentitySourceId}/resolve-identity`, {
        parameter_version: "v2-identity",
        account_id: "fixture_handle",
      }),
      { params: Promise.resolve({ sourceId: xIdentitySourceId }) },
    );

    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "worker_not_authorized" });
  });

  it.each(["x_identity_conflict", "x_identity_activation_blocked"])("maps %s to a fixed conflict response", async (code) => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xIdentityMocks.resolveXSourceIdentity.mockRejectedValue({ message: code });

    const response = await postResolveXIdentity(
      jsonRequest(`/api/worker/x-sources/${xIdentitySourceId}/resolve-identity`, {
        parameter_version: "v2-identity",
        account_id: "fixture_handle",
      }),
      { params: Promise.resolve({ sourceId: xIdentitySourceId }) },
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: code });
  });

  it.each([
    ["source_not_found", 404, "source_not_found"],
    ["source_parameter_version_mismatch", 422, "invalid_x_identity_resolution"],
    ["invalid_x_identity", 422, "invalid_x_identity_resolution"],
    ["unexpected repository error", 503, "x_identity_resolution_rejected"],
  ])("maps %s to only its fixed error response", async (message, status, error) => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xIdentityMocks.resolveXSourceIdentity.mockRejectedValue({ message });

    const response = await postResolveXIdentity(
      jsonRequest(`/api/worker/x-sources/${xIdentitySourceId}/resolve-identity`, {
        parameter_version: "v2-identity",
        account_id: "fixture_handle",
      }),
      { params: Promise.resolve({ sourceId: xIdentitySourceId }) },
    );

    expect(response.status).toBe(status);
    expect(await response.json()).toEqual({ error });
  });

  it("blocks ordinary users from admin invite creation without revealing records", async () => {
    const response = await postAdminInvite(jsonRequest("/api/admin/invites", { purpose: "user" }));
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "forbidden" });
    expect(inviteMocks.createOneTimeInvite).not.toHaveBeenCalled();
    expect(inviteMocks.createOneTimeUserInvite).not.toHaveBeenCalled();
  });

  it("blocks ordinary users from admin task detail without reading evidence", async () => {
    const response = await getAdminTaskDetail(new Request("http://localhost/api/admin/tasks/task-1"), {
      params: Promise.resolve({ taskId: "task-1" }),
    });
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "forbidden" });
    expect(taskMocks.getTaskDetail).not.toHaveBeenCalled();
  });

  it("blocks ordinary users from creating Discord or X sources", async () => {
    const discord = await postAdminSource(jsonRequest("/api/admin/sources", { display_name: "Research · #daily" }));
    const x = await postAdminXSource(jsonRequest("/api/admin/x/sources", { display_name: "Researcher", requested_handle: "researcher" }));

    expect(discord.status).toBe(403);
    expect(x.status).toBe(403);
    expect(sourceMocks.upsertDiscordSource).not.toHaveBeenCalled();
    expect(xSourceMocks.createXSource).not.toHaveBeenCalled();
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

  it("treats the X reader all selections as an unfiltered safe reader query", async () => {
    readerMocks.readXDay.mockResolvedValue([]);

    const response = await getXReader(new Request("http://localhost/api/reader/x?source=all&date=all"));

    expect(response.status).toBe(200);
    expect(readerMocks.readXDay).toHaveBeenCalledWith({ sourceKey: undefined, date: undefined });
  });

  it("returns only the safe X date-reader DTO to an authenticated ordinary user", async () => {
    readerMocks.readXDay.mockResolvedValue([{
      naturalDate: "2099-01-01",
      judgement: {
        visible: true,
        batches: [{
          cutoffAt: "2099-01-01T12:00:00.000Z", coverageStatus: "partial", status: "succeeded", revision: 2,
          stockViewpoints: [{ statement: "Synthetic judgement", supportingDisplayNames: ["Fixture source"], dissentingDisplayNames: [], uncertainties: [] }],
          marketIndustryViewpoints: [], uncertainties: [], excludedSourceCount: 1,
        }],
      },
      bloggers: [],
    }]);

    const response = await getXReader(new Request("http://localhost/api/reader/x"));
    const body = await response.json();
    const serialized = JSON.stringify(body);

    expect(response.status).toBe(200);
    expect(body.days[0].judgement.batches[0]).toMatchObject({ excludedSourceCount: 1, revision: 2 });
    for (const forbidden of ["analysis_ids", "evidence_post_ids", "task_id", "raw post", "provider", "/Users/"]) expect(serialized).not.toContain(forbidden);
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

  it("blocks ordinary users from removing an X source", async () => {
    const response = await deleteXSource(
      jsonRequest("/api/admin/x/sources/source-x", { confirmation_name: "AllInvestHK" }, {}, "DELETE"),
      { params: Promise.resolve({ sourceId: "source-x" }) },
    );

    expect(response.status).toBe(403);
    expect(xSourceMocks.removeXSource).not.toHaveBeenCalled();
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

  it("permits an X source name when binding its Worker", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    sourceMocks.getSourceType.mockResolvedValue("x");
    sourceMocks.updateSourceAdministration.mockResolvedValue({
      id: "x-source-1",
      source_type: "x",
      display_name: "Researcher A",
      enabled: true,
      authorized_worker_id: "worker-1",
    });

    const response = await patchAdminSource(jsonRequest("/api/admin/sources", {
      source_id: "x-source-1",
      display_name: "Researcher A",
      enabled: true,
      authorized_worker_id: "worker-1",
    }));

    expect(response.status).toBe(200);
    expect(sourceMocks.getSourceType).toHaveBeenCalledWith("x-source-1");
    expect(sourceMocks.updateSourceAdministration).toHaveBeenCalledWith({
      sourceId: "x-source-1",
      displayName: "Researcher A",
      enabled: true,
      authorizedWorkerId: "worker-1",
    });
  });

  it("creates sources with server-owned metadata and returns only safe creation receipts", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    sourceMocks.upsertDiscordSource.mockResolvedValue({
      id: "source-private", source_key: "discord:private", source_type: "discord", display_name: "Research · #daily", parameter_version: "discord-standard-v1",
    });
    xSourceMocks.createXSource.mockResolvedValue({
      id: "source-private", sourceKey: "x:private", sourceType: "x", displayName: "Researcher", parameterVersion: "x-standard-v2", resolutionStatus: "pending",
    });

    const discord = await postAdminSource(jsonRequest("/api/admin/sources", { display_name: "Research · #daily" }));
    const x = await postAdminXSource(jsonRequest("/api/admin/x/sources", { display_name: "Researcher", requested_handle: "@researcher" }));

    expect(discord.status).toBe(201);
    expect(await discord.json()).toEqual({ source: { source_type: "discord", display_name: "Research · #daily" } });
    expect(x.status).toBe(201);
    expect(await x.json()).toEqual({ source: { source_type: "x", display_name: "Researcher", resolution_status: "pending" } });
    expect(sourceMocks.upsertDiscordSource).toHaveBeenCalledWith(expect.objectContaining({
      sourceKey: expect.stringMatching(/^discord:[0-9a-f-]{36}$/), parameterVersion: "discord-standard-v1", createdBy: "admin-1", enabled: true,
    }));
    expect(xSourceMocks.createXSource).toHaveBeenCalledWith(expect.objectContaining({
      sourceKey: expect.stringMatching(/^x:[0-9a-f-]{36}$/), parameterVersion: "x-standard-v2", requestedHandle: "researcher", actorId: "admin-1",
    }));
  });

  it("reports that X creation is temporarily unavailable when no eligible Worker is online", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    xSourceMocks.createXSource.mockRejectedValueOnce(new xSourceMocks.XSourceError("x_worker_unavailable"));

    const response = await postAdminXSource(jsonRequest("/api/admin/x/sources", {
      display_name: "Researcher", requested_handle: "researcher",
    }));

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({ error: "x_worker_unavailable" });
  });

  it("rejects client-supplied creation metadata", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });

    const discord = await postAdminSource(jsonRequest("/api/admin/sources", {
      display_name: "Research · #daily", source_key: "forged", parameter_version: "forged",
    }));
    const x = await postAdminXSource(jsonRequest("/api/admin/x/sources", {
      display_name: "Researcher", requested_handle: "researcher", source_key: "forged", parameter_version: "forged",
    }));

    expect(discord.status).toBe(422);
    expect(x.status).toBe(422);
    expect(sourceMocks.upsertDiscordSource).not.toHaveBeenCalled();
    expect(xSourceMocks.createXSource).not.toHaveBeenCalled();
  });

  it("requires exact confirmation and returns no internal source fields when removing X", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    xSourceMocks.removeXSource.mockRejectedValueOnce(new xSourceMocks.XSourceError("confirmation_mismatch"));

    const mismatch = await deleteXSource(
      jsonRequest("/api/admin/x/sources/source-x", { confirmation_name: "Wrong" }, {}, "DELETE"),
      { params: Promise.resolve({ sourceId: "source-x" }) },
    );
    expect(mismatch.status).toBe(409);
    await expect(mismatch.json()).resolves.toEqual({ error: "confirmation_mismatch" });

    xSourceMocks.removeXSource.mockResolvedValueOnce({ action: "archived", sourceId: "source-x", displayName: "AllInvestHK" });
    const removed = await deleteXSource(
      jsonRequest("/api/admin/x/sources/source-x", { confirmation_name: "AllInvestHK" }, {}, "DELETE"),
      { params: Promise.resolve({ sourceId: "source-x" }) },
    );
    const body = await removed.json();
    expect(removed.status).toBe(200);
    expect(body).toEqual({ removal: { action: "archived", display_name: "AllInvestHK" } });
    expect(JSON.stringify(body)).not.toContain("source-x");
    expect(xSourceMocks.removeXSource).toHaveBeenLastCalledWith({
      sourceId: "source-x", actorId: "admin-1", confirmationName: "AllInvestHK",
    });
  });

  it("rejects malformed X removal input without calling the lifecycle repository", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });

    const response = await deleteXSource(
      jsonRequest("/api/admin/x/sources/source-x", { confirmation_name: "AllInvestHK", force: true }, {}, "DELETE"),
      { params: Promise.resolve({ sourceId: "source-x" }) },
    );

    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toEqual({ error: "invalid_x_source_removal" });
    expect(xSourceMocks.removeXSource).not.toHaveBeenCalled();
  });

  it("creates a configurable eight-character user invite only for an admin", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    inviteMocks.createOneTimeUserInvite.mockResolvedValue({
      inviteId: "invite-user-1",
      code: "Ab3xYz91",
      purpose: "user",
      expiresAt: "2099-01-01T02:00:00.000Z",
      validityHours: 2,
      codeMask: "Ab••••91",
    });

    const response = await postAdminInvite(
      jsonRequest("/api/admin/invites", { purpose: "user", expires_in_hours: 2 }),
    );
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      invite_id: "invite-user-1",
      code: "Ab3xYz91",
      purpose: "user",
      expires_at: "2099-01-01T02:00:00.000Z",
    });
    expect(inviteMocks.createOneTimeUserInvite).toHaveBeenCalledWith(expect.objectContaining({
      role: "user",
      createdBy: "admin-1",
      expiresInHours: 2,
    }));
  });

  it.each([
    { purpose: "user", expires_in_hours: 0 },
    { purpose: "user", expires_in_hours: 1.5 },
    { purpose: "user", expires_in_hours: 169 },
    { purpose: "user", expires_in_hours: 2, unexpected: true },
  ])("rejects invalid user invite creation parameters", async (body) => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });

    const response = await postAdminInvite(jsonRequest("/api/admin/invites", body));
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_invite_parameters" });
    expect(inviteMocks.createOneTimeUserInvite).not.toHaveBeenCalled();
  });

  it("returns only safe recent user invite metadata to an admin", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    inviteMocks.listRecentUserInvites.mockResolvedValue([{
      codeMask: "Ab••••91",
      validityHours: 2,
      createdAt: "2099-01-01T00:00:00.000Z",
      expiresAt: "2099-01-01T02:00:00.000Z",
      consumedAt: null,
    }]);

    const response = await getAdminInvites(new Request("http://localhost/api/admin/invites"));
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ invites: [{
      code_mask: "Ab••••91",
      validity_hours: 2,
      created_at: "2099-01-01T00:00:00.000Z",
      expires_at: "2099-01-01T02:00:00.000Z",
      consumed_at: null,
    }] });
    expect(body).not.toHaveProperty("code");
    expect(body).not.toHaveProperty("code_hash");
  });

  it("blocks ordinary users from reading the invite list", async () => {
    const response = await getAdminInvites(new Request("http://localhost/api/admin/invites"));
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "forbidden" });
    expect(inviteMocks.listRecentUserInvites).not.toHaveBeenCalled();
  });

  it("returns one generic error for any failed invite redemption", async () => {
    inviteMocks.redeemInviteAccount.mockResolvedValue({ ok: false, error: "invite_replayed" });

    const response = await postAuthInvite(jsonRequest("/api/auth/invite", {
      code: "wrong-code",
      email: "person@example.invalid",
      password: "password-123",
    }, { "x-forwarded-for": "192.0.2.10" }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_invite" });
    expect(inviteMocks.redeemInviteAccount).toHaveBeenCalledWith(expect.objectContaining({
      code: "wrong-code",
      sourceHash: expect.any(String),
    }));
  });

  it("returns a one-time Worker invite code only to an admin", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    inviteMocks.createOneTimeWorkerInvite.mockResolvedValue({
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
    expect(inviteMocks.createOneTimeInvite).not.toHaveBeenCalled();
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
    taskMocks.scheduleDueSourceTasks.mockResolvedValue({
      scheduled_at: "2099-01-01T00:00:00Z",
      tasks: [{ id: "scheduled-task-1", source_id: "source-1", idempotent: false }],
    });

    const first = await postScheduleTick(
      jsonRequest("/api/worker/schedule/tick", {}, { authorization: "Bearer device-secret" }),
    );
    expect(first.status).toBe(200);
    expect(await first.json()).toMatchObject({ tasks: [{ id: "scheduled-task-1", source_id: "source-1" }] });
    expect(taskMocks.scheduleDueSourceTasks).toHaveBeenCalledWith("worker-1");
    expect(taskMocks.scheduleDiscordSyncTasks).not.toHaveBeenCalled();
  });

  it("returns a safe X daily judgement claim to exactly one authenticated Worker", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.claimNextXDailyJudgement
      .mockResolvedValueOnce({
        run_id: "11111111-1111-4111-8111-111111111111",
        attempt: 1,
        lease_expires_at: "2099-01-01T00:10:00.000Z",
        batch: {
          id: "22222222-2222-4222-8222-222222222222",
          natural_date: "2099-01-01",
          cutoff_at: "2099-01-01T00:00:00.000Z",
          coverage_status: "complete",
        },
      })
      .mockResolvedValueOnce(null);

    const first = await postXDailyJudgementClaim(jsonRequest("/api/worker/x-daily-judgements/claim", {}, { authorization: "Bearer device-secret" }));
    const second = await postXDailyJudgementClaim(jsonRequest("/api/worker/x-daily-judgements/claim", {}, { authorization: "Bearer second-device-secret" }));

    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({
      run_id: "11111111-1111-4111-8111-111111111111",
      attempt: 1,
      lease_expires_at: "2099-01-01T00:10:00.000Z",
      batch: {
        id: "22222222-2222-4222-8222-222222222222",
        natural_date: "2099-01-01",
        cutoff_at: "2099-01-01T00:00:00.000Z",
        coverage_status: "complete",
      },
    });
    expect(second.status).toBe(204);
  });

  it("rejects non-Workers and an empty context request before judgement repositories", async () => {
    const unauthenticated = await postXDailyJudgementClaim(jsonRequest("/api/worker/x-daily-judgements/claim", {}));
    expect(unauthenticated.status).toBe(401);
    expect(xDailyJudgementMocks.claimNextXDailyJudgement).not.toHaveBeenCalled();

    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    const empty = await postXDailyJudgementContext(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/context", {}),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );
    expect(empty.status).toBe(422);
    expect(await empty.json()).toEqual({ error: "invalid_x_daily_judgement_context" });
    expect(xDailyJudgementMocks.getXDailyJudgementContext).not.toHaveBeenCalled();
  });

  it("returns frozen included projections without canonical message content", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.getXDailyJudgementContext.mockResolvedValue({
      run_id: "11111111-1111-4111-8111-111111111111",
      batch_id: "22222222-2222-4222-8222-222222222222",
      attempt: 1,
      prompt_version: "v3-x-cross-blogger-1",
      sources: [{ source_id: "33333333-3333-4333-8333-333333333333", display_name: "Fixture researcher", window_segments: [] }],
      excluded_sources: [{ source_id: "44444444-4444-4444-8444-444444444444", display_name: "Excluded fixture", reason: "deadline_elapsed" }],
    });

    const response = await postXDailyJudgementContext(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/context", { attempt: 1 }),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );
    const body = await response.json();
    expect(response.status).toBe(200);
    expect(body.sources).toEqual([{ source_id: "33333333-3333-4333-8333-333333333333", display_name: "Fixture researcher", window_segments: [] }]);
    expect(JSON.stringify(body)).not.toContain("canonical_messages");
    expect(JSON.stringify(body)).not.toContain("content");
  });

  it("rejects malformed or out-of-batch judgement references before completion", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.getXDailyJudgementContext.mockResolvedValue({
      run_id: "11111111-1111-4111-8111-111111111111",
      batch_id: "22222222-2222-4222-8222-222222222222",
      attempt: 1,
      prompt_version: "v3-x-cross-blogger-1",
      sources: [{
        source_id: "33333333-3333-4333-8333-333333333333",
        display_name: "Fixture researcher",
        window_segments: [{
          id: "44444444-4444-4444-8444-444444444444",
          occurred_from_at: "2099-01-01T00:00:00.000Z",
          occurred_through_at: "2099-01-01T00:01:00.000Z",
          viewpoints: [], uncertainties: [],
          analyses: [{
            post_id: "post-a@1", blogger_viewpoint: null, arguments: [], quoted_post_viewpoint: null,
            uncertainties: [], evidence_post_ids: ["post-a"],
          }],
        }],
      }],
      excluded_sources: [],
    });
    const response = await postXDailyJudgementComplete(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/complete", {
        run_id: "11111111-1111-4111-8111-111111111111",
        attempt: 1,
        schema_version: "v2-x-cross-blogger",
        provider: "codex_cli",
        model_reported: null,
        prompt_version: "v2-x-cross-blogger-1",
        stock_viewpoints: [{
          statement: "Synthetic statement",
          supporting_source_ids: ["55555555-5555-4555-8555-555555555555"],
          dissenting_source_ids: [],
          analysis_ids: ["post-a@1"],
          evidence_post_ids: ["post-a"],
          uncertainties: [],
        }],
        market_industry_viewpoints: [],
        uncertainties: [],
      }),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_daily_judgement_completion" });
    expect(xDailyJudgementMocks.completeXDailyJudgement).not.toHaveBeenCalled();
  });

  it("accepts a frozen, versioned completion without accepting any raw model payload", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.getXDailyJudgementContext.mockResolvedValue({
      run_id: "11111111-1111-4111-8111-111111111111", attempt: 1,
      batch_id: "22222222-2222-4222-8222-222222222222",
      prompt_version: "v3-x-cross-blogger-1",
      sources: [{
        source_id: "33333333-3333-4333-8333-333333333333", display_name: "Fixture researcher",
        window_segments: [{
          id: "44444444-4444-4444-8444-444444444444", schema_version: "v3-x-window", prompt_version: "v3-x-window-1",
          occurred_from_at: "2099-01-01T00:00:00.000Z", occurred_through_at: "2099-01-01T00:01:00.000Z",
          segment_output: { schema_version: "v3-x-window", analysis_ids: ["post-a@2"], evidence_post_ids: ["post-a"] },
          analyses: [{ analysis_id: "post-a@2", schema_version: "v3-x-post-analysis", prompt_version: "v3-x-post-analysis-1", analysis_output: { post_id: "post-a", evidence_post_ids: ["post-a"] }, evidence_post_ids: ["post-a"] }],
        }],
      }], excluded_sources: [],
    });
    xDailyJudgementMocks.completeXDailyJudgement.mockResolvedValue({ status: "succeeded" });
    const completion = {
      run_id: "11111111-1111-4111-8111-111111111111", attempt: 1, schema_version: "v3-x-cross-blogger",
      provider: "codex_cli", model_reported: null, prompt_version: "v3-x-cross-blogger-1",
      security_industry_viewpoints: [{
        statement: "一位博主明确倾向买入该标的。", action_intent: "buy", action_scope: "该标的", conditions: ["需求改善"],
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [], analysis_ids: ["post-a@2"], evidence_post_ids: ["post-a"], uncertainties: [],
      }], market_structure_viewpoints: [], strategy_mindset_viewpoints: [], uncertainties: [],
    };

    const response = await postXDailyJudgementComplete(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/complete", completion),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );
    expect(response.status).toBe(200);
    expect(xDailyJudgementMocks.completeXDailyJudgement).toHaveBeenCalledWith(completion, "worker-1");
  });

  it.each([
    {
      name: "cross-source analysis splicing",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-b@1"],
        evidence_post_ids: ["post-b"],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "duplicate source IDs",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333", "33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "duplicate analysis IDs",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1", "post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "duplicate evidence IDs",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a", "post-a"],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "support and dissent overlap",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "empty evidence",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: [],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "incomplete analysis evidence",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a"],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "opaque source ID in statement",
      item: {
        statement: "33333333-3333-4333-8333-333333333333 supports this statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "opaque no-new frozen source ID in global uncertainty",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: [],
      },
      uncertainties: ["77777777-7777-4777-8777-777777777777 has no new information"],
    },
    {
      name: "opaque no-new frozen source ID in item uncertainty",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: ["77777777-7777-4777-8777-777777777777 needs context"],
      },
      uncertainties: [],
    },
    {
      name: "opaque evidence ID in uncertainty",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: ["quote-a needs more context"],
      },
      uncertainties: [],
    },
    {
      name: "opaque analysis ID in global uncertainty",
      item: {
        statement: "Synthetic statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [],
        analysis_ids: ["post-a@1"],
        evidence_post_ids: ["post-a", "quote-a"],
        uncertainties: [],
      },
      uncertainties: ["post-a@1 needs more context"],
    },
    ...[
      ["batch", "abcdefab-cdef-4abc-8def-abcdefabcdef"],
      ["run", "11111111-1111-4111-8111-111111111111"],
      ["segment", "44444444-4444-4444-8444-444444444444"],
    ].flatMap(([kind, opaqueId]) => ([
      {
        name: `opaque ${kind} ID in statement`,
        item: {
          statement: `${opaqueId} supports this statement`,
          supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
          dissenting_source_ids: [], analysis_ids: ["post-a@1"], evidence_post_ids: ["post-a", "quote-a"], uncertainties: [],
        },
        uncertainties: [],
      },
      {
        name: `opaque ${kind} ID in item uncertainty`,
        item: {
          statement: "Synthetic statement",
          supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
          dissenting_source_ids: [], analysis_ids: ["post-a@1"], evidence_post_ids: ["post-a", "quote-a"],
          uncertainties: [`${opaqueId} needs context`],
        },
        uncertainties: [],
      },
      {
        name: `opaque ${kind} ID in global uncertainty`,
        item: {
          statement: "Synthetic statement",
          supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
          dissenting_source_ids: [], analysis_ids: ["post-a@1"], evidence_post_ids: ["post-a", "quote-a"], uncertainties: [],
        },
        uncertainties: [`${opaqueId} needs context`],
      },
    ])),
    {
      name: "uppercase variant of opaque batch UUID",
      item: {
        statement: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF supports this statement",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [], analysis_ids: ["post-a@1"], evidence_post_ids: ["post-a", "quote-a"], uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "single-source strong consensus wording",
      item: {
        statement: "市场已确认估值见底。",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: [], analysis_ids: ["post-a@1"], evidence_post_ids: ["post-a", "quote-a"], uncertainties: [],
      },
      uncertainties: [],
    },
    {
      name: "dissenting strong consensus wording",
      item: {
        statement: "多位博主一致认为估值见底。",
        supporting_source_ids: ["33333333-3333-4333-8333-333333333333"],
        dissenting_source_ids: ["55555555-5555-4555-8555-555555555555"],
        analysis_ids: ["post-a@1", "post-b@1"], evidence_post_ids: ["post-a", "quote-a", "post-b"], uncertainties: [],
      },
      uncertainties: [],
    },
  ])("rejects $name at the HTTP completion boundary", async ({ item, uncertainties }) => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.getXDailyJudgementContext.mockResolvedValue({
      run_id: "11111111-1111-4111-8111-111111111111",
      batch_id: "abcdefab-cdef-4abc-8def-abcdefabcdef",
      attempt: 1,
      prompt_version: "v3-x-cross-blogger-1",
      sources: [
        {
          source_id: "33333333-3333-4333-8333-333333333333",
          display_name: "Fixture researcher A",
          window_segments: [{
            id: "44444444-4444-4444-8444-444444444444",
            occurred_from_at: "2099-01-01T00:00:00.000Z",
            occurred_through_at: "2099-01-01T00:01:00.000Z",
            viewpoints: [], uncertainties: [],
            analyses: [{
              post_id: "post-a@1", blogger_viewpoint: null, arguments: [], quoted_post_viewpoint: null,
              uncertainties: [], evidence_post_ids: ["post-a", "quote-a"],
            }],
          }],
        },
        {
          source_id: "55555555-5555-4555-8555-555555555555",
          display_name: "Fixture researcher B",
          window_segments: [{
            id: "66666666-6666-4666-8666-666666666666",
            occurred_from_at: "2099-01-01T00:00:00.000Z",
            occurred_through_at: "2099-01-01T00:01:00.000Z",
            viewpoints: [], uncertainties: [],
            analyses: [{
              post_id: "post-b@1", blogger_viewpoint: null, arguments: [], quoted_post_viewpoint: null,
              uncertainties: [], evidence_post_ids: ["post-b"],
            }],
          }],
        },
      ],
      excluded_sources: [{
        source_id: "77777777-7777-4777-8777-777777777777",
        display_name: "No-new fixture researcher",
        reason: "no_new_information",
      }],
    });

    const response = await postXDailyJudgementComplete(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/complete", {
        run_id: "11111111-1111-4111-8111-111111111111",
        attempt: 1,
        schema_version: "v2-x-cross-blogger",
        provider: "codex_cli",
        model_reported: null,
        prompt_version: "v2-x-cross-blogger-1",
        stock_viewpoints: [item],
        market_industry_viewpoints: [],
        uncertainties,
      }),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_daily_judgement_completion" });
    expect(xDailyJudgementMocks.completeXDailyJudgement).not.toHaveBeenCalled();
  });

  it("rejects a legacy no-new context before DB completion", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.getXDailyJudgementContext.mockResolvedValue({
      run_id: "11111111-1111-4111-8111-111111111111",
      batch_id: "abcdefab-cdef-4abc-8def-abcdefabcdef",
      attempt: 1,
      prompt_version: "v2-x-cross-blogger-1",
      sources: [],
      excluded_sources: [{
        source_id: "77777777-7777-4777-8777-777777777777",
        display_name: "No-new fixture researcher",
        reason: "no_new_information",
      }],
    });

    const response = await postXDailyJudgementComplete(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/complete", {
        run_id: "11111111-1111-4111-8111-111111111111",
        attempt: 1,
        schema_version: "v2-x-cross-blogger",
        provider: "codex_cli",
        model_reported: null,
        prompt_version: "v2-x-cross-blogger-1",
        stock_viewpoints: [],
        market_industry_viewpoints: [],
        uncertainties: [],
      }),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_x_daily_judgement_completion" });
    expect(xDailyJudgementMocks.completeXDailyJudgement).not.toHaveBeenCalled();
  });

  it.each(["file:///private/worker/output.json", "x".repeat(161)])(
    "rejects unsafe or raw-output-sized model_reported metadata before any repository call",
    async (modelReported) => {
      workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
      const response = await postXDailyJudgementComplete(
        jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/complete", {
          run_id: "11111111-1111-4111-8111-111111111111", attempt: 1, schema_version: "v2-x-cross-blogger",
          provider: "codex_cli", model_reported: modelReported, prompt_version: "v2-x-cross-blogger-1",
          stock_viewpoints: [], market_industry_viewpoints: [], uncertainties: [],
        }),
        { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
      );
      expect(response.status).toBe(422);
      expect(await response.json()).toEqual({ error: "invalid_x_daily_judgement_completion" });
      expect(xDailyJudgementMocks.getXDailyJudgementContext).not.toHaveBeenCalled();
      expect(xDailyJudgementMocks.completeXDailyJudgement).not.toHaveBeenCalled();
    },
  );

  it("maps a stale X daily judgement attempt to 409 and only accepts bounded failure classes", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.getXDailyJudgementContext.mockResolvedValue({
      run_id: "11111111-1111-4111-8111-111111111111",
      batch_id: "abcdefab-cdef-4abc-8def-abcdefabcdef",
      attempt: 1,
      prompt_version: "v2-x-cross-blogger-1",
      sources: [{ source_id: "source-a", display_name: "A", window_segments: [] }],
      excluded_sources: [],
    });
    xDailyJudgementMocks.completeXDailyJudgement.mockRejectedValue({ code: "PT409", message: "lease_mismatch" });
    const stale = await postXDailyJudgementComplete(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/complete", {
        run_id: "11111111-1111-4111-8111-111111111111", attempt: 1, schema_version: "v3-x-cross-blogger",
        provider: "codex_cli", model_reported: null, prompt_version: "v3-x-cross-blogger-1",
        security_industry_viewpoints: [], market_structure_viewpoints: [], strategy_mindset_viewpoints: [], uncertainties: [],
      }),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );
    expect(stale.status).toBe(409);
    expect(await stale.json()).toEqual({ error: "lease_mismatch" });

    const invalidFailure = await postXDailyJudgementFailure(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/failure", { attempt: 1, failure_class: "raw_output" }),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );
    expect(invalidFailure.status).toBe(422);
    expect(await invalidFailure.json()).toEqual({ error: "invalid_x_daily_judgement_failure" });
    expect(xDailyJudgementMocks.failXDailyJudgement).not.toHaveBeenCalled();
  });

  it("reports a permitted judgement failure without calling any source-task repository", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xDailyJudgementMocks.failXDailyJudgement.mockResolvedValue({
      run_id: "11111111-1111-4111-8111-111111111111", attempt: 1, status: "retryable_failed", failure_class: "timeout",
    });

    const response = await postXDailyJudgementFailure(
      jsonRequest("/api/worker/x-daily-judgements/11111111-1111-4111-8111-111111111111/failure", { attempt: 1, failure_class: "timeout" }),
      { params: Promise.resolve({ runId: "11111111-1111-4111-8111-111111111111" }) },
    );
    expect(response.status).toBe(200);
    expect(xDailyJudgementMocks.failXDailyJudgement).toHaveBeenCalledWith(
      "11111111-1111-4111-8111-111111111111", 1, "worker-1", "timeout",
    );
    expect(taskMocks.recordTaskFailure).not.toHaveBeenCalled();
  });

  it("lets only an admin create the one-off X v3 verification replay from an exact source batch", async () => {
    const sourceBatchId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const denied = await postCreateXVerificationReplay(jsonRequest("/api/admin/x/v3-verification-replays", { source_batch_id: sourceBatchId }));
    expect(denied.status).toBe(403);
    expect(xVerificationReplayMocks.createXVerificationReplay).not.toHaveBeenCalled();

    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", role: "admin", email: "admin@example.invalid" });
    const malformed = await postCreateXVerificationReplay(jsonRequest("/api/admin/x/v3-verification-replays", { source_batch_id: sourceBatchId, unexpected: true }));
    expect(malformed.status).toBe(422);
    expect(xVerificationReplayMocks.createXVerificationReplay).not.toHaveBeenCalled();

    xVerificationReplayMocks.createXVerificationReplay.mockResolvedValue({ replayId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", status: "queued" });
    const created = await postCreateXVerificationReplay(jsonRequest("/api/admin/x/v3-verification-replays", { source_batch_id: sourceBatchId }));
    expect(created.status).toBe(202);
    expect(await created.json()).toEqual({ replay_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", status: "queued" });
    expect(xVerificationReplayMocks.createXVerificationReplay).toHaveBeenCalledWith(sourceBatchId, "admin-1");
  });

  it("rejects malformed one-off replay Worker requests before repository access", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    const invalidReplayId = "not-a-replay-id";
    const claim = await postClaimXVerificationReplay(
      jsonRequest(`/api/worker/x-v3-verification-replays/${invalidReplayId}/claim`, {}),
      { params: Promise.resolve({ replayId: invalidReplayId }) },
    );
    const context = await postXVerificationReplayContext(
      jsonRequest(`/api/worker/x-v3-verification-replays/${invalidReplayId}/context`, {}),
      { params: Promise.resolve({ replayId: invalidReplayId }) },
    );
    const complete = await postXVerificationReplayComplete(
      jsonRequest(`/api/worker/x-v3-verification-replays/${invalidReplayId}/complete`, { attempt: 1 }),
      { params: Promise.resolve({ replayId: invalidReplayId }) },
    );
    const failure = await postXVerificationReplayFailure(
      jsonRequest(`/api/worker/x-v3-verification-replays/${invalidReplayId}/failure`, { attempt: 1, failure_class: "raw_output" }),
      { params: Promise.resolve({ replayId: invalidReplayId }) },
    );

    for (const response of [claim, context, complete, failure]) expect(response.status).toBe(422);
    expect(xVerificationReplayMocks.claimXVerificationReplay).not.toHaveBeenCalled();
    expect(xVerificationReplayMocks.getXVerificationReplayContext).not.toHaveBeenCalled();
    expect(xVerificationReplayMocks.completeXVerificationReplay).not.toHaveBeenCalled();
    expect(xVerificationReplayMocks.failXVerificationReplay).not.toHaveBeenCalled();
  });

  it("returns frozen replay input only after the authenticated Worker has claimed the replay", async () => {
    const replayId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xVerificationReplayMocks.claimXVerificationReplay.mockResolvedValue({ replayId, attempt: 1, leaseExpiresAt: "2099-01-01T00:15:00.000Z" });
    xVerificationReplayMocks.getXVerificationReplayContext.mockResolvedValue({
      replay_id: replayId, attempt: 1,
      sources: [{ source_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", display_name: "Fixture", occurred_from_at: "2099-01-01T00:00:00.000Z", occurred_through_at: "2099-01-01T00:01:00.000Z", posts: [{ post_id: "post-1", content: "frozen worker input", occurred_at: "2099-01-01T00:00:00.000Z", post_url: "https://x.example/post/1", post_type: "post", quoted_post_id: null, reply_to_post_id: null, reposted_post_id: null, context_status: "resolved", attachments: [] }] }],
    });

    const claimed = await postClaimXVerificationReplay(
      jsonRequest(`/api/worker/x-v3-verification-replays/${replayId}/claim`, {}),
      { params: Promise.resolve({ replayId }) },
    );
    const context = await postXVerificationReplayContext(
      jsonRequest(`/api/worker/x-v3-verification-replays/${replayId}/context`, { attempt: 1 }),
      { params: Promise.resolve({ replayId }) },
    );

    expect(claimed.status).toBe(200);
    expect(await claimed.json()).toEqual({ replay_id: replayId, attempt: 1, lease_expires_at: "2099-01-01T00:15:00.000Z" });
    expect(context.status).toBe(200);
    expect(xVerificationReplayMocks.claimXVerificationReplay).toHaveBeenCalledWith(replayId, "worker-1");
    expect(xVerificationReplayMocks.getXVerificationReplayContext).toHaveBeenCalledWith(replayId, 1, "worker-1");
    expect(await context.json()).toMatchObject({ replay_id: replayId, sources: [{ posts: [{ content: "frozen worker input" }] }] });
  });

  it("returns the acceptance-run field that the acceptance Worker protocol requires", async () => {
    const acceptanceRunId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    xVerificationAcceptanceMocks.getXVerificationAcceptanceContext.mockResolvedValue({
      replay_id: acceptanceRunId,
      attempt: 1,
      sources: [],
    });

    const response = await postXVerificationAcceptanceContext(
      jsonRequest(`/api/worker/x-v3-verification-acceptance-runs/${acceptanceRunId}/context`, { attempt: 1 }),
      { params: Promise.resolve({ acceptanceRunId }) },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ acceptance_run_id: acceptanceRunId, attempt: 1, sources: [] });
    expect(xVerificationAcceptanceMocks.getXVerificationAcceptanceContext).toHaveBeenCalledWith(acceptanceRunId, 1, "worker-1");
  });

  it("rejects unauthenticated Workers and client-supplied schedule ranges", async () => {
    const unauthenticated = await postScheduleTick(jsonRequest("/api/worker/schedule/tick", {}));
    expect(unauthenticated.status).toBe(401);

    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    const invalid = await postScheduleTick(
      jsonRequest("/api/worker/schedule/tick", { window_key: "not-a-window" }, { authorization: "Bearer device-secret" }),
    );
    expect(invalid.status).toBe(422);
    expect(taskMocks.scheduleDueSourceTasks).not.toHaveBeenCalled();
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
    const rangeCompletionLog = vi.spyOn(console, "info").mockImplementation(() => undefined);
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
    expect(taskMocks.completeWindowedCaptureRange).toHaveBeenCalledWith(
      "task-window-1",
      1,
      "worker-1",
      expect.objectContaining({ range_complete: true }),
      expect.any(AbortSignal),
    );
    expect(rangeCompletionLog).toHaveBeenCalledWith(
      "range_completion_stage",
      expect.objectContaining({ stage: "rpc_succeeded" }),
    );
    rangeCompletionLog.mockRestore();
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

  it("maps a V2 range business conflict to 409", async () => {
    workerMocks.authenticateWorker.mockResolvedValue({ id: "worker-1", status: "online" });
    taskMocks.completeWindowedCaptureRange.mockRejectedValue({ code: "PT409", message: "lease_mismatch" });

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

  it("returns a safe database validation category for rejected window page persistence", async () => {
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
    taskMocks.persistWindowedCapturePage.mockRejectedValue({ code: "22023", message: "invalid_capture_segment" });

    const response = await postPersist(
      jsonRequest("/api/worker/tasks/task-1/persist", payload, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({
      error: "invalid_worker_persistence",
      failure_code: "invalid_capture_segment",
    });
  });

  it("returns a safe conflict category for rejected window page persistence", async () => {
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
    taskMocks.persistWindowedCapturePage.mockRejectedValue({ code: "23505", message: "conflicting_canonical_message" });

    const response = await postPersist(
      jsonRequest("/api/worker/tasks/task-1/persist", payload, { authorization: "Bearer device-secret" }),
      { params: Promise.resolve({ taskId: "task-1" }) },
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "conflicting_worker_persistence",
      failure_code: "conflicting_canonical_message",
    });
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
