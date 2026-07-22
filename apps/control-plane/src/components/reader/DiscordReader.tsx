"use client";

import { useMemo, useState } from "react";

import type { ReaderDay } from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";
import type { SummaryPresentation } from "./reader-presentation";

export function readerSourceOptions(days: ReaderDay[]) {
  return [...new Map(days.map((day) => [day.source.sourceKey, day.source])).values()];
}

export function readerDateOptions(days: ReaderDay[], sourceKey: string) {
  return days.filter((day) => day.source.sourceKey === sourceKey).map((day) => day.naturalDate);
}

function asShanghaiTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "当前生成时间";
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(date);
}

function tendency(value: string | null): string {
  return value ?? "未表达";
}

function LegacyTopics({ presentation, emptyCopy }: { presentation: Extract<SummaryPresentation, { kind: "legacy" }>; emptyCopy: string }) {
  return presentation.topics.length > 0 ? <div className="summary-topics">
    {presentation.topics.map((topic, index) => <article className="topic-card" key={`${topic.title}-${index}`}>
      <h4>{topic.title}</h4>
      <p>{topic.summary}</p>
      {topic.tickers.length > 0 ? <p className="topic-tickers">{topic.tickers.join(" · ")}</p> : null}
      <p>操作倾向：{tendency(topic.operationTendency)}</p>
      {topic.uncertainty ? <p className="topic-uncertainty">不确定性：{topic.uncertainty}</p> : null}
      <p className="topic-evidence-count">{topic.evidenceCount} 条安全证据</p>
    </article>)}
    {presentation.warnings.length > 0 ? <p className="summary-note">{presentation.warnings.join("；")}</p> : null}
    {presentation.mediaUnparsed ? <p className="summary-media-boundary">图片、附件和外部文章正文未解析。</p> : null}
  </div> : <p className="summary-empty">{emptyCopy}</p>;
}

function V11Presentation({ presentation }: { presentation: Extract<SummaryPresentation, { kind: "v1.1" }> }) {
  return <>
    <section className="reader-section" aria-label="作者观点">
      <h3 className="reader-cutoff">截至 {asShanghaiTime(presentation.asOf)} 的作者观点</h3>
      {presentation.authorCards.length > 0 ? <div className="author-cards">
        {presentation.authorCards.map((card, index) => <article className="author-card" key={`${card.authorDisplay}-${index}`}>
          <h4>{card.authorDisplay}</h4>
          <dl>
            <dt>核心市场趋势</dt><dd>{tendency(card.marketTrend)}</dd>
            <dt>市场操作倾向</dt><dd>{tendency(card.marketTendency)}</dd>
            <dt>个股操作倾向</dt><dd>{tendency(card.stockTendency)}</dd>
            <dt>方法论</dt><dd>{card.methodology.length > 0 ? card.methodology.join("；") : "未表达"}</dd>
            <dt>不确定性</dt><dd>{card.uncertainty.length > 0 ? card.uncertainty.join("；") : "未表达"}</dd>
          </dl>
          <section aria-label={`${card.authorDisplay} 的个股判断`}>
            <h5>个股判断</h5>
            {card.stockJudgments.length > 0 ? <ul>{card.stockJudgments.map((judgment, judgmentIndex) => <li key={`${judgment.subject ?? "stock"}-${judgmentIndex}`}>
              <strong>{judgment.subject ?? "个股"}</strong>：{judgment.judgment}{judgment.reasoning ? `（${judgment.reasoning}）` : ""} <span>{judgment.evidenceCount} 条安全证据</span>
            </li>)}</ul> : <p>未表达</p>}
          </section>
          <p className="topic-evidence-count">{card.evidenceCount} 条安全证据</p>
        </article>)}
      </div> : <p className="summary-empty">本时段没有可展示的作者观点。</p>}
    </section>
    <section className="reader-section" aria-label="频道话题">
      <h3>频道话题</h3>
      {presentation.topicDiscussions.length > 0 ? <div className="summary-topics">
        {presentation.topicDiscussions.map((topic, index) => <article className="topic-card" key={`${topic.title}-${index}`}>
          <h4>{topic.title}</h4>
          <p>{topic.overview}</p>
          {topic.viewpoints.length > 0 ? <ul className="viewpoint-list">{topic.viewpoints.map((viewpoint, viewpointIndex) => <li key={`${viewpoint.authorDisplay}-${viewpointIndex}`}>
            <strong>{viewpoint.authorDisplay}</strong>：{viewpoint.viewpoint}{viewpoint.reasoning ? `（${viewpoint.reasoning}）` : ""}{viewpoint.tendency ? `；操作倾向：${viewpoint.tendency}` : ""} <span>{viewpoint.evidenceCount} 条安全证据</span>
          </li>)}</ul> : <p>本话题暂无可归属的观点。</p>}
          {topic.uncertainty.length > 0 ? <p className="topic-uncertainty">不确定性：{topic.uncertainty.join("；")}</p> : null}
          <p className="topic-evidence-count">{topic.evidenceCount} 条安全证据</p>
        </article>)}
      </div> : <p className="summary-empty">本时段没有形成频道话题。</p>}
    </section>
    {presentation.warnings.length > 0 ? <section className="reader-section" aria-label="提示">
      <h3>提示</h3>
      <p className="summary-note">{presentation.warnings.join("；")}</p>
    </section> : null}
  </>;
}

function SummaryBody({ presentation, legacyEmptyCopy }: { presentation: SummaryPresentation; legacyEmptyCopy: string }) {
  if (presentation.kind === "v1.1") return <V11Presentation presentation={presentation} />;
  if (presentation.kind === "legacy") return <LegacyTopics presentation={presentation} emptyCopy={legacyEmptyCopy} />;
  return <p className="summary-empty">此版本的摘要格式无法安全展示。</p>;
}

function ManualRefresh({ sourceId }: { sourceId: string }) {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  async function refresh() {
    if (pending) return;
    setPending(true);
    setMessage(null);
    try {
      const response = await fetch("/api/admin/discord/manual-refresh", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ source_id: sourceId }) });
      const body = await response.json().catch(() => null) as { task?: { status?: string; idempotent?: boolean }; error?: string } | null;
      if (!response.ok) {
        setMessage(body?.error === "coverage_not_initialized" ? "请先由管理员初始化该来源的采集范围。" : "暂时无法创建更新任务，请稍后再试。");
        return;
      }
      const status = body?.task?.status;
      const labels: Record<string, string> = {
        queued: "更新任务已排队；本地 Worker 完成后可刷新此页面查看。",
        running: "更新任务正在进行；本地 Worker 完成后可刷新此页面查看。",
        retryable_failed: "上次更新可重试失败；请在 Worker 恢复后再次更新。",
        succeeded: "更新已完成；请刷新此页面查看最新内容。",
      };
      setMessage(labels[status ?? ""] ?? "更新任务已创建；本地 Worker 完成后可刷新此页面查看。");
    } finally {
      setPending(false);
    }
  }
  return <div className="manual-refresh">
    <button type="button" onClick={refresh} disabled={pending}>{pending ? "正在创建更新任务…" : "更新至当前时间"}</button>
    <p>不会操作本地 Chrome；本地 Worker 完成后可刷新页面。</p>
    {message ? <p role="status">{message}</p> : null}
  </div>;
}

export function DiscordReader({ days, manualRefreshSources }: { days: ReaderDay[]; manualRefreshSources?: Record<string, string> }) {
  if (!days.length) return <p>尚无可阅读的 Discord 摘要。</p>;
  const sources = useMemo(() => readerSourceOptions(days), [days]);
  const [sourceKey, setSourceKey] = useState(sources[0]!.sourceKey);
  const dates = readerDateOptions(days, sourceKey);
  const [naturalDate, setNaturalDate] = useState(dates[0] ?? "");
  const selected = days.find((day) => day.source.sourceKey === sourceKey && day.naturalDate === naturalDate) ?? days.find((day) => day.source.sourceKey === sourceKey) ?? days[0]!;
  const presentation = selected.dailySummary.presentation;
  const sourceId = manualRefreshSources?.[selected.source.sourceKey];

  return <section className="reader-shell">
    <aside className="reader-sidebar" aria-label="Discord 内容筛选">
      <label>频道
        <select value={sourceKey} onChange={(event) => { const nextSource = event.target.value; setSourceKey(nextSource); setNaturalDate(readerDateOptions(days, nextSource)[0] ?? ""); }}>
          {sources.map((source) => <option key={source.sourceKey} value={source.sourceKey}>{source.displayName}</option>)}
        </select>
      </label>
      <label>日期
        <select value={selected.naturalDate} onChange={(event) => setNaturalDate(event.target.value)}>
          {readerDateOptions(days, selected.source.sourceKey).map((date) => <option key={date} value={date}>{date}</option>)}
        </select>
      </label>
      {sourceId ? <ManualRefresh sourceId={sourceId} /> : null}
    </aside>
    <article className="reader-content">
      <header><p className="reader-eyebrow">{selected.source.displayName} · {selected.naturalDate}</p><h2>当日研判</h2></header>
      <ReaderStatus status={selected.status} />
      {presentation.kind === "v1.1" ? <V11Presentation presentation={presentation} /> : <section className="reader-section" aria-label="每日摘要"><h3>每日摘要</h3><SummaryBody presentation={presentation} legacyEmptyCopy="本日没有可展示的结构化主题。" /></section>}
      <section className="reader-section"><h3>批次摘要</h3>
        {selected.batches.length > 0 ? selected.batches.map((batch, index) => <details key={index} open><summary>批次 {index + 1}</summary><div className="batch-summary"><SummaryBody presentation={batch.presentation} legacyEmptyCopy="此批次没有可展示的结构化主题。" /></div></details>) : <p className="summary-empty">本日没有单独的批次摘要。</p>}
      </section>
      {selected.dailySummary.history.length > 1 ? <section className="reader-section"><h3>历史版本</h3>
        {selected.dailySummary.history.map((summary) => <details key={`${summary.version}-${summary.createdAt}`} open={summary.version === selected.dailySummary.version}><summary>版本 {summary.version} · {asShanghaiTime(summary.createdAt)}</summary><div className="batch-summary"><SummaryBody presentation={summary.presentation} legacyEmptyCopy="此版本没有可展示的结构化主题。" /></div></details>)}
      </section> : null}
    </article>
  </section>;
}
