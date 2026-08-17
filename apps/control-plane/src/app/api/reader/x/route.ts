import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../lib/auth/current-user";
import {
  readXDay,
  type ReaderAiAssessment,
  type ReaderCrossBloggerIntegration,
  type ReaderJudgement,
  type ReaderThesis,
  type XReaderDate,
} from "../../../../lib/db/repositories/reader";
import { isValidReaderNaturalDate } from "../../../../lib/reader-date";

function readerFilter(value: string | null) {
  return value && value !== "all" ? value : undefined;
}

function readerSafeCoverageStatus(value: unknown, revision: number) {
  if (revision < 1) return null;
  return value === "complete" || value === "partial" || value === "no_new_information" ? value : null;
}

type ReaderRecord = Record<string, unknown>;

function readerRecord(value: unknown): ReaderRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as ReaderRecord : null;
}

function readerString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function readerNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function readerStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function readerSafeRecords(value: unknown): ReaderRecord[] {
  return Array.isArray(value) ? value.map(readerRecord).filter((item): item is ReaderRecord => item !== null) : [];
}

const readerActionIntents = new Set([
  "build_position",
  "buy",
  "add",
  "hold",
  "reduce",
  "sell",
  "watch",
  "avoid",
]);

function readerSafeActionIntent(value: unknown): NonNullable<ReaderJudgement["actionIntent"]> | null {
  if (value === null || value === undefined) return null;
  return typeof value === "string" && readerActionIntents.has(value) ? value as NonNullable<ReaderJudgement["actionIntent"]> : null;
}

function readerSafeActionScopeStatus(value: unknown): NonNullable<ReaderJudgement["actionScopeStatus"]> | null {
  return value === "specified" || value === "unspecified" ? value : null;
}

function readerSafeJudgement(value: unknown): ReaderJudgement | null {
  const viewpoint = readerRecord(value);
  const statement = readerString(viewpoint?.statement);
  if (!viewpoint || statement === null) return null;
  return {
    statement,
    actionIntent: readerSafeActionIntent(viewpoint.actionIntent),
    actionScope: readerString(viewpoint.actionScope) ?? "",
    actionScopeStatus: readerSafeActionScopeStatus(viewpoint.actionScopeStatus),
    conditions: readerStringArray(viewpoint.conditions),
    supportingDisplayNames: readerStringArray(viewpoint.supportingDisplayNames),
    dissentingDisplayNames: readerStringArray(viewpoint.dissentingDisplayNames),
    uncertainties: readerStringArray(viewpoint.uncertainties),
  };
}

function readerSafeJudgements(value: unknown): ReaderJudgement[] {
  return readerSafeRecords(value)
    .map(readerSafeJudgement)
    .filter((item): item is ReaderJudgement => item !== null);
}

function readerSafeScenarioBranch(value: unknown) {
  const branch = readerRecord(value);
  const condition = readerString(branch?.condition);
  const outcome = readerString(branch?.outcome);
  if (!branch || condition === null || outcome === null) return null;
  return {
    condition,
    outcome,
    uncertainties: readerStringArray(branch.uncertainties),
  };
}

function readerSafeAttributedAction(value: unknown) {
  const action = readerRecord(value);
  const displayName = readerString(action?.displayName);
  const actionIntent = readerSafeActionIntent(action?.actionIntent);
  const actionScope = readerString(action?.actionScope);
  const actionScopeStatus = readerSafeActionScopeStatus(action?.actionScopeStatus);
  if (!action || displayName === null || actionIntent === null || actionScope === null || actionScopeStatus === null) return null;
  return {
    displayName,
    actionIntent,
    actionScope,
    actionScopeStatus,
    conditions: readerStringArray(action.conditions),
    uncertainties: readerStringArray(action.uncertainties),
  };
}

function readerSafeThesis(value: unknown): ReaderThesis | null {
  const thesis = readerRecord(value);
  const headline = readerString(thesis?.headline);
  const synthesis = readerString(thesis?.synthesis);
  if (!thesis || headline === null || synthesis === null) return null;
  return {
    headline,
    synthesis,
    scenarioBranches: readerSafeRecords(thesis.scenarioBranches)
      .map(readerSafeScenarioBranch)
      .filter((item): item is NonNullable<typeof item> => item !== null),
    attributedActions: readerSafeRecords(thesis.attributedActions)
      .map(readerSafeAttributedAction)
      .filter((item): item is NonNullable<typeof item> => item !== null),
    supportingDisplayNames: readerStringArray(thesis.supportingDisplayNames),
    dissentingDisplayNames: readerStringArray(thesis.dissentingDisplayNames),
    uncertainties: readerStringArray(thesis.uncertainties),
  };
}

function readerSafeTheses(value: unknown): ReaderThesis[] {
  return readerSafeRecords(value)
    .map(readerSafeThesis)
    .filter((item): item is ReaderThesis => item !== null);
}

function readerSafeCommonPoint(value: unknown) {
  const point = readerRecord(value);
  const statement = readerString(point?.statement);
  if (!point || statement === null) return null;
  return { statement, displayNames: readerStringArray(point.displayNames) };
}

function readerSafePosition(value: unknown) {
  const position = readerRecord(value);
  const text = readerString(position?.position);
  if (!position || text === null) return null;
  return { position: text, displayNames: readerStringArray(position.displayNames) };
}

function readerSafeConflictPoint(value: unknown) {
  const point = readerRecord(value);
  const issue = readerString(point?.issue);
  if (!point || issue === null) return null;
  return {
    issue,
    positions: readerSafeRecords(point.positions)
      .map(readerSafePosition)
      .filter((item): item is NonNullable<typeof item> => item !== null),
  };
}

function readerSafeIntegration(value: unknown): ReaderCrossBloggerIntegration | null {
  const integration = readerRecord(value);
  const headline = readerString(integration?.headline);
  const synthesis = readerString(integration?.synthesis);
  if (!integration || headline === null || synthesis === null) return null;
  return {
    headline,
    synthesis,
    commonPoints: readerSafeRecords(integration.commonPoints)
      .map(readerSafeCommonPoint)
      .filter((item): item is NonNullable<typeof item> => item !== null),
    conflictPoints: readerSafeRecords(integration.conflictPoints)
      .map(readerSafeConflictPoint)
      .filter((item): item is NonNullable<typeof item> => item !== null),
    uncertainties: readerStringArray(integration.uncertainties),
  };
}

function readerSafeAssessment(value: unknown): ReaderAiAssessment | null {
  const assessment = readerRecord(value);
  const headline = readerString(assessment?.headline);
  const judgement = readerString(assessment?.judgement);
  const importanceReason = readerString(assessment?.importanceReason);
  const reasoning = readerString(assessment?.reasoning);
  if (!assessment || headline === null || judgement === null || importanceReason === null || reasoning === null) return null;
  return {
    headline,
    judgement,
    importanceReason,
    reasoning,
    keyAssumptions: readerStringArray(assessment.keyAssumptions),
    risks: readerStringArray(assessment.risks),
    watchVariables: readerStringArray(assessment.watchVariables),
    uncertainties: readerStringArray(assessment.uncertainties),
  };
}

function readerSafeAiSynthesis(value: unknown) {
  const synthesis = readerRecord(value);
  if (!synthesis) return undefined;
  return {
    crossBloggerIntegrations: readerSafeRecords(synthesis.crossBloggerIntegrations)
      .map(readerSafeIntegration)
      .filter((item): item is ReaderCrossBloggerIntegration => item !== null),
    aiAssessments: readerSafeRecords(synthesis.aiAssessments)
      .map(readerSafeAssessment)
      .filter((item): item is ReaderAiAssessment => item !== null),
  };
}

function readerSafeV5Fields(value: unknown) {
  const revision = readerRecord(value);
  if (revision?.presentationKind !== "v5") return { presentationKind: "legacy" as const };
  return {
    presentationKind: "v5" as const,
    aiSynthesis: readerSafeAiSynthesis(revision?.aiSynthesis),
    securityIndustryTheses: readerSafeTheses(revision?.securityIndustryTheses),
    marketStructureTheses: readerSafeTheses(revision?.marketStructureTheses),
    strategyMindsetTheses: readerSafeTheses(revision?.strategyMindsetTheses),
  };
}

function readerSafeRevision(value: unknown) {
  const revision = readerRecord(value);
  const revisionNumber = readerNumber(revision?.revision) ?? 0;
  return {
    revision: revisionNumber,
    coverageStatus: readerSafeCoverageStatus(revision?.coverageStatus, revisionNumber),
    ...readerSafeV5Fields(revision),
    stockViewpoints: readerSafeJudgements(revision?.stockViewpoints),
    marketIndustryViewpoints: readerSafeJudgements(revision?.marketIndustryViewpoints),
    strategyMindsetViewpoints: readerSafeJudgements(revision?.strategyMindsetViewpoints),
    uncertainties: readerStringArray(revision?.uncertainties),
  };
}

/** Runtime JSON boundary: even a future repository DTO regression cannot expose internal fields. */
function readerSafeXDays(days: XReaderDate[]) {
  return days.map((day) => ({
    naturalDate: day.naturalDate,
    judgement: {
      visible: day.judgement.visible,
      batches: day.judgement.batches.map((batch) => ({
        ...readerSafeRevision(batch),
        cutoffAt: readerString(batch.cutoffAt) ?? "",
        status: batch.status === "succeeded" || batch.status === "judgement_pending" || batch.status === "judgement_failed" ? batch.status : "judgement_failed",
        excludedSourceCount: readerNumber(batch.excludedSourceCount) ?? 0,
        revisionHistory: (batch.revisionHistory ?? []).map((revision) => ({
          ...readerSafeRevision(revision),
        })),
      })),
    },
    bloggers: day.bloggers.map((blogger) => ({
      source: { sourceKey: blogger.source.sourceKey, displayName: blogger.source.displayName },
      status: blogger.status,
      segments: blogger.segments.map((segment) => ({
        occurredFromAt: segment.occurredFromAt,
        occurredThroughAt: segment.occurredThroughAt,
        viewpoints: readerStringArray(segment.viewpoints),
        uncertainties: readerStringArray(segment.uncertainties),
        analyses: segment.analyses.map((analysis) => ({
          postLink: analysis.postLink,
          postedAt: analysis.postedAt ?? null,
          postType: analysis.postType ?? null,
          bloggerViewpoint: analysis.bloggerViewpoint,
          actionIntent: analysis.actionIntent ?? null,
          actionScope: analysis.actionScope ?? "",
          actionScopeStatus: analysis.actionScopeStatus ?? null,
          conditions: readerStringArray(analysis.conditions),
          arguments: readerStringArray(analysis.arguments),
          quotedPostViewpoint: analysis.quotedPostViewpoint,
          uncertainties: readerStringArray(analysis.uncertainties),
        })),
      })),
    })),
  }));
}

export async function GET(request: Request) {
  if (!await getCurrentUser()) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { searchParams } = new URL(request.url);
  const sourceKey = readerFilter(searchParams.get("source"));
  const date = readerFilter(searchParams.get("date"));
  if (date && !isValidReaderNaturalDate(date)) return NextResponse.json({ error: "invalid_reader_query" }, { status: 422 });
  try {
    return NextResponse.json({ status: "ok", days: readerSafeXDays(await readXDay({ sourceKey, date })) });
  } catch {
    return NextResponse.json({ error: "reader_unavailable" }, { status: 503 });
  }
}
