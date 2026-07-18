import Link from "next/link";

import { StatusBadge } from "../../components/admin/StatusBadge";
import { WorkerCard } from "../../components/admin/WorkerCard";
import { buildTaskViewModel } from "../../lib/admin/view-model";
import { listSources } from "../../lib/db/repositories/sources";
import { listRecentTasks } from "../../lib/db/repositories/tasks";
import { listWorkers } from "../../lib/db/repositories/workers";

export default async function AdminOverviewPage() {
  const [workers, sources, tasks] = await Promise.all([listWorkers(), listSources(), listRecentTasks(10)]);
  return (
    <>
      <section>
        <h1>Admin overview</h1>
        <p>Operational state and recovery evidence for the V0 control plane.</p>
        <p><Link href="/admin/tasks">Inspect all tasks</Link></p>
      </section>
      <section>
        <h2>Workers ({workers.length})</h2>
        {workers.length > 0 ? workers.map((worker) => <WorkerCard key={worker.id} worker={worker} />) : <p>No workers enrolled.</p>}
      </section>
      <section>
        <h2>Sources ({sources.length})</h2>
        {sources.length > 0 ? (
          <ul>{sources.map((source) => <li key={source.id}>{source.display_name} · {source.enabled ? "enabled" : "disabled"}</li>)}</ul>
        ) : <p>No sources configured.</p>}
      </section>
      <section>
        <h2>Recent tasks</h2>
        {tasks.length > 0 ? (
          <ul>
            {tasks.map((task) => {
              const view = buildTaskViewModel(task);
              return <li key={view.id}><Link href={`/admin/tasks/${view.id}`}>{view.id}</Link> · <StatusBadge status={view.status} /></li>;
            })}
          </ul>
        ) : <p>No tasks created.</p>}
      </section>
    </>
  );
}
