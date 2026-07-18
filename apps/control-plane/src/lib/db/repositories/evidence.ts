import { createSupabaseAdminClient } from "../supabase-server";
import type { Database, Json } from "../types";

export async function insertRawMessageRef(
  row: Database["public"]["Tables"]["raw_messages"]["Insert"],
) {
  const { data, error } = await createSupabaseAdminClient()
    .from("raw_messages")
    .upsert(row, { onConflict: "source_id,external_message_id", ignoreDuplicates: true })
    .select()
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function insertCanonicalMessage(
  row: Database["public"]["Tables"]["canonical_messages"]["Insert"],
) {
  const { data, error } = await createSupabaseAdminClient()
    .from("canonical_messages")
    .upsert(row, { onConflict: "source_id,external_message_id" })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function insertStructuredRun(
  row: Database["public"]["Tables"]["structured_runs"]["Insert"],
) {
  const { data, error } = await createSupabaseAdminClient()
    .from("structured_runs")
    .insert({ ...row, output: row.output as Json })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function insertEvidenceRef(
  row: Database["public"]["Tables"]["evidence_refs"]["Insert"],
) {
  const { data, error } = await createSupabaseAdminClient()
    .from("evidence_refs")
    .upsert(row, { onConflict: "structured_run_id,canonical_message_id,evidence_kind" })
    .select()
    .single();
  if (error) throw error;
  return data;
}
