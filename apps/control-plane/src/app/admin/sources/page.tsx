import { listSources } from "../../../lib/db/repositories/sources";
import { SourceCreateForm } from "../../../components/admin/SourceCreateForm";
import { SourceRuleForm } from "../../../components/admin/SourceRuleForm";
import { SourceAdministrationForm } from "../../../components/admin/SourceAdministrationForm";
import { listWorkers } from "../../../lib/db/repositories/workers";

export default async function AdminSourcesPage() {
  const [sources, workers] = await Promise.all([listSources(), listWorkers()]);
  return (
    <section>
      <h1>Sources</h1>
      <p>Only logical source identifiers are shown. Channel URLs and Profile references remain on the Worker.</p>
      <SourceCreateForm />
      {sources.length > 0 ? (
        <table>
          <thead><tr><th>Source</th><th>Type</th><th>Parameter version</th><th>State</th><th>Authorized Worker</th><th>Rules</th></tr></thead>
          <tbody>
            {sources.map((source) => (
              <tr key={source.id}>
                <td>{source.display_name} ({source.source_key})</td>
                <td>{source.source_type}</td>
                <td>{source.parameter_version}</td>
                <td><SourceAdministrationForm sourceId={source.id} enabled={source.enabled} authorizedWorkerId={source.authorized_worker_id} workers={workers} /></td>
                <td>{source.authorized_worker_id ?? "any enrolled Worker"}</td>
                <td>v{source.author_rules_version}<SourceRuleForm sourceId={source.id} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <p>No sources configured.</p>}
    </section>
  );
}
