export type PresentedTopic = {
  title: string;
  summary: string;
  sourceMessageIds: string[];
  authorScope: "target" | "channel" | null;
  tickers: string[];
  operationTendency: string | null;
  uncertainty: string | null;
};

export type SummaryPresentation = {
  topics: PresentedTopic[];
  warnings: string[];
  mediaUnparsed: boolean;
};

type JsonRecord = Record<string, unknown>;

function record(value: unknown): JsonRecord | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  return Object.fromEntries(Object.entries(value));
}

function strings(value: unknown): string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string") ? value : [];
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function topic(value: unknown): PresentedTopic | null {
  const input = record(value);
  if (!input || typeof input.title !== "string" || typeof input.summary !== "string") return null;
  const authorScope = input.author_scope === "target" || input.author_scope === "channel" ? input.author_scope : null;
  return {
    title: input.title,
    summary: input.summary,
    sourceMessageIds: strings(input.source_message_ids),
    authorScope,
    tickers: strings(input.tickers),
    operationTendency: optionalString(input.operation_tendency),
    uncertainty: optionalString(input.uncertainty),
  };
}

export function evidenceCount(value: unknown): number {
  return strings(value).length;
}

export function presentSummary(output: unknown, coverage: unknown): SummaryPresentation {
  const summary = record(output);
  if (!summary || !Array.isArray(summary.topics) || !Array.isArray(summary.warnings)) {
    return { topics: [], warnings: [], mediaUnparsed: false };
  }
  const summaryCoverage = record(coverage);
  return {
    topics: summary.topics.flatMap((value) => {
      const valueTopic = topic(value);
      return valueTopic ? [valueTopic] : [];
    }),
    warnings: strings(summary.warnings),
    mediaUnparsed: summaryCoverage?.unparsed_media === true,
  };
}
