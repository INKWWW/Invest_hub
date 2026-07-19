"use client";

import { useMemo, useState } from "react";

import type { ReaderDay } from "../../lib/db/repositories/reader";
import { ReaderStatus } from "./ReaderStatus";

export function readerSourceOptions(days: ReaderDay[]) {
  return [...new Map(days.map((day) => [day.source.sourceKey, day.source])).values()];
}

export function readerDateOptions(days: ReaderDay[], sourceKey: string) {
  return days.filter((day) => day.source.sourceKey === sourceKey).map((day) => day.naturalDate);
}

function displayValue(value: unknown): string {
  return JSON.stringify(value, null, 2);
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
      <pre className="reader-summary">{displayValue(selected.dailySummary.output)}</pre>
      <section>
        <h3>Batch summaries</h3>
        {selected.batches.map((batch) => <details key={batch.id}>
          <summary>Batch with {Array.isArray(batch.inputMessageIds) ? batch.inputMessageIds.length : "recorded"} evidence messages</summary>
          <pre>{displayValue(batch.output)}</pre>
        </details>)}
      </section>
      <section>
        <h3>Evidence-backed messages</h3>
        {selected.messages.map((message) => <details key={message.externalMessageId}>
          <summary>{message.authorDisplay ?? "Unknown"} · {message.occurredAt ?? "unknown time"}{message.hasUnparsedMedia ? " · unparsed media" : ""}{message.evidenceExpired ? " · evidence expired" : ""}</summary>
          <p>{message.content}</p>
          {message.unresolved ? <p>Reply context unresolved.</p> : null}
        </details>)}
      </section>
      {selected.dailySummary.history.length > 1 ? <section>
        <h3>Summary history</h3>
        {selected.dailySummary.history.map((summary) => <details key={summary.id} open={summary.id === selected.dailySummary.id}>
          <summary>Version {summary.version} · {summary.createdAt}</summary>
          <pre>{displayValue(summary.output)}</pre>
        </details>)}
      </section> : null}
    </article>
  </section>;
}
