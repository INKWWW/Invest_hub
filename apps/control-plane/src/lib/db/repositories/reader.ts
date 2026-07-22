import { presentSummary, type SummaryPresentation } from "../../../components/reader/reader-presentation";
import { createSupabaseAdminClient } from "../supabase-server";

export type ReaderStatus = "processing" | "partial_failure" | "retryable_failed" | "failed" | "no_new_messages" | "succeeded";

export type ReaderDay = {
  source: { sourceKey: string; displayName: string };
  naturalDate: string;
  status: ReaderStatus;
  dailySummary: {
    version: number;
    presentation: SummaryPresentation;
    history: Array<{ version: number; presentation: SummaryPresentation; createdAt: string }>;
  };
  batches: Array<{ presentation: SummaryPresentation }>;
};

function readerStatus(task: { id: string; status: string } | undefined, noNewMessages: boolean, coverage: unknown): ReaderStatus {
  if (task?.status === "queued" || task?.status === "leased" || task?.status === "running") return "processing";
  if (task?.status === "retryable_failed") return "retryable_failed";
  if (task?.status === "failed" || task?.status === "cancelled") return "failed";
  if (task?.status === "succeeded" && coverage && typeof coverage === "object" && (coverage as Record<string, unknown>).partial_failure === true) return "partial_failure";
  if (task?.status === "succeeded" && noNewMessages) return "no_new_messages";
  return "succeeded";
}

export async function readDiscordDay(input: { sourceKey?: string; date?: string } = {}): Promise<ReaderDay[]> {
  const supabase = createSupabaseAdminClient();
  let sourceQuery = supabase.from("sources").select("id,source_key,display_name").eq("enabled", true).order("display_name", { ascending: true });
  if (input.sourceKey) sourceQuery = sourceQuery.eq("source_key", input.sourceKey);
  const { data: sources, error: sourcesError } = await sourceQuery;
  if (sourcesError) throw sourcesError;
  if (!sources?.length) return [];

  const sourceIds = sources.map((source) => source.id);
  let dailyQuery = supabase.from("daily_summaries").select("source_id,natural_date,version,is_current,output,coverage,created_at").in("source_id", sourceIds).order("natural_date", { ascending: false });
  if (input.date) dailyQuery = dailyQuery.eq("natural_date", input.date);
  const { data: dailies, error: dailyError } = await dailyQuery;
  if (dailyError) throw dailyError;
  const allDailies = dailies ?? [];
  const currentDailies = allDailies.filter((daily) => daily.is_current);
  if (!currentDailies.length) return [];

  const { data: taskStatuses, error: taskStatusError } = await supabase.from("sync_tasks").select("id,source_id,status,updated_at").in("source_id", sourceIds).order("updated_at", { ascending: false });
  if (taskStatusError) throw taskStatusError;
  const latestTaskBySource = new Map<string, { id: string; status: string }>();
  for (const task of taskStatuses ?? []) if (!latestTaskBySource.has(task.source_id)) latestTaskBySource.set(task.source_id, task);
  const latestTaskIds = [...latestTaskBySource.values()].map((task) => task.id);
  const noNewMessagesByTask = new Map<string, boolean>();
  if (latestTaskIds.length > 0) {
    const { data: attempts, error: attemptsError } = await supabase.from("task_attempts").select("task_id,result,updated_at").in("task_id", latestTaskIds).order("updated_at", { ascending: false });
    if (attemptsError) throw attemptsError;
    for (const attempt of attempts ?? []) {
      if (noNewMessagesByTask.has(attempt.task_id)) continue;
      const result = attempt.result;
      noNewMessagesByTask.set(attempt.task_id, Boolean(result && typeof result === "object" && (result as Record<string, unknown>).no_new_data === true));
    }
  }

  const sourceById = new Map(sources.map((source) => [source.id, source]));
  return Promise.all(currentDailies.map(async (daily) => {
    const { data: batches, error: batchError } = await supabase.from("summary_batches").select("output,coverage").eq("source_id", daily.source_id).eq("natural_date", daily.natural_date).order("created_at");
    if (batchError) throw batchError;
    const source = sourceById.get(daily.source_id)!;
    const history = allDailies.filter((item) => item.source_id === daily.source_id && item.natural_date === daily.natural_date)
      .sort((left, right) => right.version - left.version)
      .map((item) => ({ version: item.version, presentation: presentSummary(item.output, item.coverage), createdAt: item.created_at }));
    return {
      source: { sourceKey: source.source_key, displayName: source.display_name },
      naturalDate: daily.natural_date,
      status: readerStatus(latestTaskBySource.get(daily.source_id), noNewMessagesByTask.get(latestTaskBySource.get(daily.source_id)?.id ?? "") === true, daily.coverage),
      dailySummary: { version: daily.version, presentation: presentSummary(daily.output, daily.coverage), history },
      batches: (batches ?? []).map((batch) => ({ presentation: presentSummary(batch.output, batch.coverage) })),
    };
  }));
}
