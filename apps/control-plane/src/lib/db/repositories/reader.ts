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
type ReaderActionScopeStatus = "specified" | "unspecified";
type XPostType = "original" | "quote" | "reply" | "repost";

export type ReaderJudgement = {
  statement: string;
  actionIntent?: ReaderActionIntent | null;
  actionScope?: string;
  actionScopeStatus?: ReaderActionScopeStatus | null;
  conditions?: string[];
  supportingDisplayNames: string[];
  dissentingDisplayNames: string[];
  uncertainties: string[];
};

export type ReaderThesis = {
  headline: string;
  synthesis: string;
  scenarioBranches: Array<{ condition: string; outcome: string; uncertainties: string[] }>;
  attributedActions: Array<{
    displayName: string;
    actionIntent: ReaderActionIntent;
    actionScope: string;
    actionScopeStatus: ReaderActionScopeStatus;
    conditions: string[];
    uncertainties: string[];
  }>;
  supportingDisplayNames: string[];
  dissentingDisplayNames: string[];
  uncertainties: string[];
};

export type ReaderCrossBloggerIntegration = {
  headline: string;
  synthesis: string;
  commonPoints: Array<{ statement: string; displayNames: string[] }>;
  conflictPoints: Array<{ issue: string; positions: Array<{ position: string; displayNames: string[] }> }>;
  uncertainties: string[];
};

export type ReaderAiAssessment = {
  headline: string;
  judgement: string;
  importanceReason: string;
  reasoning: string;
  keyAssumptions: string[];
  risks: string[];
  watchVariables: string[];
  uncertainties: string[];
};

export type ReaderAiSynthesis = {
  crossBloggerIntegrations: ReaderCrossBloggerIntegration[];
  aiAssessments: ReaderAiAssessment[];
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
    postedAt?: string | null;
    postType?: XPostType | null;
    bloggerViewpoint: string | null;
    actionIntent?: ReaderActionIntent | null;
    actionScope?: string;
    actionScopeStatus?: ReaderActionScopeStatus;
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
  lateArrival: boolean;
  collectionGaps: Array<{ startAt: string; endAt: string }>;
  segments: XReaderSegment[];
};

export type XReaderCollectionGap = {
  source: { sourceKey: string; displayName: string };
  gaps: XReaderBlogger["collectionGaps"];
};

export type XReaderJudgementRevision = {
  revision: number;
  coverageStatus: "complete" | "partial" | "no_new_information";
  presentationKind: "legacy" | "v5";
  stockViewpoints: ReaderJudgement[];
  marketIndustryViewpoints: ReaderJudgement[];
  strategyMindsetViewpoints?: ReaderJudgement[];
  aiSynthesis?: ReaderAiSynthesis;
  securityIndustryTheses?: ReaderThesis[];
  marketStructureTheses?: ReaderThesis[];
  strategyMindsetTheses?: ReaderThesis[];
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
      presentationKind: XReaderJudgementRevision["presentationKind"];
      stockViewpoints: ReaderJudgement[];
      marketIndustryViewpoints: ReaderJudgement[];
      strategyMindsetViewpoints?: ReaderJudgement[];
      aiSynthesis?: ReaderAiSynthesis;
      securityIndustryTheses?: ReaderThesis[];
      marketStructureTheses?: ReaderThesis[];
      strategyMindsetTheses?: ReaderThesis[];
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
  collectionGaps?: XReaderCollectionGap[];
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

function actionScopeStatus(intent: InputActionIntent, scope: string, value: unknown, uncertainties: string[]): ReaderActionScopeStatus | null {
  if (intent === "none") return null;
  if (value === "specified" && scope) return "specified";
  if (value === "unspecified" && !scope) return "unspecified";
  return !scope || /(?:未|不|无法)(?:明确|说明|提供|确认).{0,24}(?:标的|对象|资产|范围)|(?:标的|对象|资产|范围).{0,24}(?:(?:未|不|无法)(?:明确|说明|提供|确认)|未知)/.test(scope) || uncertainties.some((item) => /(?:未|不|无法)(?:明确|说明|提供|确认).{0,24}(?:标的|对象|资产|范围)|(?:标的|对象|资产|范围).{0,24}(?:(?:未|不|无法)(?:明确|说明|提供|确认)|未知)/.test(item)) ? "unspecified" : "specified";
}

function judgementItems(value: unknown, displayNames: Map<string, string>, replacements: Map<string, string>): ReaderJudgement[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const judgement = object(item);
    if (!judgement || typeof judgement.statement !== "string") return [];
    const actionIntent = inputActionIntent(judgement.action_intent) ?? "none";
    const statement = readableText(judgement.statement, replacements);
    const actionScope = readableText(judgement.action_scope, replacements) ?? "";
    const conditions = readableTexts(judgement.conditions, replacements);
    const uncertainties = readableTexts(judgement.uncertainties, replacements);
    const scopeStatus = actionScopeStatus(actionIntent, actionScope, judgement.action_scope_status, uncertainties);
    const validAction = Boolean(statement) && (actionIntent === "none" ? actionScope === "" : scopeStatus !== null);
    if (!validAction || !statement) return [];
    return [{
      statement,
      actionIntent: validAction && actionIntent !== "none" ? actionIntent : null,
      actionScope: validAction ? actionScope : "",
      actionScopeStatus: validAction ? scopeStatus ?? undefined : undefined,
      conditions: validAction ? conditions : [],
      supportingDisplayNames: strings(judgement.supporting_source_ids).flatMap((sourceId) => displayNames.has(sourceId) ? [displayNames.get(sourceId)!] : []),
      dissentingDisplayNames: strings(judgement.dissenting_source_ids).flatMap((sourceId) => displayNames.has(sourceId) ? [displayNames.get(sourceId)!] : []),
      uncertainties,
    }];
  });
}

function displayNameItems(value: unknown, displayNames: Map<string, string>): string[] {
  return strings(value).flatMap((sourceId) => displayNames.has(sourceId) ? [displayNames.get(sourceId)!] : []);
}

function textReplacements(output: Record<string, unknown> | null, displayNames: Map<string, string>): Map<string, string> {
  const replacements = new Map<string, string>(displayNames);
  if (!output) return replacements;
  for (const key of ["security_industry_theses", "market_structure_theses", "strategy_mindset_theses"] as const) {
    const theses = output[key];
    if (!Array.isArray(theses)) continue;
    for (const item of theses) {
      const thesis = object(item);
      if (typeof thesis?.thesis_id === "string" && typeof thesis.headline === "string") replacements.set(thesis.thesis_id, thesis.headline);
    }
  }
  return replacements;
}

function readableText(value: unknown, replacements: Map<string, string>): string | null {
  if (typeof value !== "string") return null;
  let text = value;
  for (const [token, replacement] of replacements) text = text.replaceAll(token, replacement);
  text = text
    .replace(/\b(?:integration|assessment|thesis|security|market|strategy|source|post|analysis|batch|run|segment)-[a-z0-9_-]+(?:@\d+)?\b/gi, "")
    .replace(/\s{2,}/g, " ")
    .trim();
  return text && /[\p{L}\p{N}]/u.test(text) ? text : null;
}

function readableTexts(value: unknown, replacements: Map<string, string>): string[] {
  return strings(value).flatMap((item) => {
    const text = readableText(item, replacements);
    return text ? [text] : [];
  });
}

function bloggerViewpointItems(value: unknown, replacements: Map<string, string>): ReaderJudgement[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const viewpoint = object(item);
    const actionIntent = inputActionIntent(viewpoint?.action_intent) ?? "none";
    const actionScope = readableText(viewpoint?.action_scope, replacements) ?? "";
    const statement = readableText(viewpoint?.statement, replacements) ?? "";
    const uncertainties = readableTexts(viewpoint?.uncertainties, replacements);
    const scopeStatus = actionScopeStatus(actionIntent, actionScope, viewpoint?.action_scope_status, uncertainties);
    if (!statement || (actionIntent === "none" ? actionScope !== "" : !scopeStatus)) return [];
    return [{ statement, actionIntent: actionIntent === "none" ? null : actionIntent, actionScope, actionScopeStatus: scopeStatus ?? undefined,
      conditions: readableTexts(viewpoint?.conditions, replacements), supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties }];
  });
}

function thesisScenarioBranches(value: unknown, replacements: Map<string, string>): ReaderThesis["scenarioBranches"] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const branch = object(item);
    const condition = readableText(branch?.condition, replacements);
    const outcome = readableText(branch?.outcome, replacements);
    return condition && outcome
      ? [{ condition, outcome, uncertainties: readableTexts(branch?.uncertainties, replacements) }]
      : [];
  });
}

function thesisAttributedActions(
  value: unknown,
  displayNames: Map<string, string>,
  replacements: Map<string, string>,
): ReaderThesis["attributedActions"] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const action = object(item);
    const displayName = typeof action?.source_id === "string" ? displayNames.get(action.source_id) : undefined;
    const actionIntent = inputActionIntent(action?.action_intent);
    const actionScope = readableText(action?.action_scope, replacements) ?? "";
    const uncertainties = readableTexts(action?.uncertainties, replacements);
    const scopeStatus = actionIntent ? actionScopeStatus(actionIntent, actionScope, action?.action_scope_status, uncertainties) : null;
    if (!displayName || !actionIntent || actionIntent === "none" || !scopeStatus) return [];
    return [{
      displayName,
      actionIntent,
      actionScope,
      actionScopeStatus: scopeStatus,
      conditions: readableTexts(action?.conditions, replacements),
      uncertainties,
    }];
  });
}

function thesisItems(value: unknown, displayNames: Map<string, string>, replacements: Map<string, string>): ReaderThesis[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const thesis = object(item);
    const headline = readableText(thesis?.headline, replacements);
    const synthesis = readableText(thesis?.synthesis, replacements);
    return headline && synthesis
      ? [{
        headline,
        synthesis,
        scenarioBranches: thesisScenarioBranches(thesis?.scenario_branches, replacements),
        attributedActions: thesisAttributedActions(thesis?.attributed_actions, displayNames, replacements),
        supportingDisplayNames: displayNameItems(thesis?.supporting_source_ids, displayNames),
        dissentingDisplayNames: displayNameItems(thesis?.dissenting_source_ids, displayNames),
        uncertainties: readableTexts(thesis?.uncertainties, replacements),
      }]
      : [];
  });
}

function integrationItems(
  value: unknown,
  displayNames: Map<string, string>,
  replacements: Map<string, string>,
): ReaderCrossBloggerIntegration[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const integration = object(item);
    const headline = readableText(integration?.headline, replacements);
    const synthesis = readableText(integration?.synthesis, replacements);
    if (!headline || !synthesis) return [];
    const commonPoints = Array.isArray(integration?.common_points)
      ? integration.common_points.flatMap((point) => {
        const commonPoint = object(point);
        const statement = readableText(commonPoint?.statement, replacements);
        return statement
          ? [{ statement, displayNames: displayNameItems(commonPoint?.source_ids, displayNames) }]
          : [];
      })
      : [];
    const conflictPoints = Array.isArray(integration?.conflict_points)
      ? integration.conflict_points.flatMap((point) => {
        const conflictPoint = object(point);
        const issue = readableText(conflictPoint?.issue, replacements);
        if (!issue || !Array.isArray(conflictPoint?.positions)) return [];
        return [{
          issue,
          positions: conflictPoint.positions.flatMap((position) => {
            const item = object(position);
            const text = readableText(item?.position, replacements);
            return text
              ? [{ position: text, displayNames: displayNameItems(item?.source_ids, displayNames) }]
              : [];
          }),
        }];
      })
      : [];
    return [{
      headline,
      synthesis,
      commonPoints,
      conflictPoints,
      uncertainties: readableTexts(integration?.uncertainties, replacements),
    }];
  });
}

function aiAssessments(value: unknown, replacements: Map<string, string>): ReaderAiAssessment[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const assessment = object(item);
    const headline = readableText(assessment?.headline, replacements);
    const judgement = readableText(assessment?.judgement, replacements);
    const importanceReason = readableText(assessment?.importance_reason, replacements);
    const reasoning = readableText(assessment?.reasoning, replacements);
    return headline
      && judgement
      && importanceReason
      && reasoning
      ? [{
        headline,
        judgement,
        importanceReason,
        reasoning,
        keyAssumptions: readableTexts(assessment?.key_assumptions, replacements),
        risks: readableTexts(assessment?.risks, replacements),
        watchVariables: readableTexts(assessment?.watch_variables, replacements),
        uncertainties: readableTexts(assessment?.uncertainties, replacements),
      }]
      : [];
  });
}

function aiSynthesis(value: unknown, displayNames: Map<string, string>): ReaderAiSynthesis {
  const synthesis = object(value);
  const replacements = textReplacements(object({ ai_synthesis: synthesis }), displayNames);
  return {
    crossBloggerIntegrations: integrationItems(synthesis?.cross_blogger_integrations, displayNames, replacements),
    aiAssessments: aiAssessments(synthesis?.ai_assessments, replacements),
  };
}

function judgementStatus(status: string): "succeeded" | "judgement_pending" | "judgement_failed" {
  if (status === "succeeded") return "succeeded";
  return status === "judgement_failed" ? "judgement_failed" : "judgement_pending";
}

function judgementRevision(
  version: { revision: number; coverage_status: "complete" | "partial" | "no_new_information"; output: unknown; schema_version?: unknown; prompt_version?: unknown },
  displayNames: Map<string, string>,
): XReaderJudgementRevision {
  const output = object(version.output);
  const schemaVersion = typeof version.schema_version === "string" ? version.schema_version : "";
  const promptVersion = typeof version.prompt_version === "string" ? version.prompt_version : "";
  const versionPair = `${schemaVersion}:${promptVersion}`;
  if (versionPair === "v5-x-cross-blogger:v5-x-cross-blogger-1") {
    const replacements = textReplacements(output, displayNames);
    return {
      revision: version.revision,
      coverageStatus: version.coverage_status,
      presentationKind: "v5",
      stockViewpoints: [],
      marketIndustryViewpoints: [],
      strategyMindsetViewpoints: [],
      aiSynthesis: {
        crossBloggerIntegrations: integrationItems(output?.ai_synthesis && object(output.ai_synthesis)?.cross_blogger_integrations, displayNames, replacements),
        aiAssessments: aiAssessments(output?.ai_synthesis && object(output.ai_synthesis)?.ai_assessments, replacements),
      },
      securityIndustryTheses: thesisItems(output?.security_industry_theses, displayNames, replacements),
      marketStructureTheses: thesisItems(output?.market_structure_theses, displayNames, replacements),
      strategyMindsetTheses: thesisItems(output?.strategy_mindset_theses, displayNames, replacements),
      uncertainties: readableTexts(output?.uncertainties, replacements),
    };
  }
  if (["v2-x-cross-blogger:v2-x-cross-blogger-1", "v3-x-cross-blogger:v3-x-cross-blogger-1", "v4-x-cross-blogger:v4-x-cross-blogger-1"].includes(versionPair)) {
    return {
      revision: version.revision,
      coverageStatus: version.coverage_status,
      presentationKind: "legacy",
      stockViewpoints: judgementItems(output?.security_industry_viewpoints ?? output?.stock_viewpoints, displayNames, textReplacements(output, displayNames)),
      marketIndustryViewpoints: judgementItems(output?.market_structure_viewpoints ?? output?.market_industry_viewpoints, displayNames, textReplacements(output, displayNames)),
      strategyMindsetViewpoints: judgementItems(output?.strategy_mindset_viewpoints, displayNames, textReplacements(output, displayNames)),
      uncertainties: readableTexts(output?.uncertainties, textReplacements(output, displayNames)),
    };
  }
  return {
    revision: version.revision,
    coverageStatus: version.coverage_status,
    presentationKind: "legacy",
    stockViewpoints: [],
    marketIndustryViewpoints: [],
    strategyMindsetViewpoints: [],
    uncertainties: [],
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
      .select("source_id,natural_date,range_task_id,created_at,occurred_from_at,occurred_through_at,schema_version,prompt_version,segment_output,window_viewpoints,post_analysis_refs")
      .in("source_id", ids);
    if (input.date) query = query.eq("natural_date", input.date);
    return query.order("natural_date", { ascending: false }).order("occurred_from_at", { ascending: true })
      .order("source_id", { ascending: true }).order("id", { ascending: true }).range(from, to);
  });
  const collectionGaps = await readAllChunkPages(sourceIdChunks, (ids, from, to) => {
    let query = supabase.from("x_collection_gaps")
      .select("source_id,natural_date,window_start_at,window_end_at")
      .in("source_id", ids);
    if (input.date) query = query.eq("natural_date", input.date);
    return query.order("natural_date", { ascending: false }).order("window_start_at", { ascending: true })
      .order("source_id", { ascending: true }).range(from, to);
  });
  const requestedPostIds = new Set<string>();
  for (const segment of segments) {
    const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
    for (const ref of refs) if (ref && typeof ref === "object" && "post_id" in ref && typeof (ref as Record<string, unknown>).post_id === "string") requestedPostIds.add((ref as Record<string, string>).post_id);
  }
  const requestedPostIdChunks = chunkValues([...requestedPostIds], READER_QUERY_BATCH_SIZE);
  const canonicalQueryChunks = sourceIdChunks.flatMap((sourceIds) => requestedPostIdChunks.map((postIds) => ({ sourceIds, postIds })));
  const canonicalRows = await readAllChunkPages(canonicalQueryChunks, ({ sourceIds: ids, postIds }, from, to) => (
    supabase.from("canonical_messages").select("id,source_id,external_message_id,occurred_at")
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
    readAllChunkPages(canonicalIdChunks, (ids, from, to) => supabase.from("x_post_contexts").select("canonical_message_id,post_url,post_type")
      .in("canonical_message_id", ids).order("canonical_message_id", { ascending: true }).range(from, to)),
  ]);
  const analysisByCanonicalId = new Map(analysisRows.map((row) => [`${row.canonical_message_id}:${row.analysis_version}`, row]));
  const contextByCanonicalId = new Map(contextRows.map((row) => [row.canonical_message_id, row]));

  const batches = await readAllPages((from, to) => {
    let query = supabase.from("x_collection_batches").select("id,natural_date,cutoff_at,settlement_deadline_at,status");
    if (input.date) query = query.eq("natural_date", input.date);
    return query.order("natural_date", { ascending: false }).order("cutoff_at", { ascending: false })
      .order("id", { ascending: true }).range(from, to);
  });
  const orderedBatches = [...batches].sort((left, right) => right.cutoff_at.localeCompare(left.cutoff_at));
  const batchIds = orderedBatches.map((batch) => batch.id);
  const batchIdChunks = chunkValues(batchIds, READER_QUERY_BATCH_SIZE);
  const [versions, allBatchSources, replays] = await Promise.all([
    readAllChunkPages(batchIdChunks, (ids, from, to) => supabase.from("x_daily_judgement_versions")
      .select("batch_id,revision,coverage_status,output,schema_version,prompt_version").in("batch_id", ids)
      .order("batch_id", { ascending: true }).order("revision", { ascending: false }).range(from, to)),
    readAllChunkPages(batchIdChunks, (ids, from, to) => supabase.from("x_collection_batch_sources")
      .select("batch_id,source_id,source_display_name,x_sync_task_id,settlement_status,exclusion_code").in("batch_id", ids)
      .order("batch_id", { ascending: true }).order("source_id", { ascending: true }).range(from, to)),
    readAllChunkPages(batchIdChunks, (ids, from, to) => supabase.from("x_v3_verification_replays")
      .select("id,source_batch_id,status").eq("status", "failed").in("source_batch_id", ids)
      .order("source_batch_id", { ascending: true }).order("id", { ascending: true }).range(from, to)),
  ]);

  const failedReplays = replays.filter((replay) => replay.status === "failed" && typeof replay.id === "string" && typeof replay.source_batch_id === "string");
  const failedReplayIds = failedReplays.map((replay) => replay.id);
  const acceptanceRuns = await readAllChunkPages(chunkValues(failedReplayIds, READER_QUERY_BATCH_SIZE), (ids, from, to) => supabase.from("x_v3_verification_acceptance_runs")
    .select("id,parent_replay_id,status").eq("status", "succeeded").in("parent_replay_id", ids)
    .order("parent_replay_id", { ascending: true }).order("id", { ascending: true }).range(from, to));
  const successfulAcceptances = acceptanceRuns.filter((run) => run.status === "succeeded" && typeof run.id === "string" && typeof run.parent_replay_id === "string");
  const acceptanceIds = successfulAcceptances.map((run) => run.id);
  const verificationVersions = await readAllChunkPages(chunkValues(acceptanceIds, READER_QUERY_BATCH_SIZE), (ids, from, to) => supabase.from("x_v3_verification_acceptance_versions")
    .select("acceptance_run_id,output,schema_version,prompt_version").in("acceptance_run_id", ids)
    .order("acceptance_run_id", { ascending: true }).range(from, to));
  const verificationVersionByAcceptanceId = new Map(verificationVersions
    .filter((version) => version.schema_version === "v3-x-cross-blogger" && version.prompt_version === "v3-x-cross-blogger-1" && typeof version.acceptance_run_id === "string")
    .map((version) => [version.acceptance_run_id, version]));
  const acceptanceByParentReplayId = new Map(successfulAcceptances
    .filter((run) => verificationVersionByAcceptanceId.has(run.id))
    .map((run) => [run.parent_replay_id, run]));
  const failedReplayByBatchId = new Map(failedReplays.map((replay) => [replay.source_batch_id, replay]));

  const batchSources = allBatchSources.filter((row) => sourceIdSet.has(row.source_id));
  const batchSourcesByBatch = new Map<string, typeof batchSources>();
  for (const row of batchSources) batchSourcesByBatch.set(row.batch_id, [...(batchSourcesByBatch.get(row.batch_id) ?? []), row]);
  const taskIds = [...new Set([
    ...batchSources.flatMap((row) => typeof row.x_sync_task_id === "string" ? [row.x_sync_task_id] : []),
    ...segments.flatMap((segment) => typeof segment.range_task_id === "string" ? [segment.range_task_id] : []),
  ])];
  const taskIdChunks = chunkValues(taskIds, READER_QUERY_BATCH_SIZE);
  const [taskRows, attemptRows] = await Promise.all([
    readAllChunkPages(taskIdChunks, (ids, from, to) => supabase.from("sync_tasks").select("id,status,collection_batch_id").in("id", ids)
      .order("id", { ascending: true }).range(from, to)),
    readAllChunkPages(taskIdChunks, (ids, from, to) => supabase.from("task_attempts").select("task_id,result,updated_at").in("task_id", ids)
      .order("updated_at", { ascending: false }).order("task_id", { ascending: true })
      .order("attempt", { ascending: false }).order("id", { ascending: true }).range(from, to)),
  ]);
  const taskIdSet = new Set(taskIds);
  const taskById = new Map(taskRows.filter((task) => taskIdSet.has(task.id)).map((task) => [task.id, task]));
  const batchById = new Map(orderedBatches.map((batch) => [batch.id, batch]));
  const batchSourceByBatchAndSource = new Map(batchSources.map((row) => [`${row.batch_id}:${row.source_id}`, row]));
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
  const collectionGapsBySourceAndDate = new Map<string, Array<{ startAt: string; endAt: string }>>();
  for (const gap of collectionGaps) {
    if (!sourceIdSet.has(gap.source_id)) continue;
    const key = `${gap.source_id}:${gap.natural_date}`;
    collectionGapsBySourceAndDate.set(key, [...(collectionGapsBySourceAndDate.get(key) ?? []), {
      startAt: gap.window_start_at,
      endAt: gap.window_end_at,
    }]);
  }
  const collectionGapNoticesByDate = new Map<string, XReaderCollectionGap[]>();
  for (const [key, gaps] of collectionGapsBySourceAndDate) {
    if (segmentGroups.get(key)?.length) continue;
    const separator = key.indexOf(":");
    const sourceId = key.slice(0, separator);
    const naturalDate = key.slice(separator + 1);
    const source = sourceById.get(sourceId);
    if (!source) continue;
    collectionGapNoticesByDate.set(naturalDate, [
      ...(collectionGapNoticesByDate.get(naturalDate) ?? []),
      { source: { sourceKey: source.source_key, displayName: source.display_name }, gaps },
    ]);
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
      presentationKind: "legacy" as const,
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
    const replay = failedReplayByBatchId.get(batch.id);
    const acceptance = replay ? acceptanceByParentReplayId.get(replay.id) : undefined;
    const verificationVersion = acceptance ? verificationVersionByAcceptanceId.get(acceptance.id) : undefined;
    if (batch.status === "judgement_failed" && verificationVersion) {
      const recovery = judgementRevision({
        revision: 1,
        coverage_status: "complete",
        output: verificationVersion.output,
        schema_version: verificationVersion.schema_version,
        prompt_version: verificationVersion.prompt_version,
      }, displayNamesBySourceId);
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
  for (const key of collectionGapsBySourceAndDate.keys()) {
    const separator = key.indexOf(":");
    const naturalDate = key.slice(separator + 1);
    const sourceId = key.slice(0, separator);
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
      if (!daySegments.length && (collectionGapsBySourceAndDate.get(`${sourceId}:${naturalDate}`)?.length ?? 0) > 0) return [];
      const lateArrival = daySegments.some((segment) => {
        const rangeTaskId = typeof segment.range_task_id === "string" ? segment.range_task_id : undefined;
        const task = rangeTaskId ? taskById.get(rangeTaskId) : undefined;
        const batchId = typeof task?.collection_batch_id === "string" ? task.collection_batch_id : undefined;
        const batch = batchId ? batchById.get(batchId) : undefined;
        const batchSource = batchId ? batchSourceByBatchAndSource.get(`${batchId}:${sourceId}`) : undefined;
        return Boolean(
          batch && batchSource && (
            batchSource.settlement_status === "excluded"
            || (typeof segment.created_at === "string" && typeof batch.settlement_deadline_at === "string" && segment.created_at > batch.settlement_deadline_at)
          ),
        );
      });
      const projectedSegments = daySegments.map((segment) => {
        const refs = Array.isArray(segment.post_analysis_refs) ? segment.post_analysis_refs : [];
        const analyses = refs.flatMap((ref) => {
          const postId = ref && typeof ref === "object" ? (ref as Record<string, unknown>).post_id : undefined;
          const referencedVersion = ref && typeof ref === "object" ? (ref as Record<string, unknown>).analysis_version : undefined;
          const analysisVersion = typeof referencedVersion === "number" ? referencedVersion : ["v3-x-window", "v4-x-window"].includes(String(segment.schema_version)) ? undefined : 1;
          if (typeof postId !== "string" || typeof analysisVersion !== "number") return [];
          const canonical = canonicalByExternalId.get(`${sourceId}:${postId}`);
          if (!canonical) return [];
          const analysis = analysisByCanonicalId.get(`${canonical.id}:${analysisVersion}`);
          const context = contextByCanonicalId.get(canonical.id);
          if (!analysis || !context) return [];
          const output = (["v3-x-post-analysis", "v4-x-post-analysis"].includes(String(analysis.schema_version)) && ["v3-x-post-analysis-1", "v4-x-post-analysis-1"].includes(String(analysis.prompt_version))) ? object(analysis.analysis_output) : null;
          if (analysisVersion === 2 && !output) return [];
          const replacements = textReplacements(output, new Map());
          const actionIntent = inputActionIntent(output?.action_intent) ?? "none";
          const actionScope = readableText(output?.action_scope, replacements) ?? "";
          const uncertainties = readableTexts(analysis.uncertainties, replacements);
          const scopeStatus = actionScopeStatus(actionIntent, actionScope, output?.action_scope_status, uncertainties);
          const validAction = actionIntent === "none" ? actionScope === "" : scopeStatus !== null;
          const bloggerViewpoint = readableText(output?.blogger_viewpoint ?? analysis.blogger_viewpoint, replacements);
          return [{ postLink: context.post_url, postedAt: canonical.occurred_at ?? null, postType: context.post_type ?? null, bloggerViewpoint,
            actionIntent: validAction && actionIntent !== "none" ? actionIntent : null, actionScope: validAction ? actionScope : "", actionScopeStatus: validAction ? scopeStatus ?? undefined : undefined, conditions: validAction ? readableTexts(output?.conditions, replacements) : [],
            arguments: readableTexts(analysis.arguments, replacements), quotedPostViewpoint: readableText(analysis.quoted_post_viewpoint, replacements),
            uncertainties }];
        });
          const segmentOutput = (["v3-x-window", "v4-x-window"].includes(String(segment.schema_version)) && ["v3-x-window-1", "v4-x-window-1"].includes(String(segment.prompt_version))) ? object(segment.segment_output) : null;
        const segmentReplacements = textReplacements(segmentOutput, new Map());
        return { occurredFromAt: segment.occurred_from_at, occurredThroughAt: segment.occurred_through_at,
          viewpoints: segmentOutput ? [] : readableTexts(segment.window_viewpoints, segmentReplacements),
          securityIndustryViewpoints: bloggerViewpointItems(segmentOutput?.security_industry_viewpoints, segmentReplacements),
          marketStructureViewpoints: bloggerViewpointItems(segmentOutput?.market_structure_viewpoints, segmentReplacements),
          strategyMindsetViewpoints: bloggerViewpointItems(segmentOutput?.strategy_mindset_viewpoints, segmentReplacements),
          uncertainties: segmentOutput ? readableTexts(segmentOutput.uncertainties, segmentReplacements) : [], analyses };
      });
      return [{
        source: { sourceKey: source.source_key, displayName: batchSource?.source_display_name ?? source.display_name },
        status: batchSource
          ? batchSourceReaderStatus(batchSource, taskId ? taskById.get(taskId) : undefined, taskId ? attemptResultByTaskId.get(taskId) : undefined)
          : "succeeded" as const,
        timedOut: batchSource?.settlement_status === "excluded" && batchSource.exclusion_code === "settlement_deadline_exceeded",
        lateArrival,
        collectionGaps: collectionGapsBySourceAndDate.get(`${sourceId}:${naturalDate}`) ?? [],
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
    collectionGaps: collectionGapNoticesByDate.get(naturalDate) ?? [],
    bloggers: (bloggersByDate.get(naturalDate) ?? []).sort((left, right) => left.source.displayName.localeCompare(right.source.displayName)),
  })).sort((left, right) => right.naturalDate.localeCompare(left.naturalDate));
}
