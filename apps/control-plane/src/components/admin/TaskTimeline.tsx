type TimelineEvent = {
  id: string;
  attempt: number;
  event_type: string;
  occurred_at: string;
  details: unknown;
};

function failureClass(details: unknown): string | null {
  if (!details || typeof details !== "object" || Array.isArray(details)) return null;
  const value = (details as Record<string, unknown>).failure_class;
  return typeof value === "string" ? value : null;
}

function failureStage(details: unknown): string | null {
  if (!details || typeof details !== "object" || Array.isArray(details)) return null;
  const value = (details as Record<string, unknown>).failure_stage;
  return typeof value === "string" ? value : null;
}

export function TaskTimeline({ events }: { events: TimelineEvent[] }) {
  if (events.length === 0) return <p>No task events recorded.</p>;
  return (
    <ol>
      {events.map((event) => (
        <li key={event.id}>
          <time dateTime={event.occurred_at}>{event.occurred_at}</time>{" "}
          <strong>{event.event_type}</strong>{" "}
          <span>attempt {event.attempt}</span>
          {failureClass(event.details) ? <span> ({failureClass(event.details)}{failureStage(event.details) ? ` / ${failureStage(event.details)}` : ""})</span> : null}
        </li>
      ))}
    </ol>
  );
}
