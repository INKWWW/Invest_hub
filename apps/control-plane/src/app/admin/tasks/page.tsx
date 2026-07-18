import Link from "next/link";

import { StatusBadge } from "../../../components/admin/StatusBadge";
import { buildTaskViewModel, canRetryTask } from "../../../lib/admin/view-model";
import { listRecentTasks } from "../../../lib/db/repositories/tasks";
import { listSources } from "../../../lib/db/repositories/sources";
import { TaskCreateForm } from "../../../components/admin/TaskCreateForm";

export default async function AdminTasksPage() {
  const [tasks, sources] = await Promise.all([listRecentTasks(50), listSources()]);
  return (
    <section>
      <h1>Tasks</h1>
      <p>Task state, lease ownership and safe checkpoint are shown without raw prompt or model response data.</p>
      <TaskCreateForm sources={sources.filter((source) => source.enabled)} />
      {tasks.length > 0 ? (
        <table>
          <thead><tr><th>Task</th><th>Source</th><th>Status</th><th>Checkpoint</th><th>Lease</th><th>Action</th></tr></thead>
          <tbody>
            {tasks.map((task) => {
              const view = buildTaskViewModel(task);
              return (
                <tr key={view.id}>
                  <td><Link href={`/admin/tasks/${view.id}`}>{view.id}</Link></td>
                  <td>{view.sourceId}</td>
                  <td><StatusBadge status={view.status} /></td>
                  <td>{view.checkpoint ?? "—"}</td>
                  <td>{task.lease_expires_at ?? "—"}</td>
                  <td>{canRetryTask(task) ? <Link href={`/admin/tasks/${view.id}`}>Review retry</Link> : "—"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      ) : <p>No tasks created.</p>}
    </section>
  );
}
