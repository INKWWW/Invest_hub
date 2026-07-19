import { createSupabaseAdminClient } from "../supabase-server";

export type ReaderDay = {
  source: { sourceKey: string; displayName: string };
  naturalDate: string;
  dailySummary: { id: string; version: number; output: unknown; coverage: unknown };
  batches: Array<{ id: string; inputMessageIds: unknown; structuredRunIds: unknown; output: unknown; coverage: unknown }>;
  messages: Array<{ externalMessageId: string; occurredAt: string | null; authorDisplay: string | null; content: string; hasUnparsedMedia: boolean; unresolved: boolean }>;
};

export async function readDiscordDay(input: { sourceKey?: string; date?: string } = {}): Promise<ReaderDay[]> {
  const supabase = createSupabaseAdminClient();
  let sourceQuery = supabase
    .from("sources")
    .select("id,source_key,display_name")
    .eq("enabled", true)
    .order("display_name", { ascending: true });
  if (input.sourceKey) sourceQuery = sourceQuery.eq("source_key", input.sourceKey);
  const { data: sources, error: sourcesError } = await sourceQuery;
  if (sourcesError) throw sourcesError;
  if (!sources?.length) return [];

  const sourceIds = sources.map((source) => source.id);
  let dailyQuery = supabase
    .from("daily_summaries")
    .select("id,source_id,natural_date,version,output,coverage")
    .in("source_id", sourceIds)
    .eq("is_current", true)
    .order("natural_date", { ascending: false });
  if (input.date) dailyQuery = dailyQuery.eq("natural_date", input.date);
  const { data: dailies, error: dailyError } = await dailyQuery;
  if (dailyError) throw dailyError;

  const sourceById = new Map(sources.map((source) => [source.id, source]));
  return Promise.all((dailies ?? []).map(async (daily) => {
    const nextDate = new Date(`${daily.natural_date}T00:00:00.000Z`);
    nextDate.setUTCDate(nextDate.getUTCDate() + 1);
    const [{ data: batches, error: batchError }, { data: messages, error: messageError }] = await Promise.all([
      supabase.from("summary_batches").select("id,input_message_ids,structured_run_ids,output,coverage").eq("source_id", daily.source_id).eq("natural_date", daily.natural_date).order("created_at"),
      supabase.from("canonical_messages").select("external_message_id,occurred_at,author_display,content,has_unparsed_media,metadata").eq("source_id", daily.source_id).gte("occurred_at", `${daily.natural_date}T00:00:00.000Z`).lt("occurred_at", nextDate.toISOString()).order("occurred_at"),
    ]);
    if (batchError) throw batchError;
    if (messageError) throw messageError;
    const source = sourceById.get(daily.source_id)!;
    return {
      source: { sourceKey: source.source_key, displayName: source.display_name },
      naturalDate: daily.natural_date,
      dailySummary: { id: daily.id, version: daily.version, output: daily.output, coverage: daily.coverage },
      batches: (batches ?? []).map((batch) => ({ id: batch.id, inputMessageIds: batch.input_message_ids, structuredRunIds: batch.structured_run_ids, output: batch.output, coverage: batch.coverage })),
      messages: (messages ?? []).map((message) => ({
        externalMessageId: message.external_message_id,
        occurredAt: message.occurred_at,
        authorDisplay: message.author_display,
        content: message.content,
        hasUnparsedMedia: message.has_unparsed_media,
        unresolved: Boolean((message.metadata as Record<string, unknown>).unresolved),
      })),
    };
  }));
}
