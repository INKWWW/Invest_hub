import { beforeEach, describe, expect, it, vi } from "vitest";

const repositoryMocks = vi.hoisted(() => ({
  completeInvitedUserRegistration: vi.fn(),
  createInviteRecord: vi.fn(),
  consumeInvite: vi.fn(),
  listRecentUserInviteRecords: vi.fn(),
}));
const rateLimitMocks = vi.hoisted(() => ({
  canAttemptInviteRedemption: vi.fn(),
  recordFailedInviteRedemption: vi.fn(),
}));
const adminMocks = vi.hoisted(() => ({
  createUser: vi.fn(),
  deleteUser: vi.fn(),
  upsert: vi.fn(),
}));

vi.mock("../db/repositories/invites", () => repositoryMocks);
vi.mock("../db/repositories/invite-rate-limits", () => rateLimitMocks);
vi.mock("../db/supabase-server", () => ({
  createSupabaseAdminClient: () => ({
    auth: { admin: adminMocks },
    from: () => ({ upsert: adminMocks.upsert }),
  }),
}));

import {
  consumeWorkerInvite,
  createOneTimeUserInvite,
  createOneTimeWorkerInvite,
  redeemInviteAccount,
  redeemInviteCode,
} from "./invites";

describe("invite service boundaries", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("INVITE_CODE_PEPPER", "fixture-invite-pepper");
    repositoryMocks.createInviteRecord.mockResolvedValue({ id: "invite-1" });
    rateLimitMocks.canAttemptInviteRedemption.mockResolvedValue(true);
    rateLimitMocks.recordFailedInviteRedemption.mockResolvedValue(true);
    adminMocks.createUser.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
    adminMocks.deleteUser.mockResolvedValue({ error: null });
    adminMocks.upsert.mockResolvedValue({ error: null });
    repositoryMocks.completeInvitedUserRegistration.mockResolvedValue({
      invite_id: "invite-1",
      role: "user",
      purpose: "user",
      expires_at: "2099-01-02T00:00:00.000Z",
    });
  });

  it("persists a user mask, selected duration, and one shared creation timestamp", async () => {
    const now = "2099-01-01T00:00:00.000Z";
    const result = await createOneTimeUserInvite({
      role: "user",
      createdBy: "admin-1",
      expiresInHours: 24,
      now,
    });

    expect(result.code).toMatch(/^[A-Za-z0-9]{8}$/);
    expect(result.code).toMatch(/[A-Z]/);
    expect(result.code).toMatch(/[a-z]/);
    expect(result.code).toMatch(/[0-9]/);
    expect(repositoryMocks.createInviteRecord).toHaveBeenCalledWith(expect.objectContaining({
      purpose: "user",
      role: "user",
      createdBy: "admin-1",
      createdAt: now,
      expiresAt: "2099-01-02T00:00:00.000Z",
      validityHours: 24,
      codeMask: `${result.code.slice(0, 2)}••••${result.code.slice(-2)}`,
    }));
  });

  it("keeps Worker invites on the existing long random SHA-256 path", async () => {
    const result = await createOneTimeWorkerInvite({
      role: "user",
      createdBy: "admin-1",
      expiresAt: "2099-01-01T01:00:00.000Z",
    });

    expect(result.code.length).toBeGreaterThan(20);
    expect(result.code).not.toMatch(/^[A-Za-z0-9]{8}$/);
    expect(repositoryMocks.createInviteRecord).toHaveBeenCalledWith(expect.objectContaining({
      purpose: "worker",
    }));
    expect(repositoryMocks.createInviteRecord.mock.calls[0][0]).not.toHaveProperty("validityHours");
    expect(repositoryMocks.createInviteRecord.mock.calls[0][0]).not.toHaveProperty("codeMask");
  });

  it("retries a user code after a unique hash collision", async () => {
    repositoryMocks.createInviteRecord
      .mockRejectedValueOnce(Object.assign(new Error("duplicate"), { code: "23505" }))
      .mockResolvedValueOnce({ id: "invite-2" });

    const result = await createOneTimeUserInvite({
      role: "user",
      createdBy: "admin-1",
      expiresInHours: 2,
      now: "2099-01-01T00:00:00.000Z",
    });

    expect(result.inviteId).toBe("invite-2");
    expect(repositoryMocks.createInviteRecord).toHaveBeenCalledTimes(2);
  });

  it("tries the new HMAC and then the legacy hash for user redemption", async () => {
    repositoryMocks.consumeInvite.mockResolvedValueOnce(null).mockResolvedValueOnce({
      invite_id: "invite-legacy",
      role: "user",
      purpose: "user",
      expires_at: "2099-01-02T00:00:00.000Z",
    });

    const result = await redeemInviteCode("legacy-code", "user-1", "2099-01-01T00:00:00.000Z");

    expect(result?.invite_id).toBe("invite-legacy");
    expect(repositoryMocks.consumeInvite).toHaveBeenCalledTimes(2);
    expect(repositoryMocks.consumeInvite.mock.calls[0][0]).not.toBe(repositoryMocks.consumeInvite.mock.calls[1][0]);
  });

  it("does not create an account while the source is blocked", async () => {
    rateLimitMocks.canAttemptInviteRedemption.mockResolvedValue(false);

    const result = await redeemInviteAccount({
      code: "not-valid",
      email: "person@example.invalid",
      password: "password-123",
      sourceHash: "source-hmac",
    });

    expect(result).toEqual({ ok: false, error: "invite_replayed" });
    expect(adminMocks.createUser).not.toHaveBeenCalled();
  });

  it("creates the Profile and consumes the invite through one database boundary", async () => {
    const result = await redeemInviteAccount({
      code: "Invite-code-1",
      email: "person@example.invalid",
      password: "Abcdefg1",
      sourceHash: "source-hmac",
    });

    expect(result).toEqual({ ok: true, userId: "user-1", role: "user" });
    expect(repositoryMocks.completeInvitedUserRegistration).toHaveBeenCalledWith({
      codeHashes: [expect.any(String), expect.any(String)],
      userId: "user-1",
    });
    expect(adminMocks.upsert).not.toHaveBeenCalled();
    expect(adminMocks.deleteUser).not.toHaveBeenCalled();
  });

  it("deletes the new Auth identity when the registration boundary fails", async () => {
    repositoryMocks.completeInvitedUserRegistration.mockRejectedValue(new Error("database failure"));

    const result = await redeemInviteAccount({
      code: "Invite-code-2",
      email: "person@example.invalid",
      password: "Abcdefg1",
      sourceHash: "source-hmac",
    });

    expect(result).toEqual({ ok: false, error: "registration_failed" });
    expect(adminMocks.deleteUser).toHaveBeenCalledWith("user-1");
    expect(result).not.toHaveProperty("database failure");
  });

  it("returns only a safe classification when new Auth cleanup fails", async () => {
    repositoryMocks.completeInvitedUserRegistration.mockRejectedValue(new Error("database failure"));
    adminMocks.deleteUser.mockResolvedValue({ error: { message: "service credential failure" } });

    const result = await redeemInviteAccount({
      code: "Invite-code-3",
      email: "person@example.invalid",
      password: "Abcdefg1",
      sourceHash: "source-hmac",
    });

    expect(result).toEqual({ ok: false, error: "registration_cleanup_failed" });
    expect(JSON.stringify(result)).not.toContain("service credential");
  });

  it("cleans up an identity when the invite is not valid without consuming another record", async () => {
    repositoryMocks.completeInvitedUserRegistration.mockResolvedValue(null);

    const result = await redeemInviteAccount({
      code: "Invite-code-4",
      email: "person@example.invalid",
      password: "Abcdefg1",
      sourceHash: "source-hmac",
    });

    expect(result).toEqual({ ok: false, error: "registration_failed" });
    expect(adminMocks.deleteUser).toHaveBeenCalledWith("user-1");
    expect(rateLimitMocks.recordFailedInviteRedemption).toHaveBeenCalledWith("source-hmac");
  });

  it("keeps Worker consumption on the worker purpose", async () => {
    repositoryMocks.consumeInvite.mockResolvedValue({ invite_id: "worker-invite", role: "user", purpose: "worker" });

    const workerId = "00000000-0000-0000-0000-000000000001";
    await consumeWorkerInvite("worker-code", workerId, "2099-01-01T00:00:00.000Z");

    expect(repositoryMocks.consumeInvite).toHaveBeenCalledWith(
      expect.any(String),
      workerId,
      "worker",
      "2099-01-01T00:00:00.000Z",
    );
  });
});
