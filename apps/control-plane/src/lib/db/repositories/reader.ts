import { createSupabaseAdminClient } from "../supabase-server";

export type ReaderDay = {
  source: { sourceKey: string; displayName: string };
  naturalDate: string;
  status: ReaderStatus;
  dailySummary: {
    id: string;
    version: number;
    output: unknown;
    coverage: unknown;
    history: Array<{ id: string; version: number; output: unknown; coverage: unknown; createdAt: string }>;
  };
  batches: Array<{ id: string; inputMessageIds: unknown; structuredRunIds: unknown; output: unknown; coverage: unknown }>;
  messages: Array<{
    externalMessageId: string;
    occurredAt: string | null;
    authorDisplay: string | null;
    content: string;
    hasUnparsedMedia: boolean;
    unresolved: boolean;
    evidenceExpired: boolean;
  }>;
};

export type ReaderStatus = "processing" | "partial_failure" | "retryable_failed" | "failed" | "succeeded";

function readerStatus(taskStatus: string | undefined, coverage: unknown): ReaderStatus {
  if (taskStatus === "queued" || taskStatus === "leased" || taskStatus === "running") return "processing";
  if (taskStatus === "retryable_failed") return "retryable_failed";
  if (taskStatus === "failed" || taskStatus === "cancelled") return "failed";
  if (coverage && typeof coverage === "object" && (coverage as Record<string, unknown>).partial_failure === true) return "partial_failure";
  return "succeeded";
}

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
    .select("id,source_id,natural_date,version,is_current,output,coverage,created_at")
    .in("source_id", sourceIds)
    .order("natural_date", { ascending: false });
  if (input.date) dailyQuery = dailyQuery.eq("natural_date", input.date);
  const { data: dailies, error: dailyError } = await dailyQuery;
  if (dailyError) throw dailyError;

  const allDailies = dailies ?? [];
  const currentDailies = allDailies.filter((daily) => daily.is_current);
  if (!currentDailies.length) return [];

  const { data: taskStatuses, error: taskStatusError } = await supabase
    .from("sync_tasks")
    .select("source_id,status,updated_at")
    .in("source_id", sourceIds)
    .order("updated_at", { ascending: false });
  if (taskStatusError) throw taskStatusError;
  const latestTaskStatusBySource = new Map<string, string>();
  for (const task of taskStatuses ?? []) {
    if (!latestTaskStatusBySource.has(task.source_id)) latestTaskStatusBySource.set(task.source_id, task.status);
  }

  const sourceById = new Map(sources.map((source) => [source.id, source]));
  return Promise.all(currentDailies.map(async (daily) => {
    const nextDate = new Date(`${daily.natural_date}T00:00:00.000Z`);
    nextDate.setUTCDate(nextDate.getUTCDate() + 1);
    const [{ data: batches, error: batchError }, { data: messages, error: messageError }] = await Promise.all([
      supabase.from("summary_batches").select("id,input_message_ids,structured_run_ids,output,coverage").eq("source_id", daily.source_id).eq("natural_date", daily.natural_date).order("created_at"),
      supabase.from("canonical_messages").select("external_message_id,occurred_at,author_display,content,has_unparsed_media,metadata").eq("source_id", daily.source_id).gte("occurred_at", `${daily.natural_date}T00:00:00.000Z`).lt("occurred_at", nextDate.toISOString()).order("occurred_at"),
    ]);
    if (batchError) throw batchError;
    if (messageError) throw messageError;
    const messageIds = (messages ?? []).map((message) => message.external_message_id);
    let rawMessages: Array<{ external_message_id: string; retention_expires_at: string }> = [];
    if (messageIds.length > 0) {
      const { data, error } = await supabase
        .from("raw_messages")
        .select("external_message_id,retention_expires_at")
        .eq("source_id", daily.source_id)
        .in("external_message_id", messageIds);
      if (error) throw error;
      rawMessages = data ?? [];
    }
    const expiresAtByMessageId = new Map(rawMessages.map((message) => [message.external_message_id, message.retention_expires_at]));
    const source = sourceById.get(daily.source_id)!;
    const history = allDailies
      .filter((item) => item.source_id === daily.source_id && item.natural_date === daily.natural_date)
      .sort((left, right) => right.version - left.version)
      .map((item) => ({ id: item.id, version: item.version, output: item.output, coverage: item.coverage, createdAt: item.created_at }));
    return {
      source: { sourceKey: source.source_key, displayName: source.display_name },
      naturalDate: daily.natural_date,
      status: readerStatus(latestTaskStatusBySource.get(daily.source_id), daily.coverage),
      dailySummary: { id: daily.id, version: daily.version, output: daily.output, coverage: daily.coverage, history },
      batches: (batches ?? []).map((batch) => ({ id: batch.id, inputMessageIds: batch.input_message_ids, structuredRunIds: batch.structured_run_ids, output: batch.output, coverage: batch.coverage })),
      messages: (messages ?? []).map((message) => ({
        externalMessageId: message.external_message_id,
        occurredAt: message.occurred_at,
        authorDisplay: message.author_display,
        content: message.content,
        hasUnparsedMedia: message.has_unparsed_media,
        unresolved: Boolean((message.metadata as Record<string, unknown>).unresolved),
        evidenceExpired: Boolean(expiresAtByMessageId.get(message.external_message_id) && new Date(expiresAtByMessageId.get(message.external_message_id)!).getTime() <= Date.now()),
      })),
    };
  }));
}
