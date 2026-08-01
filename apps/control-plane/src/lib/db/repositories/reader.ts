import { presentSummary, type SummaryPresentation } from "../../../components/reader/reader-presentation";
import { createSupabaseAdminClient } from "../supabase-server";

const READER_QUERY_BATCH_SIZE = 100;

function chunkValues<Value>(values: Value[], size: number): Value[][] {
  const chunks: Value[][] = [];
  for (let index = 0; index < values.length; index += size) chunks.push(values.slice(index, index + size));
  return chunks;
}

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

export type XReaderJudgementRevision = {
  revision: number;
  coverageStatus: "complete" | "partial" | "no_new_information";
  stockViewpoints: ReaderJudgement[];
  marketIndustryViewpoints: ReaderJudgement[];
  uncertainties: string[];
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
      revisionHistory: XReaderJudgementRevision[];
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

function judgementRevision(
  version: { revision: number; coverage_status: "complete" | "partial" | "no_new_information"; output: unknown },
  displayNames: Map<string, string>,
): XReaderJudgementRevision {
  const output = object(version.output);
  return {
    revision: version.revision,
    coverageStatus: version.coverage_status,
    stockViewpoints: judgementItems(output?.stock_viewpoints, displayNames),
    marketIndustryViewpoints: judgementItems(output?.market_industry_viewpoints, displayNames),
    uncertainties: strings(output?.uncertainties),
  };
}

function batchSourceReaderStatus(
  batchSource: { settlement_status: string },
  task: { id: string; status: string } | undefined,
  attemptResult: unknown,
): ReaderStatus {
  const result = object(attemptResult);
  const noNewMessages = batchSource.settlement_status === "no_new_information" || result?.no_new_data === true;
  if (noNewMessages) return "no_new_messages";
  if (batchSource.settlement_status === "excluded") {
    if (task?.status === "failed" || task?.status === "cancelled") return "failed";
    if (task?.status === "retryable_failed") return "retryable_failed";
    return "partial_failure";
  }
  if (batchSource.settlement_status === "pending" && !task) return "processing";
  return readerStatus(task, false, result);
}

/** Reader-safe X projection: no raw body, cookie, local reference, or prompt. */
export async function readXDay(input: { sourceKey?: string; date?: string } = {}): Promise<XReaderDate[]> {
  const supabase = createSupabaseAdminClient();
  let sourceQuery = supabase.from("sources").select("id,source_key,display_name").eq("source_type", "x").order("display_name", { ascending: true });
  if (input.sourceKey) sourceQuery = sourceQuery.eq("source_key", input.sourceKey);
  const { data: sources, error: sourceError } = await sourceQuery;
  if (sourceError) throw sourceError;
  if (!sources?.length) return [];

  const sourceIds = sources.map((source) => source.id);
  const sourceIdChunks = chunkValues(sourceIds, READER_QUERY_BATCH_SIZE);
  const sourceIdSet = new Set(sourceIds);
  const sourceById = new Map(sources.map((source) => [source.id, source]));
  const segmentResults = await Promise.all(sourceIdChunks.map((ids) => {
    let query = supabase.from("x_daily_viewpoint_segments")
      .select("source_id,natural_date,occurred_from_at,occurred_through_at,window_viewpoints,post_analysis_refs")
      .in("source_id", ids).order("natural_date", { ascending: false }).order("occurred_from_at");
    if (input.date) query = query.eq("natural_date", input.date);
    return query;
  }));
  const segmentError = segmentResults.find((result) => result.error)?.error;
  if (segmentError) throw segmentError;
  const segments = segmentResults.flatMap((result) => result.data ?? []);
  const requestedPostIds = new Set<string>();
  for (const segment of segments) {
    const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
    for (const ref of refs) if (ref && typeof ref === "object" && "post_id" in ref && typeof (ref as Record<string, unknown>).post_id === "string") requestedPostIds.add((ref as Record<string, string>).post_id);
  }
  const requestedPostIdChunks = chunkValues([...requestedPostIds], READER_QUERY_BATCH_SIZE);
  const canonicalResults = await Promise.all(sourceIdChunks.flatMap((sourceChunk) => requestedPostIdChunks.map((postIdChunk) => (
    supabase.from("canonical_messages").select("id,source_id,external_message_id")
      .in("source_id", sourceChunk).in("external_message_id", postIdChunk)
  ))));
  const canonicalError = canonicalResults.find((result) => result.error)?.error;
  if (canonicalError) throw canonicalError;
  const canonicalRows = canonicalResults.flatMap((result) => result.data ?? []);
  const canonicalByExternalId = new Map(canonicalRows.map((row) => [`${row.source_id}:${row.external_message_id}`, row]));
  const canonicalIds = canonicalRows.map((row) => row.id);
  const canonicalIdChunks = chunkValues(canonicalIds, READER_QUERY_BATCH_SIZE);
  const [analysisResults, contextResults] = await Promise.all([
    Promise.all(canonicalIdChunks.map((ids) => supabase.from("x_post_analyses")
      .select("canonical_message_id,analysis_version,blogger_viewpoint,arguments,quoted_post_viewpoint,uncertainties")
      .in("canonical_message_id", ids).eq("analysis_version", 1))),
    Promise.all(canonicalIdChunks.map((ids) => supabase.from("x_post_contexts").select("canonical_message_id,post_url").in("canonical_message_id", ids))),
  ]);
  const analysisError = analysisResults.find((result) => result.error)?.error;
  const contextError = contextResults.find((result) => result.error)?.error;
  if (analysisError) throw analysisError;
  if (contextError) throw contextError;
  const analysisRows = analysisResults.flatMap((result) => result.data ?? []);
  const contextRows = contextResults.flatMap((result) => result.data ?? []);
  const analysisByCanonicalId = new Map(analysisRows.map((row) => [row.canonical_message_id, row]));
  const contextByCanonicalId = new Map(contextRows.map((row) => [row.canonical_message_id, row]));

  let batchQuery = supabase.from("x_collection_batches").select("id,natural_date,cutoff_at,status").order("natural_date", { ascending: false }).order("cutoff_at", { ascending: false });
  if (input.date) batchQuery = batchQuery.eq("natural_date", input.date);
  const { data: batches, error: batchError } = await batchQuery;
  if (batchError) throw batchError;
  const orderedBatches = [...(batches ?? [])].sort((left, right) => right.cutoff_at.localeCompare(left.cutoff_at));
  const batchIds = orderedBatches.map((batch) => batch.id);
  const batchIdChunks = chunkValues(batchIds, READER_QUERY_BATCH_SIZE);
  const [versionResults, batchSourceResults] = await Promise.all([
    Promise.all(batchIdChunks.map((ids) => supabase.from("x_daily_judgement_versions").select("batch_id,revision,coverage_status,output").in("batch_id", ids).order("revision", { ascending: false }))),
    Promise.all(batchIdChunks.map((ids) => supabase.from("x_collection_batch_sources").select("batch_id,source_id,source_display_name,x_sync_task_id,settlement_status").in("batch_id", ids))),
  ]);
  const versionError = versionResults.find((result) => result.error)?.error;
  const batchSourcesError = batchSourceResults.find((result) => result.error)?.error;
  if (versionError) throw versionError;
  if (batchSourcesError) throw batchSourcesError;
  const versions = versionResults.flatMap((result) => result.data ?? []);
  const allBatchSources = batchSourceResults.flatMap((result) => result.data ?? []);

  const batchSources = allBatchSources.filter((row) => sourceIdSet.has(row.source_id));
  const batchSourcesByBatch = new Map<string, typeof batchSources>();
  for (const row of batchSources) batchSourcesByBatch.set(row.batch_id, [...(batchSourcesByBatch.get(row.batch_id) ?? []), row]);
  const taskIds = [...new Set(batchSources.flatMap((row) => typeof row.x_sync_task_id === "string" ? [row.x_sync_task_id] : []))];
  const taskIdChunks = chunkValues(taskIds, READER_QUERY_BATCH_SIZE);
  const [taskResults, attemptResults] = await Promise.all([
    Promise.all(taskIdChunks.map((ids) => supabase.from("sync_tasks").select("id,status").in("id", ids))),
    Promise.all(taskIdChunks.map((ids) => supabase.from("task_attempts").select("task_id,result,updated_at").in("task_id", ids).order("updated_at", { ascending: false }))),
  ]);
  const taskError = taskResults.find((result) => result.error)?.error;
  const attemptError = attemptResults.find((result) => result.error)?.error;
  if (taskError) throw taskError;
  if (attemptError) throw attemptError;
  const taskRows = taskResults.flatMap((result) => result.data ?? []);
  const attemptRows = attemptResults.flatMap((result) => result.data ?? []);
  const taskIdSet = new Set(taskIds);
  const taskById = new Map(taskRows.filter((task) => taskIdSet.has(task.id)).map((task) => [task.id, task]));
  const attemptResultByTaskId = new Map<string, unknown>();
  for (const attempt of attemptRows) {
    if (taskIdSet.has(attempt.task_id) && !attemptResultByTaskId.has(attempt.task_id)) attemptResultByTaskId.set(attempt.task_id, attempt.result);
  }

  const segmentGroups = new Map<string, typeof segments>();
  for (const segment of segments) {
    if (!sourceIdSet.has(segment.source_id)) continue;
    const key = `${segment.source_id}:${segment.natural_date}`;
    segmentGroups.set(key, [...(segmentGroups.get(key) ?? []), segment]);
  }

  const versionsByBatch = new Map<string, typeof versions>();
  for (const version of versions) {
    versionsByBatch.set(version.batch_id, [...(versionsByBatch.get(version.batch_id) ?? []), version]);
  }
  const batchesByDate = new Map<string, XReaderDate["judgement"]["batches"]>();
  for (const batch of orderedBatches) {
    const batchVersions = [...(versionsByBatch.get(batch.id) ?? [])].sort((left, right) => right.revision - left.revision);
    const currentVersion = batchVersions[0];
    const batchRows = batchSourcesByBatch.get(batch.id) ?? [];
    const displayNamesBySourceId = new Map(batchRows.map((row) => [row.source_id, row.source_display_name]));
    const current = currentVersion ? judgementRevision(currentVersion, displayNamesBySourceId) : {
      revision: 0,
      coverageStatus: "no_new_information" as const,
      stockViewpoints: [],
      marketIndustryViewpoints: [],
      uncertainties: [],
    };
    const judgement: XReaderDate["judgement"]["batches"][number] = {
      cutoffAt: batch.cutoff_at,
      status: judgementStatus(batch.status),
      excludedSourceCount: batchRows.filter((row) => row.settlement_status === "excluded").length,
      ...current,
      revisionHistory: batchVersions.slice(1).map((version) => judgementRevision(version, displayNamesBySourceId)),
    };
    batchesByDate.set(batch.natural_date, [...(batchesByDate.get(batch.natural_date) ?? []), judgement]);
  }

  const latestBatchSourceByDateAndSource = new Map<string, typeof batchSources[number]>();
  for (const batch of orderedBatches) {
    for (const batchSource of batchSourcesByBatch.get(batch.id) ?? []) {
      const key = `${batch.natural_date}:${batchSource.source_id}`;
      if (!latestBatchSourceByDateAndSource.has(key)) latestBatchSourceByDateAndSource.set(key, batchSource);
    }
  }
  const sourceIdsByDate = new Map<string, Set<string>>();
  for (const key of segmentGroups.keys()) {
    const separator = key.indexOf(":");
    const sourceId = key.slice(0, separator);
    const naturalDate = key.slice(separator + 1);
    sourceIdsByDate.set(naturalDate, new Set([...(sourceIdsByDate.get(naturalDate) ?? []), sourceId]));
  }
  for (const key of latestBatchSourceByDateAndSource.keys()) {
    const separator = key.indexOf(":");
    const naturalDate = key.slice(0, separator);
    const sourceId = key.slice(separator + 1);
    sourceIdsByDate.set(naturalDate, new Set([...(sourceIdsByDate.get(naturalDate) ?? []), sourceId]));
  }

  const bloggersByDate = new Map<string, XReaderBlogger[]>();
  for (const [naturalDate, dateSourceIds] of sourceIdsByDate) {
    const bloggers = [...dateSourceIds].flatMap((sourceId) => {
      const source = sourceById.get(sourceId);
      if (!source) return [];
      const batchSource = latestBatchSourceByDateAndSource.get(`${naturalDate}:${sourceId}`);
      const taskId = typeof batchSource?.x_sync_task_id === "string" ? batchSource.x_sync_task_id : undefined;
      const daySegments = [...(segmentGroups.get(`${sourceId}:${naturalDate}`) ?? [])]
        .sort((left, right) => right.occurred_through_at.localeCompare(left.occurred_through_at));
      const projectedSegments = daySegments.map((segment) => {
        const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
        const analyses = refs.flatMap((ref) => {
          const postId = ref && typeof ref === "object" ? (ref as Record<string, unknown>).post_id : undefined;
          if (typeof postId !== "string") return [];
          const canonical = canonicalByExternalId.get(`${sourceId}:${postId}`);
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
      });
      return [{
        source: { sourceKey: source.source_key, displayName: batchSource?.source_display_name ?? source.display_name },
        status: batchSource
          ? batchSourceReaderStatus(batchSource, taskId ? taskById.get(taskId) : undefined, taskId ? attemptResultByTaskId.get(taskId) : undefined)
          : "succeeded" as const,
        segments: projectedSegments,
      }];
    }).sort((left, right) => left.source.displayName.localeCompare(right.source.displayName));
    bloggersByDate.set(naturalDate, bloggers);
  }

  const dates = new Set([
    ...bloggersByDate.keys(),
    ...(input.sourceKey ? [] : batchesByDate.keys()),
  ]);
  return [...dates].map((naturalDate) => ({
    naturalDate,
    judgement: input.sourceKey
      ? { visible: false, batches: [] }
      : { visible: true, batches: (batchesByDate.get(naturalDate) ?? []).sort((left, right) => right.cutoffAt.localeCompare(left.cutoffAt)) },
    bloggers: (bloggersByDate.get(naturalDate) ?? []).sort((left, right) => left.source.displayName.localeCompare(right.source.displayName)),
  })).sort((left, right) => right.naturalDate.localeCompare(left.naturalDate));
}
