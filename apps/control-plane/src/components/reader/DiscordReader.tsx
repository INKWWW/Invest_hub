"use client";

import { useMemo, useState } from "react";

import type { ReaderDay } from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";
import { evidenceCount, presentSummary, type SummaryPresentation } from "./reader-presentation";

export function readerSourceOptions(days: ReaderDay[]) {
  return [...new Map(days.map((day) => [day.source.sourceKey, day.source])).values()];
}

export function readerDateOptions(days: ReaderDay[], sourceKey: string) {
  return days.filter((day) => day.source.sourceKey === sourceKey).map((day) => day.naturalDate);
}

function SummaryTopics({ presentation, emptyCopy }: { presentation: SummaryPresentation; emptyCopy: string }) {
  return <>
    {presentation.topics.length > 0 ? <div className="summary-topics">
      {presentation.topics.map((topic, index) => <article className="topic-card" key={`${topic.title}-${index}`}>
        <header className="topic-heading">
          <h3>{topic.title}</h3>
          {topic.authorScope ? <span className="topic-scope">{topic.authorScope === "target" ? "Target author" : "Channel discussion"}</span> : null}
        </header>
        <p>{topic.summary}</p>
        {topic.tickers.length > 0 ? <p className="topic-tickers">{topic.tickers.join(" · ")}</p> : null}
        {topic.operationTendency ? <p><strong>Action context:</strong> {topic.operationTendency}</p> : null}
        {topic.uncertainty ? <p className="topic-uncertainty"><strong>Uncertainty:</strong> {topic.uncertainty}</p> : null}
        <p className="topic-evidence-count">{evidenceCount(topic.sourceMessageIds)} evidence messages</p>
      </article>)}
    </div> : <p className="summary-empty">{emptyCopy}</p>}
    {presentation.warnings.length > 0 ? <section className="summary-warnings" aria-label="Summary warnings">
      <h3>Notes</h3>
      <ul>{presentation.warnings.map((warning, index) => <li key={`${warning}-${index}`}>{warning}</li>)}</ul>
    </section> : null}
    {presentation.mediaUnparsed ? <p className="summary-media-boundary"><strong>Unparsed media:</strong> images, files, and external article bodies were not interpreted.</p> : null}
  </>;
}

export function DiscordReader({ days }: { days: ReaderDay[] }) {
  if (!days.length) return <p>No generated Discord summaries yet.</p>;
  const sources = useMemo(() => readerSourceOptions(days), [days]);
  const [sourceKey, setSourceKey] = useState(sources[0]!.sourceKey);
  const dates = readerDateOptions(days, sourceKey);
  const [naturalDate, setNaturalDate] = useState(dates[0] ?? "");
  const selected = days.find((day) => day.source.sourceKey === sourceKey && day.naturalDate === naturalDate)
    ?? days.find((day) => day.source.sourceKey === sourceKey)
    ?? days[0]!;
  const evidenceExpired = selected.messages.some((message) => message.evidenceExpired);
  const dailyPresentation = presentSummary(selected.dailySummary.output, selected.dailySummary.coverage);

  return <section className="reader-shell">
    <aside className="reader-sidebar" aria-label="Discord reader filters">
      <label>Channel
        <select value={sourceKey} onChange={(event) => {
          const nextSource = event.target.value;
          setSourceKey(nextSource);
          setNaturalDate(readerDateOptions(days, nextSource)[0] ?? "");
        }}>
          {sources.map((source) => <option key={source.sourceKey} value={source.sourceKey}>{source.displayName}</option>)}
        </select>
      </label>
      <label>Date
        <select value={selected.naturalDate} onChange={(event) => setNaturalDate(event.target.value)}>
          {readerDateOptions(days, selected.source.sourceKey).map((date) => <option key={date} value={date}>{date}</option>)}
        </select>
      </label>
    </aside>
    <article className="reader-content">
      <header>
        <p className="reader-eyebrow">{selected.source.displayName} · {selected.naturalDate}</p>
        <h2>Daily summary</h2>
        <p>Current version {selected.dailySummary.version}</p>
      </header>
      <ReaderStatus status={selected.status} evidenceExpired={evidenceExpired} />
      <section className="reader-summary" aria-label="Daily summary topics">
        <SummaryTopics presentation={dailyPresentation} emptyCopy="No structured topics were generated for this day." />
      </section>
      <section>
        <h3>Batch summaries</h3>
        {selected.batches.map((batch) => <details key={batch.id} open>
          <summary>Batch with {Array.isArray(batch.inputMessageIds) ? batch.inputMessageIds.length : "recorded"} evidence messages</summary>
          <div className="batch-summary">
            <SummaryTopics presentation={presentSummary(batch.output, batch.coverage)} emptyCopy="No structured topics were generated for this batch." />
          </div>
        </details>)}
      </section>
      {selected.dailySummary.history.length > 1 ? <section>
        <h3>Summary history</h3>
        {selected.dailySummary.history.map((summary) => <details key={summary.id} open={summary.id === selected.dailySummary.id}>
          <summary>Version {summary.version} · {summary.createdAt}</summary>
          <div className="batch-summary">
            <SummaryTopics presentation={presentSummary(summary.output, summary.coverage)} emptyCopy="No structured topics were generated for this version." />
          </div>
        </details>)}
      </section> : null}
    </article>
  </section>;
}
