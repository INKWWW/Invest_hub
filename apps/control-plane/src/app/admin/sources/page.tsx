import { listSources } from "../../../lib/db/repositories/sources";
import { SourceCreateForm } from "../../../components/admin/SourceCreateForm";

export default async function AdminSourcesPage() {
  const sources = await listSources();
  return (
    <section>
      <h1>Sources</h1>
      <p>Only logical source identifiers are shown. Channel URLs and Profile references remain on the Worker.</p>
      <SourceCreateForm />
      {sources.length > 0 ? (
        <table>
          <thead><tr><th>Source</th><th>Type</th><th>Parameter version</th><th>State</th></tr></thead>
          <tbody>
            {sources.map((source) => (
              <tr key={source.id}>
                <td>{source.display_name} ({source.source_key})</td>
                <td>{source.source_type}</td>
                <td>{source.parameter_version}</td>
                <td>{source.enabled ? "enabled" : "disabled"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <p>No sources configured.</p>}
    </section>
  );
}
