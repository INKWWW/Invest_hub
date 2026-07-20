import { WorkerCard } from "../../../components/admin/WorkerCard";
import { AdminShell } from "../../../components/admin/AdminShell";
import { WorkerInviteForm } from "../../../components/admin/WorkerInviteForm";
import { listWorkers } from "../../../lib/db/repositories/workers";

export default async function AdminWorkersPage() {
  const workers = await listWorkers();
  return <AdminShell active="workers">
    <section>
      <h1>Workers</h1>
      <p>Device credentials are never shown here.</p>
      <WorkerInviteForm />
      {workers.length > 0 ? workers.map((worker) => <WorkerCard key={worker.id} worker={worker} />) : <p>No workers enrolled.</p>}
    </section>
  </AdminShell>;
}
