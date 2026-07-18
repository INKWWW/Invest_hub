import { createSupabaseAdminClient } from "../supabase-server";
import type { Database } from "../types";

type SourceInsert = Database["public"]["Tables"]["sources"]["Insert"];

export async function listSources() {
  const { data, error } = await createSupabaseAdminClient()
    .from("sources")
    .select("id,source_key,source_type,display_name,parameter_version,enabled,created_by,created_at,updated_at")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
}

export async function upsertDiscordSource(input: {
  sourceKey: string;
  displayName: string;
  parameterVersion: string;
  createdBy: string;
  enabled?: boolean;
}) {
  const row: SourceInsert = {
    source_key: input.sourceKey,
    source_type: "discord",
    display_name: input.displayName,
    parameter_version: input.parameterVersion,
    created_by: input.createdBy,
    enabled: input.enabled ?? true,
  };
  const { data, error } = await createSupabaseAdminClient()
    .from("sources")
    .upsert(row, { onConflict: "source_key" })
    .select()
    .single();
  if (error) throw error;
  return data;
}
