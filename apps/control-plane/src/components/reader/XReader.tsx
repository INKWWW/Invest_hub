"use client";

import { useEffect, useMemo, useState } from "react";

import type { ReaderJudgement, XReaderBlogger, XReaderDate, XReaderJudgementRevision } from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";

const ALL = "all";

function sources(days: XReaderDate[]) {
  return [...new Map(days.flatMap((day) => day.bloggers.map((blogger) => [blogger.source.sourceKey, blogger.source]))).values()];
}

function dates(days: XReaderDate[]) {
  return [...new Set(days.map((day) => day.naturalDate))];
}

function validOrAll(value: string | undefined, values: string[]) {
  return value && values.includes(value) ? value : ALL;
}

function JudgementList({ batches }: { batches: XReaderDate["judgement"]["batches"] }) {
  if (!batches.length) return <p className="summary-empty">本时段没有形成新的跨博主判断。</p>;
  return <div className="x-reader-judgements">{batches.map((batch, index) => <details className="x-reader-judgement" key={batch.cutoffAt} open={index === 0}>
    <summary>截止 {new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(batch.cutoffAt))} · {batch.status === "succeeded" ? batch.coverageStatus === "partial" && batch.timedOutSourceCount > 0 && !batch.stockViewpoints.length && !batch.marketIndustryViewpoints.length ? "采集超时，未形成判断" : "已更新" : batch.status === "judgement_pending" ? "判断处理中" : "判断失败"}</summary>
    {batch.status === "succeeded" ? <div className="reader-section">
      <p>输入覆盖：{batch.includedSourceCount} 位博主观点已纳入，{batch.noNewSourceCount} 位无新增信息，{batch.excludedSourceCount} 位未纳入。下方主题仅列出直接支持或反对该主题的博主。</p>
      <JudgementRevision revision={batch} excludedSourceCount={batch.excludedSourceCount} timedOutSourceCount={batch.timedOutSourceCount} />
      {batch.revisionHistory.map((revision) => <details className="x-reader-revision" key={revision.revision}>
        <summary>修订版本 {revision.revision}</summary>
        <JudgementRevision revision={revision} excludedSourceCount={batch.excludedSourceCount} timedOutSourceCount={batch.timedOutSourceCount} />
      </details>)}
    </div> : <p className="summary-empty">{batch.status === "judgement_pending" ? "当日判断仍在处理中。" : "当日判断未能完成，稍后会重试。"}</p>}
  </details>)}</div>;
}

function JudgementRevision({ revision, excludedSourceCount, timedOutSourceCount }: {
  revision: Omit<XReaderJudgementRevision, "coverageStatus"> & {
    coverageStatus: XReaderJudgementRevision["coverageStatus"] | null;
  };
  excludedSourceCount: number;
  timedOutSourceCount: number;
}) {
  return <div className="x-reader-revision-content">
    {revision.stockViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`stock-${judgementIndex}`} judgement={judgement} />)}
    {revision.marketIndustryViewpoints.map((judgement, judgementIndex) => <JudgementCard key={`market-${judgementIndex}`} judgement={judgement} />)}
    {!revision.stockViewpoints.length && !revision.marketIndustryViewpoints.length ? <p className="summary-empty">本窗口没有形成新的跨博主判断。</p> : null}
    {revision.coverageStatus === "partial" ? <p className="topic-uncertainty">本次判断未纳入 {excludedSourceCount} 位博主的完整信息。{timedOutSourceCount > 0 ? `其中 ${timedOutSourceCount} 位因采集未在结算截止前完成。` : ""}</p> : null}
    {revision.coverageStatus === "no_new_information" ? <p className="summary-empty">本窗口没有新的可判断信息。</p> : null}
    {revision.uncertainties.length ? <p className="topic-uncertainty">不确定性：{revision.uncertainties.join("；")}</p> : null}
  </div>;
}

function JudgementCard({ judgement }: { judgement: ReaderJudgement }) {
  return <section className="topic-card"><p>{judgement.statement}</p>
    {judgement.supportingDisplayNames.length ? <p>支持观点：{judgement.supportingDisplayNames.join("、")}</p> : null}
    {judgement.dissentingDisplayNames.length ? <p>不同观点：{judgement.dissentingDisplayNames.join("、")}</p> : null}
    {judgement.uncertainties.length ? <p className="topic-uncertainty">不确定性：{judgement.uncertainties.join("；")}</p> : null}
  </section>;
}

function XReaderBloggerCard({ blogger }: { blogger: XReaderBlogger }) {
  return <section className="x-reader-blogger">
    <header className="x-reader-author-strip"><p>博主</p><h3 className="x-reader-author">{blogger.source.displayName}</h3></header>
    {blogger.timedOut ? <div className="reader-status" data-status="partial_failure"><p role="status">采集超时：本机未在结算时间前完成采集。</p></div> : <ReaderStatus status={blogger.status} asOf={blogger.segments[0]?.occurredThroughAt} />}
    {!blogger.segments.length ? <p className="summary-empty">{blogger.timedOut ? "本批次未纳入该博主的完整信息。" : blogger.status === "partial_failure" ? "本批次未纳入该博主的完整信息。" : "本批次没有可展示的博主观点。"}</p> : null}
    {blogger.segments.map((segment, index) => <details className="x-reader-segment" key={segment.occurredThroughAt} open={index === 0}>
      <summary>截止 {new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(segment.occurredThroughAt))} · 博主观点</summary>
      {segment.viewpoints.length ? <ul className="x-viewpoints">{segment.viewpoints.map((viewpoint, viewpointIndex) => <li key={viewpointIndex}>{viewpoint}</li>)}</ul> : <p className="summary-empty">本窗口没有形成新的博主观点。</p>}
      {segment.uncertainties.length ? <p className="topic-uncertainty">不确定性：{segment.uncertainties.join("；")}</p> : null}
      {segment.analyses.map((analysis, analysisIndex) => <article className="x-analysis" key={analysisIndex}>
        <p><a href={analysis.postLink} target="_blank" rel="noreferrer">原始 X 帖子</a></p>
        <p><strong>博主观点：</strong>{analysis.bloggerViewpoint ?? "未表达（例如普通 repost）"}</p>
        {analysis.arguments.length ? <p><strong>论据：</strong>{analysis.arguments.join("；")}</p> : null}
        {analysis.quotedPostViewpoint ? <p><strong>引用帖观点：</strong>{analysis.quotedPostViewpoint}</p> : null}
        {analysis.uncertainties.length ? <p className="topic-uncertainty">不确定性：{analysis.uncertainties.join("；")}</p> : null}
      </article>)}
    </details>)}
  </section>;
}

function XReaderDateCard({ day, sourceKey }: { day: XReaderDate; sourceKey: string }) {
  const bloggers = sourceKey === ALL ? day.bloggers : day.bloggers.filter((blogger) => blogger.source.sourceKey === sourceKey);
  return <section className="reader-day-card">
    <header><h2 className="x-reader-date"><span>日期</span>{day.naturalDate}</h2></header>
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
    const availableDates = dates(days);
    if (initialNaturalDate && initialNaturalDate !== ALL && !availableDates.includes(initialNaturalDate)) return [initialNaturalDate, ...availableDates];
    return availableDates;
  }, [days, initialNaturalDate]);
  const [sourceKey, setSourceKey] = useState(() => validOrAll(initialSourceKey, sourceOptions.map((source) => source.sourceKey)));
  const [naturalDate, setNaturalDate] = useState(() => validOrAll(initialNaturalDate, dateOptions));
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
