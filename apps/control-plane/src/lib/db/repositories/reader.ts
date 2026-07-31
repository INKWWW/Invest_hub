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

export type ReaderJudgement = {
  statement: string;
  supportingDisplayNames: string[];
  dissentingDisplayNames: string[];
  uncertainties: string[];
};

type XReaderSegment = {
  occurredFromAt: string;
  occurredThroughAt: string;
  viewpoints: string[];
  uncertainties: string[];
  analyses: Array<{
    postLink: string;
    bloggerViewpoint: string | null;
    arguments: string[];
    quotedPostViewpoint: string | null;
    uncertainties: string[];
  }>;
};

export type XReaderBlogger = {
  source: { sourceKey: string; displayName: string };
  status: ReaderStatus;
  segments: XReaderSegment[];
};

export type XReaderDate = {
  naturalDate: string;
  judgement: {
    visible: boolean;
    batches: Array<{
      cutoffAt: string;
      coverageStatus: "complete" | "partial" | "no_new_information";
      status: "succeeded" | "judgement_pending" | "judgement_failed";
      revision: number;
      stockViewpoints: ReaderJudgement[];
      marketIndustryViewpoints: ReaderJudgement[];
      uncertainties: string[];
      excludedSourceCount: number;
    }>;
  };
  bloggers: XReaderBlogger[];
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

function object(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function judgementItems(value: unknown, displayNames: Map<string, string>): ReaderJudgement[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const judgement = object(item);
    if (!judgement || typeof judgement.statement !== "string") return [];
    return [{
      statement: judgement.statement,
      supportingDisplayNames: strings(judgement.supporting_source_ids).flatMap((sourceId) => displayNames.has(sourceId) ? [displayNames.get(sourceId)!] : []),
      dissentingDisplayNames: strings(judgement.dissenting_source_ids).flatMap((sourceId) => displayNames.has(sourceId) ? [displayNames.get(sourceId)!] : []),
      uncertainties: strings(judgement.uncertainties),
    }];
  });
}

function judgementStatus(status: string): "succeeded" | "judgement_pending" | "judgement_failed" {
  if (status === "succeeded") return "succeeded";
  return status === "judgement_failed" ? "judgement_failed" : "judgement_pending";
}

/** Reader-safe X projection: no raw body, cookie, local reference, or prompt. */
export async function readXDay(input: { sourceKey?: string; date?: string } = {}): Promise<XReaderDate[]> {
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
  const requestedPostIds = new Set<string>();
  for (const segment of segments ?? []) {
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
  const bloggersByDate = new Map<string, XReaderBlogger[]>();
  const groups = new Map<string, typeof segments>();
  for (const segment of segments ?? []) {
    const key = `${segment.source_id}:${segment.natural_date}`;
    groups.set(key, [...(groups.get(key) ?? []), segment]);
  }
  for (const [, daySegments] of groups) {
    const source = sourceById.get(daySegments[0]!.source_id)!;
    const blogger = {
      source: { sourceKey: source.source_key, displayName: source.display_name },
      status: readerStatus(latestTaskBySource.get(source.id), false, null),
      segments: daySegments.sort((left, right) => right.occurred_through_at.localeCompare(left.occurred_through_at)).map((segment) => {
        const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
        const analyses = refs.flatMap((ref) => {
          const postId = ref && typeof ref === "object" ? (ref as Record<string, unknown>).post_id : undefined;
          if (typeof postId !== "string") return [];
          const canonical = canonicalByExternalId.get(postId);
          if (!canonical) return [];
          const analysis = analysisByCanonicalId.get(canonical.id);
          const context = contextByCanonicalId.get(canonical.id);
          if (!analysis || !context) return [];
          return [{ postLink: context.post_url, bloggerViewpoint: analysis.blogger_viewpoint,
            arguments: strings(analysis.arguments), quotedPostViewpoint: analysis.quoted_post_viewpoint,
            uncertainties: strings(analysis.uncertainties) }];
        });
        return { occurredFromAt: segment.occurred_from_at, occurredThroughAt: segment.occurred_through_at,
          viewpoints: strings(segment.window_viewpoints), uncertainties: [], analyses };
      }),
    };
    const naturalDate = daySegments[0]!.natural_date;
    bloggersByDate.set(naturalDate, [...(bloggersByDate.get(naturalDate) ?? []), blogger]);
  }

  if (input.sourceKey) return [...bloggersByDate.entries()].map(([naturalDate, bloggers]) => ({
    naturalDate,
    judgement: { visible: false, batches: [] },
    bloggers: bloggers.sort((left, right) => left.source.displayName.localeCompare(right.source.displayName)),
  })).sort((left, right) => right.naturalDate.localeCompare(left.naturalDate));

  let batchQuery = supabase.from("x_collection_batches").select("id,natural_date,cutoff_at,status").order("natural_date", { ascending: false }).order("cutoff_at", { ascending: false });
  if (input.date) batchQuery = batchQuery.eq("natural_date", input.date);
  const { data: batches, error: batchError } = await batchQuery;
  if (batchError) throw batchError;
  const batchIds = (batches ?? []).map((batch) => batch.id);
  const [{ data: versions, error: versionError }, { data: batchSources, error: batchSourcesError }] = batchIds.length
    ? await Promise.all([
      supabase.from("x_daily_judgement_versions").select("batch_id,revision,coverage_status,output").in("batch_id", batchIds).order("revision", { ascending: false }),
      supabase.from("x_collection_batch_sources").select("batch_id,source_id,source_display_name,settlement_status").in("batch_id", batchIds),
    ])
    : [{ data: [], error: null }, { data: [], error: null }];
  if (versionError) throw versionError;
  if (batchSourcesError) throw batchSourcesError;
  const latestVersionByBatch = new Map<string, typeof versions extends Array<infer Row> ? Row : never>();
  for (const version of versions ?? []) {
    const current = latestVersionByBatch.get(version.batch_id);
    if (!current || version.revision > current.revision) latestVersionByBatch.set(version.batch_id, version);
  }
  const displayNamesBySourceId = new Map((batchSources ?? []).map((row) => [row.source_id, row.source_display_name]));
  const batchSourcesByBatch = new Map<string, typeof batchSources>();
  for (const row of batchSources ?? []) batchSourcesByBatch.set(row.batch_id, [...(batchSourcesByBatch.get(row.batch_id) ?? []), row]);
  const batchesByDate = new Map<string, XReaderDate["judgement"]["batches"]>();
  for (const batch of batches ?? []) {
    const version = latestVersionByBatch.get(batch.id);
    const output = object(version?.output);
    const batchRows = batchSourcesByBatch.get(batch.id) ?? [];
    const judgement = {
      cutoffAt: batch.cutoff_at,
      coverageStatus: version?.coverage_status ?? "no_new_information" as const,
      status: judgementStatus(batch.status),
      revision: version?.revision ?? 0,
      stockViewpoints: judgementItems(output?.stock_viewpoints, displayNamesBySourceId),
      marketIndustryViewpoints: judgementItems(output?.market_industry_viewpoints, displayNamesBySourceId),
      uncertainties: strings(output?.uncertainties),
      excludedSourceCount: batchRows.filter((row) => row.settlement_status === "excluded").length,
    };
    batchesByDate.set(batch.natural_date, [...(batchesByDate.get(batch.natural_date) ?? []), judgement]);
  }
  const dates = new Set([...bloggersByDate.keys(), ...batchesByDate.keys()]);
  return [...dates].map((naturalDate) => ({
    naturalDate,
    judgement: { visible: true, batches: (batchesByDate.get(naturalDate) ?? []).sort((left, right) => right.cutoffAt.localeCompare(left.cutoffAt)) },
    bloggers: (bloggersByDate.get(naturalDate) ?? []).sort((left, right) => left.source.displayName.localeCompare(right.source.displayName)),
  })).sort((left, right) => right.naturalDate.localeCompare(left.naturalDate));
}
