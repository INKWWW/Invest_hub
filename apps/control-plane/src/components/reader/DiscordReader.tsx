import type { ReaderDay } from "../../lib/db/repositories/reader";

export function DiscordReader({ days }: { days: ReaderDay[] }) {
  if (!days.length) return <p>No generated Discord summaries yet.</p>;
  return <section>{days.map((day) => <article key={`${day.source.sourceKey}-${day.naturalDate}`}>
    <h2>{day.source.displayName} · {day.naturalDate}</h2>
    <p>Summary version {day.dailySummary.version}</p>
    <pre>{JSON.stringify(day.dailySummary.output, null, 2)}</pre>
    <h3>Evidence-backed messages</h3>
    {day.messages.map((message) => <details key={message.externalMessageId}><summary>{message.authorDisplay ?? "Unknown"} · {message.occurredAt ?? "unknown time"}{message.hasUnparsedMedia ? " · unparsed media" : ""}</summary><p>{message.content}</p>{message.unresolved ? <p>Reply context unresolved.</p> : null}</details>)}
  </article>)}</section>;
}
