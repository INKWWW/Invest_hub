import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  canonicalLimit: vi.fn(),
  profileMaybeSingle: vi.fn(),
  profileSingle: vi.fn(),
  profileInsert: vi.fn(),
}));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({
    from(table: string) {
      if (table === "canonical_messages") {
        return {
          select: (fields: string) => {
            databaseMocks.canonicalLimit.mockName(fields);
            return {
              eq: () => ({
                order: () => ({ limit: databaseMocks.canonicalLimit }),
              }),
            };
          },
        };
      }
      return {
        select: () => ({
          eq: () => ({
            order: () => ({
              order: () => databaseMocks.profileMaybeSingle,
            }),
          }),
        }),
        insert: databaseMocks.profileInsert,
      };
    },
  }),
}));

import {
  listObservedAuthors,
  saveSourceAuthorProfile,
  SourceAuthorProfileError,
} from "./author-profiles";

describe("source author profile repository", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("derives stable observed authors without selecting message content", async () => {
    databaseMocks.canonicalLimit.mockResolvedValue({
      data: [
        {
          author_display: "Newest name",
          occurred_at: "2026-07-22T03:00:00Z",
          metadata: { author_id: "discord-2", author_handle: "second" },
        },
        {
          author_display: "Older name",
          occurred_at: "2026-07-22T02:00:00Z",
          metadata: { author_id: "discord-2", author_handle: "old-second" },
        },
        {
          author_display: "First name",
          occurred_at: "2026-07-22T01:00:00Z",
          metadata: { author_id: "discord-1", author_username: "first" },
        },
        {
          author_display: "No stable id",
          occurred_at: "2026-07-22T00:00:00Z",
          metadata: {},
        },
      ],
      error: null,
    });

    await expect(listObservedAuthors("source-1")).resolves.toEqual([
      { authorId: "discord-1", authorDisplay: "First name", authorHandle: "first" },
      { authorId: "discord-2", authorDisplay: "Newest name", authorHandle: "second" },
    ]);
    expect(databaseMocks.canonicalLimit.getMockName()).toBe("author_display,metadata,occurred_at");
  });

  it("persists a direct selector as pending without requiring an observed author", async () => {
    databaseMocks.profileSingle.mockResolvedValue({
      data: {
        id: "profile-1",
        source_id: "source-1",
        requested_author: "Priority author",
        resolution_status: "pending",
        author_id: null,
        author_display: "Priority author",
        author_handle: null,
        enabled: true,
      },
      error: null,
    });
    databaseMocks.profileInsert.mockReturnValue({
      select: () => ({ single: databaseMocks.profileSingle }),
    });

    await expect(saveSourceAuthorProfile({
      sourceId: "source-1",
      requestedAuthor: " Priority author ",
      actorId: "admin-1",
    })).resolves.toEqual({
      id: "profile-1",
      sourceId: "source-1",
      requestedAuthor: "Priority author",
      resolutionStatus: "pending",
      authorId: null,
      authorDisplay: "Priority author",
      authorHandle: null,
      enabled: true,
    });
    expect(databaseMocks.canonicalLimit).not.toHaveBeenCalled();
    expect(databaseMocks.profileInsert).toHaveBeenCalledWith({
      source_id: "source-1",
      requested_author: "Priority author",
      resolution_status: "pending",
      author_id: null,
      author_display: "Priority author",
      author_handle: null,
      enabled: true,
      created_by: "admin-1",
    });
  });

  it("maps a duplicate selector to a safe validation error", async () => {
    databaseMocks.profileSingle.mockResolvedValue({ data: null, error: { code: "23505" } });
    databaseMocks.profileInsert.mockReturnValue({
      select: () => ({ single: databaseMocks.profileSingle }),
    });

    await expect(saveSourceAuthorProfile({
      sourceId: "source-1",
      requestedAuthor: "Priority author",
      actorId: "admin-1",
    })).rejects.toMatchObject({ message: "duplicate_author_selector" } satisfies Partial<SourceAuthorProfileError>);
  });
});
