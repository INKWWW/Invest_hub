import { createSupabaseAdminClient } from "../supabase-server";
import type { Database } from "../types";

type SourceInsert = Database["public"]["Tables"]["sources"]["Insert"];

const sourceFields = "id,source_key,source_type,display_name,parameter_version,enabled,authorized_worker_id,author_rules_version,created_by,created_at,updated_at";

export class SourceAdministrationError extends Error {}

export async function listSources() {
  const { data, error } = await createSupabaseAdminClient()
    .from("sources")
    .select(sourceFields)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
}

export async function updateSourceAdministration(input: {
  sourceId: string;
  displayName: string;
  enabled: boolean;
  authorizedWorkerId: string | null;
}) {
  const supabase = createSupabaseAdminClient();
  if (input.authorizedWorkerId) {
    const { data: worker, error: workerError } = await supabase
      .from("workers")
      .select("id,status")
      .eq("id", input.authorizedWorkerId)
      .maybeSingle();
    if (workerError) throw workerError;
    if (!worker || worker.status === "revoked") {
      throw new SourceAdministrationError("invalid_authorized_worker");
    }
  }

  const { data, error } = await supabase
    .from("sources")
    .update({
      display_name: input.displayName,
      enabled: input.enabled,
      authorized_worker_id: input.authorizedWorkerId,
    })
    .eq("id", input.sourceId)
    .select(sourceFields)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new SourceAdministrationError("source_not_found");
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
