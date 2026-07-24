"use client";

import { useMemo, useState } from "react";

import type { XReaderDay } from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";

function sources(days: XReaderDay[]) {
  return [...new Map(days.map((day) => [day.source.sourceKey, day.source])).values()];
}

function dates(days: XReaderDay[], sourceKey: string) {
  return days.filter((day) => day.source.sourceKey === sourceKey).map((day) => day.naturalDate);
}

export function XReader({ days }: { days: XReaderDay[] }) {
  if (!days.length) return <p>尚无可阅读的 X 信息。</p>;
  const sourceOptions = useMemo(() => sources(days), [days]);
  const [sourceKey, setSourceKey] = useState(sourceOptions[0]!.sourceKey);
  const [naturalDate, setNaturalDate] = useState(dates(days, sourceKey)[0] ?? "");
  const selected = days.find((day) => day.source.sourceKey === sourceKey && day.naturalDate === naturalDate)
    ?? days.find((day) => day.source.sourceKey === sourceKey) ?? days[0]!;
  return <section className="reader-shell">
    <aside className="reader-sidebar" aria-label="X 内容筛选">
      <label>博主
        <select value={sourceKey} onChange={(event) => { const next = event.target.value; setSourceKey(next); setNaturalDate(dates(days, next)[0] ?? ""); }}>
          {sourceOptions.map((source) => <option key={source.sourceKey} value={source.sourceKey}>{source.displayName}</option>)}
        </select>
      </label>
      <label>日期
        <select value={selected.naturalDate} onChange={(event) => setNaturalDate(event.target.value)}>
          {dates(days, selected.source.sourceKey).map((date) => <option key={date} value={date}>{date}</option>)}
        </select>
      </label>
    </aside>
    <article className="reader-content">
      <header><p className="x-reader-context"><strong>{selected.source.displayName}</strong><span> · {selected.naturalDate}</span></p><h2 className="x-reader-heading">每日综合观点</h2></header>
      <ReaderStatus status={selected.status} asOf={selected.segments.at(-1)?.occurredThroughAt} />
      {selected.segments.map((segment) => <section className="reader-section" key={segment.id}>
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
    </article>
  </section>;
}
