import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  canonicalLimit: vi.fn(),
  profileMaybeSingle: vi.fn(),
  profileSingle: vi.fn(),
  profileUpsert: vi.fn(),
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
        upsert: databaseMocks.profileUpsert,
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

  it("refuses a free-text author profile when the stable author was not observed", async () => {
    databaseMocks.canonicalLimit.mockResolvedValue({ data: [], error: null });

    await expect(saveSourceAuthorProfile({
      sourceId: "source-1",
      authorId: "not-observed",
      enabled: true,
      actorId: "admin-1",
    })).rejects.toMatchObject({ message: "unobserved_author" } satisfies Partial<SourceAuthorProfileError>);

    expect(databaseMocks.profileUpsert).not.toHaveBeenCalled();
  });

  it("persists only display data derived from the selected observed stable ID", async () => {
    databaseMocks.canonicalLimit.mockResolvedValue({
      data: [{ author_display: "Observed author", occurred_at: "2026-07-22T00:00:00Z", metadata: { author_id: "discord-1", author_handle: "observed" } }],
      error: null,
    });
    databaseMocks.profileSingle.mockResolvedValue({
      data: {
        source_id: "source-1",
        author_id: "discord-1",
        author_display: "Observed author",
        author_handle: "observed",
        enabled: false,
      },
      error: null,
    });
    databaseMocks.profileUpsert.mockReturnValue({
      select: () => ({ single: databaseMocks.profileSingle }),
    });

    await expect(saveSourceAuthorProfile({
      sourceId: "source-1",
      authorId: "discord-1",
      enabled: false,
      actorId: "admin-1",
    })).resolves.toEqual({
      sourceId: "source-1",
      authorId: "discord-1",
      authorDisplay: "Observed author",
      authorHandle: "observed",
      enabled: false,
    });
    expect(databaseMocks.profileUpsert).toHaveBeenCalledWith({
      source_id: "source-1",
      author_id: "discord-1",
      author_display: "Observed author",
      author_handle: "observed",
      enabled: false,
      created_by: "admin-1",
    }, { onConflict: "source_id,author_id" });
  });
});
