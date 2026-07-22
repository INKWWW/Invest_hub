export type LegacyTopicPresentation = {
  title: string;
  summary: string;
  evidenceCount: number;
  tickers: string[];
  operationTendency: string | null;
  uncertainty: string | null;
};

export type V11AuthorCardPresentation = {
  authorDisplay: string;
  marketTrend: string | null;
  stockJudgments: Array<{ subject: string | null; judgment: string; reasoning: string | null; evidenceCount: number }>;
  marketTendency: string | null;
  stockTendency: string | null;
  methodology: string[];
  uncertainty: string[];
  evidenceCount: number;
};

export type V11TopicPresentation = {
  title: string;
  overview: string;
  viewpoints: Array<{ authorDisplay: string; viewpoint: string; reasoning: string | null; tendency: string | null; evidenceCount: number }>;
  uncertainty: string[];
  evidenceCount: number;
};

export type SummaryPresentation =
  | { kind: "empty" }
  | { kind: "legacy"; topics: LegacyTopicPresentation[]; warnings: string[]; mediaUnparsed: boolean }
  | { kind: "v1.1"; asOf: string; authorCards: V11AuthorCardPresentation[]; topicDiscussions: V11TopicPresentation[]; warnings: string[] };

type JsonRecord = Record<string, unknown>;

function record(value: unknown): JsonRecord | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  return value as JsonRecord;
}

function strings(value: unknown): string[] | null {
  return Array.isArray(value) && value.every((item) => typeof item === "string") ? value : null;
}

function requiredString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function nullableString(value: unknown): string | null | undefined {
  return value === null ? null : requiredString(value) ?? undefined;
}

function countEvidence(value: unknown): number | null {
  const ids = strings(value);
  return ids && ids.length > 0 ? ids.length : null;
}

function hasExactKeys(value: JsonRecord, expected: string[]): boolean {
  const keys = Object.keys(value);
  return keys.length === expected.length && keys.every((key) => expected.includes(key));
}

function presentLegacy(output: JsonRecord, coverage: unknown): SummaryPresentation {
  const topics = output.topics;
  const warnings = strings(output.warnings);
  if (!Array.isArray(topics) || !warnings) return { kind: "empty" };
  const projected: LegacyTopicPresentation[] = [];
  for (const value of topics) {
    const topic = record(value);
    if (!topic) continue;
    const title = requiredString(topic.title);
    const summary = requiredString(topic.summary);
    const evidence = countEvidence(topic.source_message_ids);
    const tickers = strings(topic.tickers ?? []);
    const operationTendency = nullableString(topic.operation_tendency);
    const uncertainty = nullableString(topic.uncertainty);
    if (!title || !summary || evidence === null || !tickers || operationTendency === undefined || uncertainty === undefined) continue;
    projected.push({ title, summary, evidenceCount: evidence, tickers, operationTendency, uncertainty });
  }
  const coverageRecord = record(coverage);
  return { kind: "legacy", topics: projected, warnings, mediaUnparsed: coverageRecord?.unparsed_media === true };
}

function presentV11(output: JsonRecord, coverage: unknown): SummaryPresentation {
  if (!hasExactKeys(output, ["schema_version", "natural_date", "as_of", "author_cards", "topic_discussions", "warnings"])) return { kind: "empty" };
  const asOf = requiredString(output.as_of);
  const cards = output.author_cards;
  const discussions = output.topic_discussions;
  const warnings = strings(output.warnings);
  if (!asOf || !Array.isArray(cards) || !Array.isArray(discussions) || !warnings) return { kind: "empty" };
  if (record(coverage)?.unparsed_media === true && !warnings.includes("存在未解析媒体")) return { kind: "empty" };

  const authorCards: V11AuthorCardPresentation[] = [];
  for (const value of cards) {
    const card = record(value);
    const coreLogic = record(card?.core_logic);
    const tendency = record(card?.operation_tendency);
    if (!card || !coreLogic || !tendency
      || !hasExactKeys(card, ["author_id", "author_display", "core_logic", "operation_tendency", "methodology", "uncertainty", "source_message_ids"])
      || !hasExactKeys(coreLogic, ["market_trend", "stock_judgments"])
      || !hasExactKeys(tendency, ["market", "stocks"])) return { kind: "empty" };
    const authorDisplay = requiredString(card?.author_display);
    const marketTrend = nullableString(coreLogic?.market_trend);
    const stockJudgments = coreLogic?.stock_judgments;
    const marketTendency = nullableString(tendency?.market);
    const stockTendency = nullableString(tendency?.stocks);
    const methodology = strings(card?.methodology);
    const uncertainty = strings(card?.uncertainty);
    const evidence = countEvidence(card?.source_message_ids);
    if (!authorDisplay || marketTrend === undefined || !Array.isArray(stockJudgments) || marketTendency === undefined || stockTendency === undefined || !methodology || !uncertainty || evidence === null) return { kind: "empty" };
    const projectedJudgments: V11AuthorCardPresentation["stockJudgments"] = [];
    let valid = true;
    for (const item of stockJudgments) {
      const judgment = record(item);
      const subject = nullableString(judgment?.subject);
      const conclusion = requiredString(judgment?.judgment);
      const reasoning = nullableString(judgment?.reasoning);
      const judgmentEvidence = countEvidence(judgment?.source_message_ids);
      if (!judgment || !hasExactKeys(judgment, ["subject", "judgment", "reasoning", "source_message_ids"]) || subject === undefined || !conclusion || reasoning === undefined || judgmentEvidence === null) { valid = false; break; }
      projectedJudgments.push({ subject, judgment: conclusion, reasoning, evidenceCount: judgmentEvidence });
    }
    if (!valid) return { kind: "empty" };
    authorCards.push({ authorDisplay, marketTrend, stockJudgments: projectedJudgments, marketTendency, stockTendency, methodology, uncertainty, evidenceCount: evidence });
  }

  const topicDiscussions: V11TopicPresentation[] = [];
  for (const value of discussions) {
    const topic = record(value);
    if (!topic || !hasExactKeys(topic, ["title", "summary", "viewpoints", "uncertainty", "source_message_ids"])) return { kind: "empty" };
    const title = requiredString(topic?.title);
    const overview = requiredString(topic?.summary);
    const viewpoints = topic?.viewpoints;
    const uncertainty = strings(topic?.uncertainty);
    const evidence = countEvidence(topic?.source_message_ids);
    if (!title || !overview || !Array.isArray(viewpoints) || !uncertainty || evidence === null) return { kind: "empty" };
    const projectedViewpoints: V11TopicPresentation["viewpoints"] = [];
    let valid = true;
    for (const item of viewpoints) {
      const viewpoint = record(item);
      const authorDisplay = requiredString(viewpoint?.author_display);
      const statement = requiredString(viewpoint?.viewpoint);
      const reasoning = nullableString(viewpoint?.reasoning);
      const tendency = nullableString(viewpoint?.operation_tendency);
      const viewpointEvidence = countEvidence(viewpoint?.source_message_ids);
      if (!viewpoint || !hasExactKeys(viewpoint, ["author_id", "author_display", "viewpoint", "reasoning", "operation_tendency", "source_message_ids"]) || !authorDisplay || !statement || reasoning === undefined || tendency === undefined || viewpointEvidence === null) { valid = false; break; }
      projectedViewpoints.push({ authorDisplay, viewpoint: statement, reasoning, tendency, evidenceCount: viewpointEvidence });
    }
    if (!valid) return { kind: "empty" };
    topicDiscussions.push({ title, overview, viewpoints: projectedViewpoints, uncertainty, evidenceCount: evidence });
  }
  return { kind: "v1.1", asOf, authorCards, topicDiscussions, warnings };
}

export function presentSummary(output: unknown, coverage: unknown): SummaryPresentation {
  const summary = record(output);
  if (!summary) return { kind: "empty" };
  if (summary.schema_version === "v1.1") return presentV11(summary, coverage);
  if (summary.schema_version === "v1.1-batch") {
    const daily = record(summary.daily_summary);
    return daily?.schema_version === "v1.1" ? presentV11(daily, coverage) : { kind: "empty" };
  }
  if (Object.hasOwn(summary, "schema_version")) return { kind: "empty" };
  return presentLegacy(summary, coverage);
}
