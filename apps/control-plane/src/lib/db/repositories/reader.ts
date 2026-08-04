import { presentSummary, type SummaryPresentation } from "../../../components/reader/reader-presentation";
import { createSupabaseAdminClient } from "../supabase-server";

const READER_QUERY_BATCH_SIZE = 100;
const READER_QUERY_PAGE_SIZE = 1000;

type ReaderQueryPage<Row> = { data: Row[] | null; error: unknown };

function chunkValues<Value>(values: Value[], size: number): Value[][] {
  const chunks: Value[][] = [];
  for (let index = 0; index < values.length; index += size) chunks.push(values.slice(index, index + size));
  return chunks;
}

async function readAllPages<Row>(buildPage: (from: number, to: number) => PromiseLike<ReaderQueryPage<Row>>): Promise<Row[]> {
  const rows: Row[] = [];
  for (let from = 0; ; from += READER_QUERY_PAGE_SIZE) {
    const { data, error } = await buildPage(from, from + READER_QUERY_PAGE_SIZE - 1);
    if (error) throw error;
    const page = data ?? [];
    rows.push(...page);
    if (page.length < READER_QUERY_PAGE_SIZE) return rows;
  }
}

async function readAllChunkPages<Chunk, Row>(
  chunks: Chunk[],
  buildPage: (chunk: Chunk, from: number, to: number) => PromiseLike<ReaderQueryPage<Row>>,
): Promise<Row[]> {
  const rows: Row[] = [];
  for (const chunk of chunks) rows.push(...await readAllPages((from, to) => buildPage(chunk, from, to)));
  return rows;
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

type ReaderActionIntent = "build_position" | "buy" | "add" | "hold" | "reduce" | "sell" | "watch" | "avoid";
type InputActionIntent = ReaderActionIntent | "none";

export type ReaderJudgement = {
  statement: string;
  actionIntent?: ReaderActionIntent | null;
  actionScope?: string;
  conditions?: string[];
  supportingDisplayNames: string[];
  dissentingDisplayNames: string[];
  uncertainties: string[];
};

type XReaderSegment = {
  occurredFromAt: string;
  occurredThroughAt: string;
  viewpoints: string[];
  securityIndustryViewpoints?: ReaderJudgement[];
  marketStructureViewpoints?: ReaderJudgement[];
  strategyMindsetViewpoints?: ReaderJudgement[];
  uncertainties: string[];
  analyses: Array<{
    postLink: string;
    bloggerViewpoint: string | null;
    actionIntent?: ReaderActionIntent | null;
    actionScope?: string;
    conditions?: string[];
    arguments: string[];
    quotedPostViewpoint: string | null;
    uncertainties: string[];
  }>;
};

export type XReaderBlogger = {
  source: { sourceKey: string; displayName: string };
  status: ReaderStatus;
  timedOut: boolean;
  segments: XReaderSegment[];
};

export type XReaderJudgementRevision = {
  revision: number;
  coverageStatus: "complete" | "partial" | "no_new_information";
  stockViewpoints: ReaderJudgement[];
  marketIndustryViewpoints: ReaderJudgement[];
  strategyMindsetViewpoints?: ReaderJudgement[];
  uncertainties: string[];
};

export type XReaderDate = {
  naturalDate: string;
  judgement: {
    visible: boolean;
    batches: Array<{
      cutoffAt: string;
      coverageStatus: XReaderJudgementRevision["coverageStatus"] | null;
      status: "succeeded" | "judgement_pending" | "judgement_failed";
      revision: number;
      stockViewpoints: ReaderJudgement[];
      marketIndustryViewpoints: ReaderJudgement[];
      strategyMindsetViewpoints?: ReaderJudgement[];
      uncertainties: string[];
      includedSourceCount: number;
      noNewSourceCount: number;
      excludedSourceCount: number;
      timedOutSourceCount: number;
      revisionHistory: XReaderJudgementRevision[];
      verificationRecovery?: {
        stockViewpoints: ReaderJudgement[];
        marketIndustryViewpoints: ReaderJudgement[];
        strategyMindsetViewpoints?: ReaderJudgement[];
        uncertainties: string[];
      };
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

function inputActionIntent(value: unknown): InputActionIntent | null {
  return typeof value === "string" && ["build_position", "buy", "add", "hold", "reduce", "sell", "watch", "avoid", "none"].includes(value)
    ? value as InputActionIntent : null;
}

function judgementItems(value: unknown, displayNames: Map<string, string>): ReaderJudgement[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const judgement = object(item);
    if (!judgement || typeof judgement.statement !== "string") return [];
    const actionIntent = inputActionIntent(judgement.action_intent) ?? "none";
    const actionScope = typeof judgement.action_scope === "string" ? judgement.action_scope : "";
    const conditions = strings(judgement.conditions);
    const validAction = actionIntent === "none" ? actionScope === "" : actionScope !== "";
    return [{
      statement: judgement.statement,
      actionIntent: validAction && actionIntent !== "none" ? actionIntent : null,
      actionScope: validAction ? actionScope : "",
      conditions: validAction ? conditions : [],
      supportingDisplayNames: strings(judgement.supporting_source_ids).flatMap((sourceId) => displayNames.has(sourceId) ? [displayNames.get(sourceId)!] : []),
      dissentingDisplayNames: strings(judgement.dissenting_source_ids).flatMap((sourceId) => displayNames.has(sourceId) ? [displayNames.get(sourceId)!] : []),
      uncertainties: strings(judgement.uncertainties),
    }];
  });
}

function bloggerViewpointItems(value: unknown): ReaderJudgement[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const viewpoint = object(item);
    const actionIntent = inputActionIntent(viewpoint?.action_intent) ?? "none";
    const actionScope = typeof viewpoint?.action_scope === "string" ? viewpoint.action_scope : "";
    const statement = typeof viewpoint?.statement === "string" ? viewpoint.statement : "";
    if (!statement || (actionIntent === "none" ? actionScope !== "" : actionScope === "")) return [];
    return [{ statement, actionIntent: actionIntent === "none" ? null : actionIntent, actionScope,
      conditions: strings(viewpoint?.conditions), supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties: strings(viewpoint?.uncertainties) }];
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
    stockViewpoints: judgementItems(output?.security_industry_viewpoints ?? output?.stock_viewpoints, displayNames),
    marketIndustryViewpoints: judgementItems(output?.market_structure_viewpoints ?? output?.market_industry_viewpoints, displayNames),
    strategyMindsetViewpoints: judgementItems(output?.strategy_mindset_viewpoints, displayNames),
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
  const sources = await readAllPages((from, to) => {
    let query = supabase.from("sources").select("id,source_key,display_name").eq("source_type", "x");
    if (input.sourceKey) query = query.eq("source_key", input.sourceKey);
    return query.order("display_name", { ascending: true }).order("id", { ascending: true }).range(from, to);
  });
  if (!sources.length) return [];

  const sourceIds = sources.map((source) => source.id);
  const sourceIdChunks = chunkValues(sourceIds, READER_QUERY_BATCH_SIZE);
  const sourceIdSet = new Set(sourceIds);
  const sourceById = new Map(sources.map((source) => [source.id, source]));
  const segments = await readAllChunkPages(sourceIdChunks, (ids, from, to) => {
    let query = supabase.from("x_daily_viewpoint_segments")
      .select("source_id,natural_date,occurred_from_at,occurred_through_at,schema_version,prompt_version,segment_output,window_viewpoints,post_analysis_refs")
      .in("source_id", ids);
    if (input.date) query = query.eq("natural_date", input.date);
    return query.order("natural_date", { ascending: false }).order("occurred_from_at", { ascending: true })
      .order("source_id", { ascending: true }).order("id", { ascending: true }).range(from, to);
  });
  const requestedPostIds = new Set<string>();
  for (const segment of segments) {
    const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
    for (const ref of refs) if (ref && typeof ref === "object" && "post_id" in ref && typeof (ref as Record<string, unknown>).post_id === "string") requestedPostIds.add((ref as Record<string, string>).post_id);
  }
  const requestedPostIdChunks = chunkValues([...requestedPostIds], READER_QUERY_BATCH_SIZE);
  const canonicalQueryChunks = sourceIdChunks.flatMap((sourceIds) => requestedPostIdChunks.map((postIds) => ({ sourceIds, postIds })));
  const canonicalRows = await readAllChunkPages(canonicalQueryChunks, ({ sourceIds: ids, postIds }, from, to) => (
    supabase.from("canonical_messages").select("id,source_id,external_message_id")
      .in("source_id", ids).in("external_message_id", postIds)
      .order("source_id", { ascending: true }).order("external_message_id", { ascending: true }).order("id", { ascending: true }).range(from, to)
  ));
  const canonicalByExternalId = new Map(canonicalRows.map((row) => [`${row.source_id}:${row.external_message_id}`, row]));
  const canonicalIds = canonicalRows.map((row) => row.id);
  const canonicalIdChunks = chunkValues(canonicalIds, READER_QUERY_BATCH_SIZE);
  const [analysisRows, contextRows] = await Promise.all([
    readAllChunkPages(canonicalIdChunks, (ids, from, to) => supabase.from("x_post_analyses")
      .select("canonical_message_id,analysis_version,schema_version,prompt_version,analysis_output,blogger_viewpoint,arguments,quoted_post_viewpoint,uncertainties")
      .in("canonical_message_id", ids)
      .order("canonical_message_id", { ascending: true }).order("analysis_version", { ascending: true }).range(from, to)),
    readAllChunkPages(canonicalIdChunks, (ids, from, to) => supabase.from("x_post_contexts").select("canonical_message_id,post_url")
      .in("canonical_message_id", ids).order("canonical_message_id", { ascending: true }).range(from, to)),
  ]);
  const analysisByCanonicalId = new Map(analysisRows.map((row) => [`${row.canonical_message_id}:${row.analysis_version}`, row]));
  const contextByCanonicalId = new Map(contextRows.map((row) => [row.canonical_message_id, row]));

  const batches = await readAllPages((from, to) => {
    let query = supabase.from("x_collection_batches").select("id,natural_date,cutoff_at,status");
    if (input.date) query = query.eq("natural_date", input.date);
    return query.order("natural_date", { ascending: false }).order("cutoff_at", { ascending: false })
      .order("id", { ascending: true }).range(from, to);
  });
  const orderedBatches = [...batches].sort((left, right) => right.cutoff_at.localeCompare(left.cutoff_at));
  const batchIds = orderedBatches.map((batch) => batch.id);
  const batchIdChunks = chunkValues(batchIds, READER_QUERY_BATCH_SIZE);
  const [versions, allBatchSources, replays] = await Promise.all([
    readAllChunkPages(batchIdChunks, (ids, from, to) => supabase.from("x_daily_judgement_versions")
      .select("batch_id,revision,coverage_status,output").in("batch_id", ids)
      .order("batch_id", { ascending: true }).order("revision", { ascending: false }).range(from, to)),
    readAllChunkPages(batchIdChunks, (ids, from, to) => supabase.from("x_collection_batch_sources")
      .select("batch_id,source_id,source_display_name,x_sync_task_id,settlement_status,exclusion_code").in("batch_id", ids)
      .order("batch_id", { ascending: true }).order("source_id", { ascending: true }).range(from, to)),
    readAllChunkPages(batchIdChunks, (ids, from, to) => supabase.from("x_v3_verification_replays")
      .select("id,source_batch_id,status").eq("status", "succeeded").in("source_batch_id", ids)
      .order("source_batch_id", { ascending: true }).order("id", { ascending: true }).range(from, to)),
  ]);

  const succeededReplays = replays.filter((replay) => replay.status === "succeeded" && typeof replay.id === "string" && typeof replay.source_batch_id === "string");
  const replayIds = succeededReplays.map((replay) => replay.id);
  const verificationVersions = await readAllChunkPages(chunkValues(replayIds, READER_QUERY_BATCH_SIZE), (ids, from, to) => supabase.from("x_v3_verification_versions")
    .select("replay_id,output,schema_version,prompt_version").in("replay_id", ids)
    .order("replay_id", { ascending: true }).range(from, to));
  const verificationVersionByReplayId = new Map(verificationVersions
    .filter((version) => version.schema_version === "v3-x-cross-blogger" && version.prompt_version === "v3-x-cross-blogger-1" && typeof version.replay_id === "string")
    .map((version) => [version.replay_id, version]));
  const succeededReplayByBatchId = new Map(succeededReplays
    .filter((replay) => verificationVersionByReplayId.has(replay.id))
    .map((replay) => [replay.source_batch_id, replay]));

  const batchSources = allBatchSources.filter((row) => sourceIdSet.has(row.source_id));
  const batchSourcesByBatch = new Map<string, typeof batchSources>();
  for (const row of batchSources) batchSourcesByBatch.set(row.batch_id, [...(batchSourcesByBatch.get(row.batch_id) ?? []), row]);
  const taskIds = [...new Set(batchSources.flatMap((row) => typeof row.x_sync_task_id === "string" ? [row.x_sync_task_id] : []))];
  const taskIdChunks = chunkValues(taskIds, READER_QUERY_BATCH_SIZE);
  const [taskRows, attemptRows] = await Promise.all([
    readAllChunkPages(taskIdChunks, (ids, from, to) => supabase.from("sync_tasks").select("id,status").in("id", ids)
      .order("id", { ascending: true }).range(from, to)),
    readAllChunkPages(taskIdChunks, (ids, from, to) => supabase.from("task_attempts").select("task_id,result,updated_at").in("task_id", ids)
      .order("updated_at", { ascending: false }).order("task_id", { ascending: true })
      .order("attempt", { ascending: false }).order("id", { ascending: true }).range(from, to)),
  ]);
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
      coverageStatus: null,
      stockViewpoints: [],
      marketIndustryViewpoints: [],
      strategyMindsetViewpoints: [],
      uncertainties: [],
    };
    const judgement: XReaderDate["judgement"]["batches"][number] = {
      cutoffAt: batch.cutoff_at,
      status: judgementStatus(batch.status),
      includedSourceCount: batchRows.filter((row) => row.settlement_status === "included").length,
      noNewSourceCount: batchRows.filter((row) => row.settlement_status === "no_new_information").length,
      excludedSourceCount: batchRows.filter((row) => row.settlement_status === "excluded").length,
      timedOutSourceCount: batchRows.filter((row) => row.settlement_status === "excluded" && row.exclusion_code === "settlement_deadline_exceeded").length,
      ...current,
      revisionHistory: batchVersions.slice(1).map((version) => judgementRevision(version, displayNamesBySourceId)),
    };
    const replay = succeededReplayByBatchId.get(batch.id);
    const verificationVersion = replay ? verificationVersionByReplayId.get(replay.id) : undefined;
    if (batch.status === "judgement_failed" && verificationVersion) {
      const recovery = judgementRevision({ revision: 1, coverage_status: "complete", output: verificationVersion.output }, displayNamesBySourceId);
      judgement.verificationRecovery = {
        stockViewpoints: recovery.stockViewpoints,
        marketIndustryViewpoints: recovery.marketIndustryViewpoints,
        strategyMindsetViewpoints: recovery.strategyMindsetViewpoints,
        uncertainties: recovery.uncertainties,
      };
    }
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
          const referencedVersion = ref && typeof ref === "object" ? (ref as Record<string, unknown>).analysis_version : undefined;
          const analysisVersion = typeof referencedVersion === "number" ? referencedVersion : segment.schema_version === "v3-x-window" ? undefined : 1;
          if (typeof postId !== "string" || typeof analysisVersion !== "number") return [];
          const canonical = canonicalByExternalId.get(`${sourceId}:${postId}`);
          if (!canonical) return [];
          const analysis = analysisByCanonicalId.get(`${canonical.id}:${analysisVersion}`);
          const context = contextByCanonicalId.get(canonical.id);
          if (!analysis || !context) return [];
          const output = analysis.schema_version === "v3-x-post-analysis" && analysis.prompt_version === "v3-x-post-analysis-1" ? object(analysis.analysis_output) : null;
          if (analysisVersion === 2 && !output) return [];
          const actionIntent = inputActionIntent(output?.action_intent) ?? "none";
          const actionScope = typeof output?.action_scope === "string" ? output.action_scope : "";
          const validAction = actionIntent === "none" ? actionScope === "" : actionScope !== "";
          return [{ postLink: context.post_url, bloggerViewpoint: output && typeof output.blogger_viewpoint === "string" ? output.blogger_viewpoint : analysis.blogger_viewpoint,
            actionIntent: validAction && actionIntent !== "none" ? actionIntent : null, actionScope: validAction ? actionScope : "", conditions: validAction ? strings(output?.conditions) : [],
            arguments: strings(analysis.arguments), quotedPostViewpoint: analysis.quoted_post_viewpoint,
            uncertainties: strings(analysis.uncertainties) }];
        });
        const segmentOutput = segment.schema_version === "v3-x-window" && segment.prompt_version === "v3-x-window-1" ? object(segment.segment_output) : null;
        return { occurredFromAt: segment.occurred_from_at, occurredThroughAt: segment.occurred_through_at,
          viewpoints: segmentOutput ? [] : strings(segment.window_viewpoints),
          securityIndustryViewpoints: bloggerViewpointItems(segmentOutput?.security_industry_viewpoints),
          marketStructureViewpoints: bloggerViewpointItems(segmentOutput?.market_structure_viewpoints),
          strategyMindsetViewpoints: bloggerViewpointItems(segmentOutput?.strategy_mindset_viewpoints),
          uncertainties: segmentOutput ? strings(segmentOutput.uncertainties) : [], analyses };
      });
      return [{
        source: { sourceKey: source.source_key, displayName: batchSource?.source_display_name ?? source.display_name },
        status: batchSource
          ? batchSourceReaderStatus(batchSource, taskId ? taskById.get(taskId) : undefined, taskId ? attemptResultByTaskId.get(taskId) : undefined)
          : "succeeded" as const,
        timedOut: batchSource?.settlement_status === "excluded" && batchSource.exclusion_code === "settlement_deadline_exceeded",
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
