"use client";

import { useEffect, useMemo, useState, type ReactElement, type ReactNode } from "react";

import type {
  ReaderAiAssessment,
  ReaderAiSynthesis,
  ReaderCrossBloggerIntegration,
  ReaderJudgement,
  ReaderThesis,
  XReaderBlogger,
  XReaderDate,
  XReaderJudgementRevision,
} from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";

const ALL = "all";
const AI_SYNTHESIS_DISCLAIMER = "仅基于本批次已纳入的博主观点，不获取外部信息，不构成交易建议";
const ACTION_INTENT_LABELS = {
  build_position: "建仓", buy: "买入", add: "加仓", hold: "持有",
  reduce: "减仓", sell: "卖出", watch: "观望", avoid: "回避",
} as const;

function sources(days: XReaderDate[]) {
  return [...new Map(days.flatMap((day) => [
    ...day.bloggers.map((blogger) => [blogger.source.sourceKey, blogger.source] as const),
    ...(day.collectionGaps ?? []).map((notice) => [notice.source.sourceKey, notice.source] as const),
  ])).values()];
}

function dates(days: XReaderDate[]) {
  return [...new Set(days.map((day) => day.naturalDate))];
}

function formatShanghaiDateTime(value: string) {
  const parts = new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(new Date(value));
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? "";
  return `${part("month")}月${part("day")}日 ${part("hour")}:${part("minute")}`;
}

function formatShanghaiGap(gap: { startAt: string; endAt: string }) {
  const start = formatShanghaiDateTime(gap.startAt);
  const end = formatShanghaiDateTime(gap.endAt);
  return start.slice(0, 6) === end.slice(0, 6) ? `${start}–${end.slice(7)}` : `${start}–${end}`;
}

function CollectionGapNotice({ gaps }: { gaps: XReaderBlogger["collectionGaps"] | undefined }) {
  if (!gaps?.length) return null;
  return <div className="reader-status" data-status="partial_failure">
    {gaps.map((gap) => <p role="status" key={`${gap.startAt}:${gap.endAt}`}>采集缺失：{formatShanghaiGap(gap)}</p>)}
  </div>;
}

function DateCollectionGapNotice({ notices }: { notices: NonNullable<XReaderDate["collectionGaps"]> }) {
  if (!notices.length) return null;
  return <section className="x-reader-gap-only" aria-label="采集缺失">
    {notices.map((notice) => <div className="reader-status" data-status="partial_failure" key={notice.source.sourceKey}>
      <p className="x-reader-gap-source">{notice.source.displayName}</p>
      {notice.gaps.map((gap) => <p role="status" key={`${gap.startAt}:${gap.endAt}`}>采集缺失：{formatShanghaiGap(gap)}</p>)}
    </div>)}
  </section>;
}

function validOrAll(value: string | undefined, values: string[]) {
  return value && values.includes(value) ? value : ALL;
}

type JudgementRevisionView = Omit<XReaderJudgementRevision, "coverageStatus"> & {
  coverageStatus: XReaderJudgementRevision["coverageStatus"] | null;
};

function legacyViewpoints(revision: JudgementRevisionView) {
  return {
    stock: revision.stockViewpoints ?? [],
    market: revision.marketIndustryViewpoints ?? [],
    strategy: revision.strategyMindsetViewpoints ?? [],
  };
}

function v5Theses(revision: JudgementRevisionView) {
  return {
    security: revision.securityIndustryTheses ?? [],
    market: revision.marketStructureTheses ?? [],
    strategy: revision.strategyMindsetTheses ?? [],
  };
}

function hasAiSynthesisContent(synthesis: ReaderAiSynthesis | undefined) {
  return Boolean(synthesis?.crossBloggerIntegrations.length || synthesis?.aiAssessments.length);
}

function hasVisibleJudgementContent(revision: JudgementRevisionView) {
  if (revision.presentationKind === "v5") {
    const theses = v5Theses(revision);
    return hasAiSynthesisContent(revision.aiSynthesis)
      || theses.security.length > 0
      || theses.market.length > 0
      || theses.strategy.length > 0;
  }
  const viewpoints = legacyViewpoints(revision);
  return viewpoints.stock.length > 0 || viewpoints.market.length > 0 || viewpoints.strategy.length > 0;
}

function JudgementList({ batches }: { batches: XReaderDate["judgement"]["batches"] }) {
  if (!batches.length) return <p className="summary-empty">本时段没有形成新的跨博主判断。</p>;
  return <div className="x-reader-judgements">{batches.flatMap((batch, index) => [<details className="x-reader-judgement" key={batch.cutoffAt} open={index === 0}>
    <summary>截止 {new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(batch.cutoffAt))} · {batch.status === "succeeded" ? batch.coverageStatus === "partial" && batch.timedOutSourceCount > 0 && !hasVisibleJudgementContent(batch) ? "采集超时，未形成判断" : "已更新" : batch.status === "judgement_pending" ? "判断处理中" : "判断失败"}</summary>
    {batch.status === "succeeded" ? <div className="reader-section">
      <p>输入覆盖：{batch.includedSourceCount} 位博主观点已纳入，{batch.noNewSourceCount} 位无新增信息，{batch.excludedSourceCount} 位未纳入。下方主题仅列出直接支持或反对该主题的博主。</p>
      <JudgementRevision revision={batch} excludedSourceCount={batch.excludedSourceCount} timedOutSourceCount={batch.timedOutSourceCount} />
      {batch.revisionHistory.map((revision) => <details className="x-reader-revision" key={revision.revision}>
        <summary>修订版本 {revision.revision}</summary>
        <JudgementRevision revision={revision} excludedSourceCount={batch.excludedSourceCount} timedOutSourceCount={batch.timedOutSourceCount} />
      </details>)}
    </div> : <p className="summary-empty">{batch.status === "judgement_pending" ? "当日判断仍在处理中。" : "当日判断未能完成，已停止自动重试。"}</p>}
  </details>, batch.verificationRecovery ? <details className="x-reader-verification-recovery" key={`${batch.cutoffAt}-verification-recovery`}>
    <summary>验证恢复（非定时任务）</summary>
    <div className="reader-section"><p>基于该失败窗口已冻结的输入完成 v3 验证，不影响既有定时任务或原始失败记录。</p>
      <JudgementRevision revision={{
        revision: 1,
        coverageStatus: null,
        presentationKind: "legacy",
        stockViewpoints: batch.verificationRecovery.stockViewpoints,
        marketIndustryViewpoints: batch.verificationRecovery.marketIndustryViewpoints,
        strategyMindsetViewpoints: batch.verificationRecovery.strategyMindsetViewpoints ?? [],
        uncertainties: batch.verificationRecovery.uncertainties,
      }} excludedSourceCount={0} timedOutSourceCount={0} />
    </div>
  </details> : null].filter((item): item is ReactElement => item !== null))}</div>;
}

function JudgementRevision({ revision, excludedSourceCount, timedOutSourceCount }: {
  revision: JudgementRevisionView;
  excludedSourceCount: number;
  timedOutSourceCount: number;
}) {
  const viewpoints = legacyViewpoints(revision);
  const theses = v5Theses(revision);
  const batchCoverageNote = revision.coverageStatus === "partial"
    ? `本次判断未纳入 ${excludedSourceCount} 位博主的完整信息。${timedOutSourceCount > 0 ? `其中 ${timedOutSourceCount} 位因采集未在结算截止前完成。` : ""}`
    : null;
  const showBatchUncertainty = revision.presentationKind === "v5" && (Boolean(batchCoverageNote) || revision.uncertainties.length > 0);
  const hasV5Content = hasVisibleJudgementContent(revision);

  return <div className="x-reader-revision-content">
    {revision.presentationKind === "v5" ? <>
      <AiSynthesisSection synthesis={revision.aiSynthesis ?? { crossBloggerIntegrations: [], aiAssessments: [] }} />
      <ThesisModule title="个股与产业判断" tone="security" theses={theses.security} />
      <ThesisModule title="市场结构判断" tone="market" theses={theses.market} />
      <ThesisModule title="投资策略与心态" tone="strategy" theses={theses.strategy} />
      {!hasV5Content ? <p className="summary-empty">本窗口没有形成新的跨博主判断。</p> : null}
      {showBatchUncertainty ? <section className="x-reader-batch-uncertainty">
        <h3 className="x-reader-batch-heading">批次整体不确定性</h3>
        <div className="x-reader-batch-body">
          {batchCoverageNote ? <p className="topic-uncertainty">{batchCoverageNote}</p> : null}
          {revision.uncertainties.length ? <ul className="x-reader-batch-list">
            {revision.uncertainties.map((uncertainty, uncertaintyIndex) => <li key={uncertaintyIndex} className="topic-uncertainty">{uncertainty}</li>)}
          </ul> : null}
        </div>
      </section> : null}
    </> : <>
      {viewpoints.stock.length ? <ViewpointModule title="个股与产业判断" tone="security"><div className="x-reader-viewpoint-list">{viewpoints.stock.map((judgement, judgementIndex) => <JudgementCard key={`stock-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
      {viewpoints.market.length ? <ViewpointModule title="市场结构判断" tone="market"><div className="x-reader-viewpoint-list">{viewpoints.market.map((judgement, judgementIndex) => <JudgementCard key={`market-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
      {viewpoints.strategy.length ? <ViewpointModule title="投资策略与心态" tone="strategy"><div className="x-reader-viewpoint-list">{viewpoints.strategy.map((judgement, judgementIndex) => <JudgementCard key={`strategy-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
      {!viewpoints.stock.length && !viewpoints.market.length && !viewpoints.strategy.length ? <p className="summary-empty">本窗口没有形成新的跨博主判断。</p> : null}
      {batchCoverageNote ? <p className="topic-uncertainty">{batchCoverageNote}</p> : null}
      {revision.uncertainties.length ? <p className="topic-uncertainty">不确定性：{revision.uncertainties.join("；")}</p> : null}
    </>}
    {revision.coverageStatus === "no_new_information" ? <p className="summary-empty">本窗口没有新的可判断信息。</p> : null}
  </div>;
}

function formatActionText(action: {
  actionIntent?: ReaderJudgement["actionIntent"] | null;
  actionScopeStatus?: ReaderJudgement["actionScopeStatus"];
  actionScope?: ReaderJudgement["actionScope"];
}) {
  if (!action.actionIntent) return null;
  return action.actionScopeStatus === "unspecified"
    ? `操作表述：${ACTION_INTENT_LABELS[action.actionIntent]}；对象：未明确，不可据此执行`
    : `操作表述：${ACTION_INTENT_LABELS[action.actionIntent]}（${action.actionScope}）`;
}

function actionText(judgement: ReaderJudgement) {
  return formatActionText(judgement);
}

function analysisActionText(analysis: XReaderBlogger["segments"][number]["analyses"][number]) {
  return formatActionText(analysis);
}

const POST_TYPE_LABELS = { original: "原帖", quote: "引用帖", reply: "回复", repost: "转发" } as const;

function analysisLabel(analysis: XReaderBlogger["segments"][number]["analyses"][number]) {
  const postedAt = analysis.postedAt && !Number.isNaN(Date.parse(analysis.postedAt)) ? Object.fromEntries(new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(new Date(analysis.postedAt)).map(({ type, value }) => [type, value])) : null;
  const postedAtLabel = postedAt ? `${postedAt.month}-${postedAt.day} ${postedAt.hour}:${postedAt.minute}` : null;
  const postType = analysis.postType ? POST_TYPE_LABELS[analysis.postType] : null;
  return [postedAtLabel, postType].filter(Boolean).join(" · ") || "原始 X 帖子";
}

type ViewpointTone = "security" | "market" | "strategy";

function ViewpointModule({ title, tone, children }: { title: string; tone: ViewpointTone; children: ReactNode }) {
  return <section className={`x-reader-viewpoint-group x-reader-viewpoint-group--${tone}`}>
    <h3 className="x-reader-viewpoint-heading">{title}</h3>
    {children}
  </section>;
}

function AiSynthesisSection({ synthesis }: { synthesis: ReaderAiSynthesis }): ReactElement | null {
  if (!synthesis.crossBloggerIntegrations.length && !synthesis.aiAssessments.length) return null;
  return <section className="x-ai-synthesis">
    <header className="x-ai-synthesis-header">
      <h3 className="x-reader-viewpoint-heading">AI 综合研判</h3>
      <p className="x-ai-synthesis-disclaimer">{AI_SYNTHESIS_DISCLAIMER}</p>
    </header>
    <div className="x-ai-synthesis-body">
      {synthesis.crossBloggerIntegrations.length ? <section className="x-ai-module">
        <div className="x-ai-module-header">
          <h4>跨博主观点整合</h4>
          <span className="x-ai-source-badge">博主观点归纳</span>
        </div>
        <div className="x-ai-card-list">{synthesis.crossBloggerIntegrations.map((integration, index) => <CrossBloggerIntegrationCard key={index} integration={integration} index={index} />)}</div>
      </section> : null}
      {synthesis.aiAssessments.length ? <section className="x-ai-module">
        <div className="x-ai-module-header">
          <h4>AI 研判</h4>
          <span className="x-ai-model-badge">AI 分析判断</span>
        </div>
        <div className="x-ai-card-list">{synthesis.aiAssessments.map((assessment, index) => <AiAssessmentCard key={index} assessment={assessment} index={index} />)}</div>
      </section> : null}
    </div>
  </section>;
}

function CrossBloggerIntegrationCard({ integration, index }: { integration: ReaderCrossBloggerIntegration; index: number }): ReactElement {
  return <article data-testid="x-ai-integration-card" className="x-ai-integration-card">
    <p className="x-ai-card-number">整合 {String(index + 1).padStart(2, "0")}</p>
    <h5 className="x-ai-card-title">{integration.headline}</h5>
    <p className="x-ai-card-body">{integration.synthesis}</p>
    <div className="x-ai-info-grid">
      {integration.commonPoints.length ? <section data-testid="x-ai-common-points" className="x-ai-info-cell x-ai-info-cell--integration">
        <h6>共性归纳</h6>
        <ul className="x-ai-info-list">
          {integration.commonPoints.map((point, pointIndex) => <li key={pointIndex}>{point.statement}<span className="x-ai-inline-meta">博主：{point.displayNames.join("、")}</span></li>)}
        </ul>
      </section> : null}
      {integration.conflictPoints.length ? <section className="x-ai-info-cell x-ai-info-cell--integration">
        <h6>分歧与条件差异</h6>
        <ul className="x-ai-info-list">
          {integration.conflictPoints.map((conflict, conflictIndex) => <li key={conflictIndex}>
            <strong>{conflict.issue}</strong>
            <ul className="x-ai-nested-list">
              {conflict.positions.map((position, positionIndex) => <li data-testid="x-ai-conflict-position" key={positionIndex}>{position.position}<span className="x-ai-inline-meta">博主：{position.displayNames.join("、")}</span></li>)}
            </ul>
          </li>)}
        </ul>
      </section> : null}
      {integration.uncertainties.length ? <section className="x-ai-info-cell x-ai-info-cell--integration">
        <h6>整合不确定性</h6>
        <ul className="x-ai-info-list">
          {integration.uncertainties.map((uncertainty, uncertaintyIndex) => <li key={uncertaintyIndex}>{uncertainty}</li>)}
        </ul>
      </section> : null}
    </div>
  </article>;
}

function AiAssessmentCard({ assessment, index }: { assessment: ReaderAiAssessment; index: number }): ReactElement {
  return <article data-testid="x-ai-assessment-card" className="x-ai-assessment-card">
    <p className="x-ai-card-number">AI 研判 {String(index + 1).padStart(2, "0")}</p>
    <h5 className="x-ai-card-title">{assessment.headline}</h5>
    <p className="x-ai-card-body">{assessment.judgement}</p>
    <div className="x-ai-info-grid">
      <section className="x-ai-info-cell x-ai-info-cell--assessment">
        <h6>重要性理由</h6>
        <p>{assessment.importanceReason}</p>
      </section>
      <section className="x-ai-info-cell x-ai-info-cell--assessment">
        <h6>推理</h6>
        <p>{assessment.reasoning}</p>
      </section>
      {assessment.keyAssumptions.length ? <section className="x-ai-info-cell x-ai-info-cell--assessment">
        <h6>关键假设</h6>
        <ul className="x-ai-info-list">
          {assessment.keyAssumptions.map((assumption, assumptionIndex) => <li key={assumptionIndex}>{assumption}</li>)}
        </ul>
      </section> : null}
      {assessment.risks.length ? <section className="x-ai-info-cell x-ai-info-cell--assessment">
        <h6>风险</h6>
        <ul className="x-ai-info-list">
          {assessment.risks.map((risk, riskIndex) => <li key={riskIndex}>{risk}</li>)}
        </ul>
      </section> : null}
      {assessment.watchVariables.length ? <section className="x-ai-info-cell x-ai-info-cell--assessment">
        <h6>观察变量</h6>
        <ul className="x-ai-info-list">
          {assessment.watchVariables.map((watchVariable, watchVariableIndex) => <li key={watchVariableIndex}>{watchVariable}</li>)}
        </ul>
      </section> : null}
      {assessment.uncertainties.length ? <section className="x-ai-info-cell x-ai-info-cell--assessment">
        <h6>研判不确定性</h6>
        <ul className="x-ai-info-list">
          {assessment.uncertainties.map((uncertainty, uncertaintyIndex) => <li key={uncertaintyIndex}>{uncertainty}</li>)}
        </ul>
      </section> : null}
    </div>
  </article>;
}

function ThesisModule({ title, tone, theses }: { title: string; tone: ViewpointTone; theses: ReaderThesis[] }): ReactElement | null {
  if (!theses.length) return null;
  return <ViewpointModule title={title} tone={tone}>
    <div className="x-reader-viewpoint-list">{theses.map((thesis, index) => <ThesisCard key={`${title}-${index}`} thesis={thesis} index={index} />)}</div>
  </ViewpointModule>;
}

function ThesisCard({ thesis, index }: { thesis: ReaderThesis; index: number }): ReactElement {
  return <article data-testid="x-thesis-card" className="topic-card x-thesis-card">
    <p className="x-reader-viewpoint-number">判断主线 {String(index + 1).padStart(2, "0")}</p>
    <h4 className="x-thesis-headline">{thesis.headline}</h4>
    <p className="x-thesis-synthesis">{thesis.synthesis}</p>
    {thesis.scenarioBranches.length ? <section data-testid="x-thesis-scenario" className="x-thesis-subsection">
      <p className="x-thesis-subheading">情景分支</p>
      <ul className="x-thesis-sublist">
        {thesis.scenarioBranches.map((branch, branchIndex) => <li key={branchIndex}>
          <strong>情景 {String.fromCharCode(65 + branchIndex)}</strong>
          <p>条件：{branch.condition}</p>
          <p>结果：{branch.outcome}</p>
          {branch.uncertainties.length ? <p className="topic-uncertainty">不确定性：{branch.uncertainties.join("；")}</p> : null}
        </li>)}
      </ul>
    </section> : null}
    {thesis.attributedActions.length ? <section data-testid="x-thesis-actions" className="x-thesis-subsection">
      <p className="x-thesis-subheading">博主操作归因</p>
      <ul className="x-thesis-sublist">
        {thesis.attributedActions.map((action, actionIndex) => <li key={actionIndex}>
          <p><strong>{action.displayName}</strong>：{formatActionText(action)}</p>
          {action.conditions.length ? <p>条件：{action.conditions.join("；")}</p> : null}
          {action.uncertainties.length ? <p className="topic-uncertainty">不确定性：{action.uncertainties.join("；")}</p> : null}
        </li>)}
      </ul>
    </section> : null}
    {thesis.supportingDisplayNames.length ? <p>支持观点：{thesis.supportingDisplayNames.join("、")}</p> : null}
    {thesis.dissentingDisplayNames.length ? <p>不同观点：{thesis.dissentingDisplayNames.join("、")}</p> : null}
    {thesis.uncertainties.length ? <p className="topic-uncertainty">不确定性：{thesis.uncertainties.join("；")}</p> : null}
  </article>;
}

function JudgementCard({ judgement, index }: { judgement: ReaderJudgement; index: number }) {
  return <article className="topic-card"><p className="x-reader-viewpoint-number">观点 {String(index + 1).padStart(2, "0")}</p><p className="x-reader-viewpoint-statement">{judgement.statement}</p>
    {actionText(judgement) ? <p>{actionText(judgement)}</p> : null}
    {judgement.conditions?.length ? <p>条件：{judgement.conditions.join("；")}</p> : null}
    {judgement.supportingDisplayNames.length ? <p>支持观点：{judgement.supportingDisplayNames.join("、")}</p> : null}
    {judgement.dissentingDisplayNames.length ? <p>不同观点：{judgement.dissentingDisplayNames.join("、")}</p> : null}
    {judgement.uncertainties.length ? <p className="topic-uncertainty">不确定性：{judgement.uncertainties.join("；")}</p> : null}
  </article>;
}

function XReaderBloggerCard({ blogger }: { blogger: XReaderBlogger }) {
  return <section className="x-reader-blogger">
    <header className="x-reader-author-strip"><p>博主</p><h3 className="x-reader-author">{blogger.source.displayName}</h3></header>
    <CollectionGapNotice gaps={blogger.collectionGaps} />
    {blogger.lateArrival ? <div className="reader-status" data-status="late_arrival">
      <p role="status">后补采集：该内容在当日判断结算后完成采集，未纳入原跨博主日报。</p>
    </div> : null}
    {blogger.timedOut ? <div className="reader-status" data-status="partial_failure"><p role="status">采集超时：本机未在结算时间前完成采集。</p></div> : <ReaderStatus status={blogger.status} asOf={blogger.segments[0]?.occurredThroughAt} />}
    {!blogger.segments.length ? <p className="summary-empty">{blogger.timedOut ? "本批次未纳入该博主的完整信息。" : blogger.status === "partial_failure" ? "本批次未纳入该博主的完整信息。" : "本批次没有可展示的博主观点。"}</p> : null}
    {blogger.segments.map((segment, index) => <details className="x-reader-segment" key={segment.occurredThroughAt} open={index === 0}>
      <summary>截止 {new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(segment.occurredThroughAt))} · 博主观点</summary>
      {segment.viewpoints.length ? <div className="x-reader-unlinked-viewpoints"><p className="x-reader-unlinked-viewpoints-label">未关联帖子的博主观点</p><ul className="x-viewpoints">{segment.viewpoints.map((viewpoint, viewpointIndex) => <li key={viewpointIndex}>{viewpoint}</li>)}</ul></div> : null}
      {!segment.viewpoints.length && !segment.analyses.length ? <p className="summary-empty">本窗口没有形成新的博主观点。</p> : null}
      {segment.uncertainties.length ? <p className="topic-uncertainty">不确定性：{segment.uncertainties.join("；")}</p> : null}
      {segment.analyses.map((analysis, analysisIndex) => <details className="x-analysis" key={analysisIndex} open>
        <summary><a href={analysis.postLink} target="_blank" rel="noreferrer">{analysisLabel(analysis)}</a></summary>
        <div className="x-analysis-body">
          <p><strong>博主观点：</strong>{analysis.bloggerViewpoint ?? "未表达（例如普通 repost）"}</p>
          {analysisActionText(analysis) ? <p><strong>操作表述：</strong>{analysisActionText(analysis)?.replace(/^操作表述：/, "")}</p> : null}
          {analysis.conditions?.length ? <p><strong>条件：</strong>{analysis.conditions.join("；")}</p> : null}
          {analysis.arguments.length ? <p><strong>论据：</strong>{analysis.arguments.join("；")}</p> : null}
          {analysis.quotedPostViewpoint ? <p><strong>引用帖观点：</strong>{analysis.quotedPostViewpoint}</p> : null}
          {analysis.uncertainties.length ? <p className="topic-uncertainty">不确定性：{analysis.uncertainties.join("；")}</p> : null}
        </div>
      </details>)}
    </details>)}
  </section>;
}

function XReaderDateCard({ day, sourceKey }: { day: XReaderDate; sourceKey: string }) {
  const bloggers = sourceKey === ALL ? day.bloggers : day.bloggers.filter((blogger) => blogger.source.sourceKey === sourceKey);
  const collectionGaps = sourceKey === ALL ? (day.collectionGaps ?? []) : (day.collectionGaps ?? []).filter((notice) => notice.source.sourceKey === sourceKey);
  return <section className="reader-day-card">
    <header><h2 className="x-reader-date"><span>日期</span>{day.naturalDate}</h2></header>
    <section className="x-reader-judgement-section"><h2>当日判断总结</h2>{sourceKey === ALL && day.judgement.visible ? <JudgementList batches={day.judgement.batches} /> : <p>跨博主当日判断总结仅在全部博主视图展示。</p>}</section>
    <DateCollectionGapNotice notices={collectionGaps} />
    <section className="x-reader-bloggers"><h2>单个博主观点</h2>{bloggers.map((blogger) => <XReaderBloggerCard key={blogger.source.sourceKey} blogger={blogger} />)}</section>
  </section>;
}

export function XReader({ days, initialSourceKey, initialNaturalDate }: {
  days: XReaderDate[];
  initialSourceKey?: string;
  initialNaturalDate?: string;
}) {
  if (!days.length) return <p>尚无可阅读的 X 信息。</p>;
  const sourceOptions = useMemo(() => sources(days), [days]);
  const dateOptions = useMemo(() => {
    const availableDates = dates(days);
    if (initialNaturalDate && initialNaturalDate !== ALL && !availableDates.includes(initialNaturalDate)) return [initialNaturalDate, ...availableDates];
    return availableDates;
  }, [days, initialNaturalDate]);
  const [sourceKey, setSourceKey] = useState(() => validOrAll(initialSourceKey, sourceOptions.map((source) => source.sourceKey)));
  const [naturalDate, setNaturalDate] = useState(() => validOrAll(initialNaturalDate, dateOptions));
  const visibleDays = useMemo(() => days.filter((day) =>
    (naturalDate === ALL || day.naturalDate === naturalDate) && (sourceKey === ALL || day.bloggers.some((blogger) => blogger.source.sourceKey === sourceKey) || (day.collectionGaps ?? []).some((notice) => notice.source.sourceKey === sourceKey)),
  ), [days, naturalDate, sourceKey]);

  useEffect(() => {
    const searchParams = new URLSearchParams(window.location.search);
    if (sourceKey === ALL) searchParams.delete("source"); else searchParams.set("source", sourceKey);
    searchParams.delete("date");
    const query = searchParams.toString();
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash}`);
  }, [sourceKey]);

  return <section className="reader-shell">
    <aside className="reader-sidebar" aria-label="X 内容筛选">
      <label>博主
        <select value={sourceKey} onChange={(event) => setSourceKey(event.target.value)}>
          <option value={ALL}>全部</option>
          {sourceOptions.map((source) => <option key={source.sourceKey} value={source.sourceKey}>{source.displayName}</option>)}
        </select>
      </label>
      <label>日期
        <select value={naturalDate} onChange={(event) => setNaturalDate(event.target.value)}>
          <option value={ALL}>全部</option>
          {dateOptions.map((date) => <option key={date} value={date}>{date}</option>)}
        </select>
      </label>
    </aside>
    <article className="reader-content">
      {visibleDays.length ? <div className="reader-result-list">{visibleDays.map((day) => <XReaderDateCard key={day.naturalDate} day={day} sourceKey={sourceKey} />)}</div> : <p className="summary-empty">没有找到符合当前博主和日期筛选的 X 信息。</p>}
    </article>
  </section>;
}
