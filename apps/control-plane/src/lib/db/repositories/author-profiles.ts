import { createSupabaseAdminClient } from "../supabase-server";
import type { Json } from "../types";

type Metadata = Record<string, Json | undefined>;

export type ObservedAuthor = {
  authorId: string;
  authorDisplay: string;
  authorHandle: string | null;
};

export type SourceAuthorProfile = ObservedAuthor & {
  sourceId: string;
  enabled: boolean;
};

export class SourceAuthorProfileError extends Error {}

function asMetadata(value: Json): Metadata | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Metadata : null;
}
function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

export async function listObservedAuthors(sourceId: string): Promise<ObservedAuthor[]> {
  const { data, error } = await createSupabaseAdminClient()
    .from("canonical_messages")
    .select("author_display,metadata,occurred_at")
    .eq("source_id", sourceId)
    .order("occurred_at", { ascending: false })
    .limit(1000);
  if (error) throw error;

  const observed = new Map<string, ObservedAuthor>();
  for (const message of data ?? []) {
    const metadata = asMetadata(message.metadata);
    const authorId = optionalString(metadata?.author_id);
    const authorDisplay = optionalString(message.author_display) ?? optionalString(metadata?.author_display);
    if (!authorId || !authorDisplay || observed.has(authorId)) continue;
    observed.set(authorId, {
      authorId,
      authorDisplay,
      authorHandle: optionalString(metadata?.author_handle) ?? optionalString(metadata?.author_username),
    });
  }

  return [...observed.values()].sort((left, right) => left.authorDisplay.localeCompare(right.authorDisplay)
    || left.authorId.localeCompare(right.authorId));
}

export async function listSourceAuthorProfiles(sourceId: string): Promise<SourceAuthorProfile[]> {
  const { data, error } = await createSupabaseAdminClient()
    .from("source_author_profiles")
    .select("source_id,author_id,author_display,author_handle,enabled")
    .eq("source_id", sourceId)
    .order("author_display", { ascending: true })
    .order("author_id", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((profile) => ({
    sourceId: profile.source_id,
    authorId: profile.author_id,
    authorDisplay: profile.author_display,
    authorHandle: profile.author_handle,
    enabled: profile.enabled,
  }));
}

export async function saveSourceAuthorProfile(input: {
  sourceId: string;
  authorId: string;
  enabled: boolean;
  actorId: string;
}): Promise<SourceAuthorProfile> {
  const observed = (await listObservedAuthors(input.sourceId)).find((author) => author.authorId === input.authorId);
  if (!observed) throw new SourceAuthorProfileError("unobserved_author");

  const { data, error } = await createSupabaseAdminClient()
    .from("source_author_profiles")
    .upsert({
      source_id: input.sourceId,
      author_id: observed.authorId,
      author_display: observed.authorDisplay,
      author_handle: observed.authorHandle,
      enabled: input.enabled,
      created_by: input.actorId,
    }, { onConflict: "source_id,author_id" })
    .select("source_id,author_id,author_display,author_handle,enabled")
    .single();
  if (error) throw error;

  return {
    sourceId: data.source_id,
    authorId: data.author_id,
    authorDisplay: data.author_display,
    authorHandle: data.author_handle,
    enabled: data.enabled,
  };
}

export async function deleteSourceAuthorProfile(input: {
  sourceId: string;
  authorId: string;
}): Promise<boolean> {
  const { data, error } = await createSupabaseAdminClient()
    .from("source_author_profiles")
    .delete()
    .eq("source_id", input.sourceId)
    .eq("author_id", input.authorId)
    .select("id")
    .maybeSingle();
  if (error) throw error;
  return Boolean(data);
}
