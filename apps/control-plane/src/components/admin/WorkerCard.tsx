type WorkerCardProps = {
  worker: {
    id: string;
    name: string;
    status: string;
    last_heartbeat_at: string | null;
    enrolled_at: string;
    revoked_at: string | null;
  };
};

export function WorkerCard({ worker }: WorkerCardProps) {
  return (
    <article>
      <h2>{worker.name}</h2>
      <dl>
        <dt>Worker ID</dt>
        <dd>{worker.id}</dd>
        <dt>Status</dt>
        <dd>{worker.status}</dd>
        <dt>Last heartbeat</dt>
        <dd>{worker.last_heartbeat_at ?? "Never"}</dd>
        <dt>Enrolled</dt>
        <dd>{worker.enrolled_at}</dd>
        <dt>Revoked</dt>
        <dd>{worker.revoked_at ?? "No"}</dd>
      </dl>
    </article>
  );
}

