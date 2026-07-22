import { createSupabaseAdminClient } from "../supabase-server";
import type { Json } from "../types";

type Metadata = Record<string, Json | undefined>;

export type ObservedAuthor = {
  authorId: string;
  authorDisplay: string;
  authorHandle: string | null;
};

export type AuthorResolutionStatus = "pending" | "resolved" | "ambiguous";

export type SourceAuthorProfile = {
  id: string;
  sourceId: string;
  requestedAuthor: string;
  resolutionStatus: AuthorResolutionStatus;
  authorId: string | null;
  authorDisplay: string;
  authorHandle: string | null;
  enabled: boolean;
};

export class SourceAuthorProfileError extends Error {}

function asMetadata(value: Json): Metadata | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Metadata : null;
}
function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}
function asResolutionStatus(value: string): AuthorResolutionStatus {
  if (value === "pending" || value === "resolved" || value === "ambiguous") return value;
  throw new Error("invalid_author_profile_resolution_status");
}
function mapProfile(profile: {
  id: string;
  source_id: string;
  requested_author: string;
  resolution_status: string;
  author_id: string | null;
  author_display: string;
  author_handle: string | null;
  enabled: boolean;
}): SourceAuthorProfile {
  return {
    id: profile.id,
    sourceId: profile.source_id,
    requestedAuthor: profile.requested_author,
    resolutionStatus: asResolutionStatus(profile.resolution_status),
    authorId: profile.author_id,
    authorDisplay: profile.author_display,
    authorHandle: profile.author_handle,
    enabled: profile.enabled,
  };
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
    .select("id,source_id,requested_author,resolution_status,author_id,author_display,author_handle,enabled")
    .eq("source_id", sourceId)
    .order("requested_author", { ascending: true })
    .order("id", { ascending: true });
  if (error) throw error;
  return (data ?? []).map(mapProfile);
}

export async function saveSourceAuthorProfile(input: {
  sourceId: string;
  requestedAuthor: string;
  actorId: string;
}): Promise<SourceAuthorProfile> {
  const requestedAuthor = input.requestedAuthor.trim();
  if (!requestedAuthor) throw new SourceAuthorProfileError("invalid_author_selector");
  const { data, error } = await createSupabaseAdminClient()
    .from("source_author_profiles")
    .insert({
      source_id: input.sourceId,
      requested_author: requestedAuthor,
      resolution_status: "pending",
      author_id: null,
      author_display: requestedAuthor,
      author_handle: null,
      enabled: true,
      created_by: input.actorId,
    })
    .select("id,source_id,requested_author,resolution_status,author_id,author_display,author_handle,enabled")
    .single();
  if (error) {
    if (error.code === "23505") throw new SourceAuthorProfileError("duplicate_author_selector");
    throw error;
  }
  return mapProfile(data);
}

export async function setSourceAuthorProfileEnabled(input: {
  sourceId: string;
  profileId: string;
  enabled: boolean;
}): Promise<SourceAuthorProfile | null> {
  const { data, error } = await createSupabaseAdminClient()
    .from("source_author_profiles")
    .update({ enabled: input.enabled })
    .eq("source_id", input.sourceId)
    .eq("id", input.profileId)
    .select("id,source_id,requested_author,resolution_status,author_id,author_display,author_handle,enabled")
    .maybeSingle();
  if (error) throw error;
  return data ? mapProfile(data) : null;
}

export async function deleteSourceAuthorProfile(input: {
  sourceId: string;
  profileId: string;
}): Promise<boolean> {
  const { data, error } = await createSupabaseAdminClient()
    .from("source_author_profiles")
    .delete()
    .eq("source_id", input.sourceId)
    .eq("id", input.profileId)
    .select("id")
    .maybeSingle();
  if (error) throw error;
  return Boolean(data);
}
