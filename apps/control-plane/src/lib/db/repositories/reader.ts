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

export type XReaderDay = {
  source: { sourceKey: string; displayName: string };
  naturalDate: string;
  status: ReaderStatus;
  segments: Array<{
    id: string;
    occurredFromAt: string;
    occurredThroughAt: string;
    viewpoints: string[];
    uncertainties: string[];
    analyses: Array<{
      postId: string;
      postLink: string;
      bloggerViewpoint: string | null;
      arguments: string[];
      quotedPostViewpoint: string | null;
      uncertainties: string[];
      evidencePostIds: string[];
    }>;
  }>;
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
  let sourceQuery = supabase.from("sources").select("id,source_key,display_name").eq("source_type", "discord").eq("enabled", true).order("display_name", { ascending: true });
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

function strings(value: unknown): string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string") ? value : [];
}

/** Reader-safe X projection: no raw body, cookie, local reference, or prompt. */
export async function readXDay(input: { sourceKey?: string; date?: string } = {}): Promise<XReaderDay[]> {
  const supabase = createSupabaseAdminClient();
  let sourceQuery = supabase.from("sources").select("id,source_key,display_name").eq("source_type", "x").eq("enabled", true).order("display_name", { ascending: true });
  if (input.sourceKey) sourceQuery = sourceQuery.eq("source_key", input.sourceKey);
  const { data: sources, error: sourceError } = await sourceQuery;
  if (sourceError) throw sourceError;
  if (!sources?.length) return [];

  const sourceIds = sources.map((source) => source.id);
  let segmentQuery = supabase.from("x_daily_viewpoint_segments")
    .select("id,source_id,natural_date,occurred_from_at,occurred_through_at,window_viewpoints,post_analysis_refs,evidence_refs,created_at")
    .in("source_id", sourceIds).order("natural_date", { ascending: false }).order("occurred_from_at");
  if (input.date) segmentQuery = segmentQuery.eq("natural_date", input.date);
  const { data: segments, error: segmentError } = await segmentQuery;
  if (segmentError) throw segmentError;
  if (!segments?.length) return [];

  const requestedPostIds = new Set<string>();
  for (const segment of segments) {
    const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
    for (const ref of refs) if (ref && typeof ref === "object" && "post_id" in ref && typeof (ref as Record<string, unknown>).post_id === "string") requestedPostIds.add((ref as Record<string, string>).post_id);
  }
  const { data: canonicalRows, error: canonicalError } = requestedPostIds.size
    ? await supabase.from("canonical_messages").select("id,source_id,external_message_id").in("source_id", sourceIds).in("external_message_id", [...requestedPostIds])
    : { data: [], error: null };
  if (canonicalError) throw canonicalError;
  const canonicalByExternalId = new Map((canonicalRows ?? []).map((row) => [row.external_message_id, row]));
  const canonicalIds = (canonicalRows ?? []).map((row) => row.id);
  const [{ data: analysisRows, error: analysisError }, { data: contextRows, error: contextError }] = canonicalIds.length
    ? await Promise.all([
      supabase.from("x_post_analyses").select("canonical_message_id,analysis_version,blogger_viewpoint,arguments,quoted_post_viewpoint,uncertainties,evidence_refs").in("canonical_message_id", canonicalIds).eq("analysis_version", 1),
      supabase.from("x_post_contexts").select("canonical_message_id,post_url").in("canonical_message_id", canonicalIds),
    ])
    : [{ data: [], error: null }, { data: [], error: null }];
  if (analysisError) throw analysisError;
  if (contextError) throw contextError;
  const analysisByCanonicalId = new Map((analysisRows ?? []).map((row) => [row.canonical_message_id, row]));
  const contextByCanonicalId = new Map((contextRows ?? []).map((row) => [row.canonical_message_id, row]));

  const { data: taskRows, error: taskError } = await supabase.from("sync_tasks").select("id,source_id,status,updated_at").eq("task_type", "x_sync").in("source_id", sourceIds).order("updated_at", { ascending: false });
  if (taskError) throw taskError;
  const latestTaskBySource = new Map<string, { id: string; status: string }>();
  for (const task of taskRows ?? []) if (!latestTaskBySource.has(task.source_id)) latestTaskBySource.set(task.source_id, task);
  const sourceById = new Map(sources.map((source) => [source.id, source]));
  const groups = new Map<string, typeof segments>();
  for (const segment of segments) {
    const key = `${segment.source_id}:${segment.natural_date}`;
    groups.set(key, [...(groups.get(key) ?? []), segment]);
  }
  return [...groups.entries()].map(([key, daySegments]) => {
    const source = sourceById.get(daySegments[0]!.source_id)!;
    return {
      source: { sourceKey: source.source_key, displayName: source.display_name },
      naturalDate: daySegments[0]!.natural_date,
      status: readerStatus(latestTaskBySource.get(source.id), false, null),
      segments: daySegments.map((segment) => {
        const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
        const analyses = refs.flatMap((ref) => {
          const postId = ref && typeof ref === "object" ? (ref as Record<string, unknown>).post_id : undefined;
          if (typeof postId !== "string") return [];
          const canonical = canonicalByExternalId.get(postId);
          if (!canonical) return [];
          const analysis = analysisByCanonicalId.get(canonical.id);
          const context = contextByCanonicalId.get(canonical.id);
          if (!analysis || !context) return [];
          return [{ postId, postLink: context.post_url, bloggerViewpoint: analysis.blogger_viewpoint,
            arguments: strings(analysis.arguments), quotedPostViewpoint: analysis.quoted_post_viewpoint,
            uncertainties: strings(analysis.uncertainties), evidencePostIds: strings(analysis.evidence_refs) }];
        });
        return { id: segment.id, occurredFromAt: segment.occurred_from_at, occurredThroughAt: segment.occurred_through_at,
          viewpoints: strings(segment.window_viewpoints), uncertainties: [], analyses };
      }),
    };
  }).sort((left, right) => right.naturalDate.localeCompare(left.naturalDate) || left.source.displayName.localeCompare(right.source.displayName));
}
