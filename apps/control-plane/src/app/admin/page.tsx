import Link from "next/link";

import { AdminShell } from "../../components/admin/AdminShell";
import { StatusBadge } from "../../components/admin/StatusBadge";
import { UserInviteForm } from "../../components/admin/UserInviteForm";
import { WorkerCard } from "../../components/admin/WorkerCard";
import { XManualRecoveryRunForm } from "../../components/admin/XManualRecoveryRunForm";
import { buildTaskViewModel } from "../../lib/admin/view-model";
import { getCurrentUser } from "../../lib/auth/current-user";
import { listSources } from "../../lib/db/repositories/sources";
import { listRecentTasks } from "../../lib/db/repositories/tasks";
import { listWorkers } from "../../lib/db/repositories/workers";

export default async function AdminOverviewPage() {
  const [workers, sources, tasks, viewer] = await Promise.all([listWorkers(), listSources(), listRecentTasks(10), getCurrentUser()]);
  if (!viewer) return null;
  return <AdminShell active="overview" viewer={viewer}>
    <>
      <section>
        <h1>Admin overview</h1>
        <p>Operational state and recovery evidence for the V1 control plane.</p>
        <p><Link href="/admin/tasks">Inspect all tasks</Link></p>
      </section>
      <XManualRecoveryRunForm />
      <UserInviteForm />
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
  </AdminShell>;
}
