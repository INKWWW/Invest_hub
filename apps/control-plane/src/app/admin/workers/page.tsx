import { WorkerCard } from "../../../components/admin/WorkerCard";
import { listWorkers } from "../../../lib/db/repositories/workers";

export default async function AdminWorkersPage() {
  const workers = await listWorkers();
  return (
    <section>
      <h1>Workers</h1>
      <p>Device credentials are never shown here.</p>
      {workers.length > 0 ? workers.map((worker) => <WorkerCard key={worker.id} worker={worker} />) : <p>No workers enrolled.</p>}
    </section>
  );
}

