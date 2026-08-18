"use client";

import { useEffect, useMemo, useState, type ReactElement, type ReactNode } from "react";

import type { ReaderJudgement, XReaderBlogger, XReaderDate, XReaderJudgementRevision } from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";

const ALL = "all";
const ACTION_INTENT_LABELS = {
  build_position: "建仓", buy: "买入", add: "加仓", hold: "持有",
  reduce: "减仓", sell: "卖出", watch: "观望", avoid: "回避",
} as const;

function sources(days: XReaderDate[]) {
  return [...new Map(days.flatMap((day) => day.bloggers.map((blogger) => [blogger.source.sourceKey, blogger.source]))).values()];
}

function dates(days: XReaderDate[]) {
  return [...new Set(days.map((day) => day.naturalDate))];
}

function validOrAll(value: string | undefined, values: string[]) {
  return value && values.includes(value) ? value : ALL;
}

function initialDate(value: string | undefined, values: string[]) {
  if (value === ALL) return ALL;
  if (value && values.includes(value)) return value;
  return values[0] ?? ALL;
}

function currentRunText(status: NonNullable<XReaderDate["currentRun"]>["status"]) {
  if (status === "not_run") return "当前应运行窗口尚未运行。";
  if (status === "processing") return "当前应运行窗口处理中。";
  if (status === "failed") return "当前应运行窗口失败，未生成新的可读内容。";
  return "当前应运行窗口已完成。";
}

function cutoffLabel(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(date);
}

function JudgementList({ batches }: { batches: XReaderDate["judgement"]["batches"] }) {
  if (!batches.length) return <p className="summary-empty">本时段没有形成新的跨博主判断。</p>;
  return <div className="x-reader-judgements">{batches.flatMap((batch, index) => [<details className="x-reader-judgement" key={batch.cutoffAt} open={index === 0}>
    <summary>截止 {new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(batch.cutoffAt))} · {batch.status === "succeeded" ? batch.coverageStatus === "partial" && batch.timedOutSourceCount > 0 && !batch.stockViewpoints.length && !batch.marketIndustryViewpoints.length && !(batch.strategyMindsetViewpoints?.length) ? "采集超时，未形成判断" : "已更新" : batch.status === "judgement_pending" ? "判断处理中" : "判断失败"}</summary>
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
      <JudgementRevision revision={{ revision: 1, coverageStatus: null, ...batch.verificationRecovery }} excludedSourceCount={0} timedOutSourceCount={0} />
    </div>
  </details> : null].filter((item): item is ReactElement => item !== null))}</div>;
}

function JudgementRevision({ revision, excludedSourceCount, timedOutSourceCount }: {
  revision: Omit<XReaderJudgementRevision, "coverageStatus"> & {
    coverageStatus: XReaderJudgementRevision["coverageStatus"] | null;
  };
  excludedSourceCount: number;
  timedOutSourceCount: number;
}) {
  return <div className="x-reader-revision-content">
    {revision.stockViewpoints.length ? <ViewpointModule title="个股与产业判断" tone="security"><div className="x-reader-viewpoint-list">{revision.stockViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`stock-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
    {revision.marketIndustryViewpoints.length ? <ViewpointModule title="市场结构判断" tone="market"><div className="x-reader-viewpoint-list">{revision.marketIndustryViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`market-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
    {revision.strategyMindsetViewpoints?.length ? <ViewpointModule title="投资策略与心态" tone="strategy"><div className="x-reader-viewpoint-list">{revision.strategyMindsetViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`strategy-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
    {!revision.stockViewpoints.length && !revision.marketIndustryViewpoints.length && !(revision.strategyMindsetViewpoints?.length) ? <p className="summary-empty">本窗口没有形成新的跨博主判断。</p> : null}
    {revision.coverageStatus === "partial" ? <p className="topic-uncertainty">本次判断未纳入 {excludedSourceCount} 位博主的完整信息。{timedOutSourceCount > 0 ? `其中 ${timedOutSourceCount} 位因采集未在结算截止前完成。` : ""}</p> : null}
    {revision.coverageStatus === "no_new_information" ? <p className="summary-empty">本窗口没有新的可判断信息。</p> : null}
    {revision.uncertainties.length ? <p className="topic-uncertainty">不确定性：{revision.uncertainties.join("；")}</p> : null}
  </div>;
}

function actionText(judgement: ReaderJudgement) {
  if (!judgement.actionIntent) return null;
  return judgement.actionScopeStatus === "unspecified" ? `操作表述：${ACTION_INTENT_LABELS[judgement.actionIntent]}；对象：未明确，不可据此执行` : `操作表述：${ACTION_INTENT_LABELS[judgement.actionIntent]}（${judgement.actionScope}）`;
}

function analysisActionText(analysis: XReaderBlogger["segments"][number]["analyses"][number]) {
  if (!analysis.actionIntent) return null;
  return analysis.actionScopeStatus === "unspecified" ? `操作表述：${ACTION_INTENT_LABELS[analysis.actionIntent]}；对象：未明确，不可据此执行` : `操作表述：${ACTION_INTENT_LABELS[analysis.actionIntent]}（${analysis.actionScope}）`;
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
    {blogger.timedOut ? <div className="reader-status" data-status="partial_failure"><p role="status">采集超时：本机未在结算时间前完成采集。</p></div> : <ReaderStatus status={blogger.status} asOf={blogger.segments[0]?.occurredThroughAt} />}
    {!blogger.segments.length ? <p className="summary-empty">{blogger.timedOut ? "本批次未纳入该博主的完整信息。" : blogger.status === "partial_failure" ? "本批次未纳入该博主的完整信息。" : "本批次没有可展示的博主观点。"}</p> : null}
    {blogger.segments.map((segment, index) => <details className="x-reader-segment" key={segment.occurredThroughAt} open={index === 0}>
      <summary>截止 {new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(segment.occurredThroughAt))} · 博主观点</summary>
      {segment.securityIndustryViewpoints?.length ? <ViewpointModule title="个股与产业观点" tone="security"><div className="x-reader-viewpoint-list">{segment.securityIndustryViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`security-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
      {segment.marketStructureViewpoints?.length ? <ViewpointModule title="市场结构观点" tone="market"><div className="x-reader-viewpoint-list">{segment.marketStructureViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`market-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
      {segment.strategyMindsetViewpoints?.length ? <ViewpointModule title="投资策略与心态" tone="strategy"><div className="x-reader-viewpoint-list">{segment.strategyMindsetViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`strategy-${judgementIndex}`} judgement={judgement} index={judgementIndex} />)}</div></ViewpointModule> : null}
      {segment.viewpoints.length ? <div className="x-reader-unlinked-viewpoints"><p className="x-reader-unlinked-viewpoints-label">未关联帖子的博主观点</p><ul className="x-viewpoints">{segment.viewpoints.map((viewpoint, viewpointIndex) => <li key={viewpointIndex}>{viewpoint}</li>)}</ul></div> : null}
      {!segment.viewpoints.length && !segment.analyses.length ? <p className="summary-empty">本窗口没有形成新的博主观点。</p> : null}
      {segment.uncertainties.length ? <p className="topic-uncertainty">不确定性：{segment.uncertainties.join("；")}</p> : null}
      {segment.analyses.map((analysis, analysisIndex) => <details className="x-analysis" key={analysisIndex}>
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
  return <section className="reader-day-card">
    <header><h2 className="x-reader-date"><span>日期</span>{day.naturalDate}</h2></header>
    {day.currentRun ? <div className={`reader-status reader-status--${day.currentRun.status}`}><p role="status">截止 {cutoffLabel(day.currentRun.cutoffAt)}：{currentRunText(day.currentRun.status)}</p></div> : null}
    <section className="x-reader-judgement-section"><h2>当日判断总结</h2>{sourceKey === ALL && day.judgement.visible ? <JudgementList batches={day.judgement.batches} /> : <p>跨博主当日判断总结仅在全部博主视图展示。</p>}</section>
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
    return dates(days);
  }, [days, initialNaturalDate]);
  const [sourceKey, setSourceKey] = useState(() => validOrAll(initialSourceKey, sourceOptions.map((source) => source.sourceKey)));
  const [naturalDate, setNaturalDate] = useState(() => initialDate(initialNaturalDate, dateOptions));
  const visibleDays = useMemo(() => days.filter((day) =>
    (naturalDate === ALL || day.naturalDate === naturalDate) && (sourceKey === ALL || day.bloggers.some((blogger) => blogger.source.sourceKey === sourceKey)),
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
