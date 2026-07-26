"use client";

import { useEffect, useMemo, useState } from "react";

import type { XReaderDay } from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";

const ALL = "all";

function sources(days: XReaderDay[]) {
  return [...new Map(days.map((day) => [day.source.sourceKey, day.source])).values()];
}

function dates(days: XReaderDay[]) {
  return [...new Set(days.map((day) => day.naturalDate))];
}

function validOrAll(value: string | undefined, values: string[]) {
  return value && values.includes(value) ? value : ALL;
}

function XReaderDayCard({ day }: { day: XReaderDay }) {
  return <article className="reader-day-card">
    <header><p className="x-reader-context"><strong>{day.source.displayName}</strong><span> · {day.naturalDate}</span></p><h2 className="x-reader-heading">每日综合观点</h2></header>
    <ReaderStatus status={day.status} asOf={day.segments.at(-1)?.occurredThroughAt} />
    {day.segments.map((segment) => <section className="reader-section" key={segment.id}>
      {segment.viewpoints.length ? <ul className="x-viewpoints">{segment.viewpoints.map((viewpoint, viewpointIndex) => <li key={viewpointIndex}>{viewpoint}</li>)}</ul> : <p className="summary-empty">本窗口没有形成新的综合观点。</p>}
      {segment.uncertainties.length ? <p className="topic-uncertainty">不确定性：{segment.uncertainties.join("；")}</p> : null}
      <details className="x-evidence" open={false}>
        <summary>证据明细 · {segment.analyses.length} 条帖子分析</summary>
        {segment.analyses.map((analysis) => <article className="x-analysis" key={analysis.postId}>
          <h4><a href={analysis.postLink} target="_blank" rel="noreferrer">原始 X 帖子</a></h4>
          <p><strong>博主观点：</strong>{analysis.bloggerViewpoint ?? "未表达（例如普通 repost）"}</p>
          {analysis.arguments.length ? <p><strong>论据：</strong>{analysis.arguments.join("；")}</p> : null}
          {analysis.quotedPostViewpoint ? <p><strong>引用帖观点：</strong>{analysis.quotedPostViewpoint}</p> : null}
          {analysis.uncertainties.length ? <p className="topic-uncertainty">不确定性：{analysis.uncertainties.join("；")}</p> : null}
        </article>)}
      </details>
    </section>)}
  </article>;
}

export function XReader({ days, initialSourceKey, initialNaturalDate }: {
  days: XReaderDay[];
  initialSourceKey?: string;
  initialNaturalDate?: string;
}) {
  if (!days.length) return <p>尚无可阅读的 X 信息。</p>;
  const sourceOptions = useMemo(() => sources(days), [days]);
  const dateOptions = useMemo(() => dates(days), [days]);
  const [sourceKey, setSourceKey] = useState(() => validOrAll(initialSourceKey, sourceOptions.map((source) => source.sourceKey)));
  const [naturalDate, setNaturalDate] = useState(() => validOrAll(initialNaturalDate, dateOptions));
  const visibleDays = useMemo(() => days.filter((day) =>
    (sourceKey === ALL || day.source.sourceKey === sourceKey) && (naturalDate === ALL || day.naturalDate === naturalDate),
  ), [days, naturalDate, sourceKey]);

  useEffect(() => {
    const searchParams = new URLSearchParams(window.location.search);
    if (sourceKey === ALL) searchParams.delete("source"); else searchParams.set("source", sourceKey);
    if (naturalDate === ALL) searchParams.delete("date"); else searchParams.set("date", naturalDate);
    const query = searchParams.toString();
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash}`);
  }, [naturalDate, sourceKey]);

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
      {visibleDays.length ? <div className="reader-result-list">{visibleDays.map((day) => <XReaderDayCard key={`${day.source.sourceKey}:${day.naturalDate}`} day={day} />)}</div> : <p className="summary-empty">没有找到符合当前博主和日期筛选的 X 信息。</p>}
    </article>
  </section>;
}
