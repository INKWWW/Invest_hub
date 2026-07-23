import { listSources } from "../../../lib/db/repositories/sources";
import { AdminShell } from "../../../components/admin/AdminShell";
import { SourceCreateForm } from "../../../components/admin/SourceCreateForm";
import { SourceRuleForm } from "../../../components/admin/SourceRuleForm";
import { SourceAuthorProfilesForm } from "../../../components/admin/SourceAuthorProfilesForm";
import { SourceAdministrationForm } from "../../../components/admin/SourceAdministrationForm";
import { SourceCoverageForm } from "../../../components/admin/SourceCoverageForm";
import { XCoverageForm } from "../../../components/admin/XCoverageForm";
import { XHistoryBackfillForm } from "../../../components/admin/XHistoryBackfillForm";
import { XManualRefreshForm } from "../../../components/admin/XManualRefreshForm";
import { XSourceForm } from "../../../components/admin/XSourceForm";
import { getCurrentUser } from "../../../lib/auth/current-user";
import { listWorkers } from "../../../lib/db/repositories/workers";

export default async function AdminSourcesPage() {
  const [sources, workers, viewer] = await Promise.all([listSources(), listWorkers(), getCurrentUser()]);
  if (!viewer) return null;
  return <AdminShell active="sources" viewer={viewer}>
    <section>
      <h1>信息来源</h1>
      <p>Discord 与 X 采用独立配置和采集边界。内部来源标识、URL 和本地 Profile 引用不会在普通阅读页面展示。</p>
      <SourceCreateForm />
      <XSourceForm />
      {sources.length > 0 ? (
        <table>
          <thead><tr><th>来源</th><th>类型</th><th>参数版本</th><th>状态与名称</th><th>采集范围</th><th>授权 Worker</th><th>规则</th><th>作者配置</th></tr></thead>
          <tbody>
            {sources.map((source) => (
              <tr key={source.id}>
                <td>{source.display_name}</td>
                <td>{source.source_type}</td>
                <td>{source.parameter_version}</td>
                <td><SourceAdministrationForm sourceId={source.id} displayName={source.display_name} enabled={source.enabled} authorizedWorkerId={source.authorized_worker_id} workers={workers} /></td>
                <td>{source.source_type === "x" ? <><XCoverageForm sourceId={source.id} /><XManualRefreshForm sourceId={source.id} /><XHistoryBackfillForm sourceId={source.id} /></> : <SourceCoverageForm sourceId={source.id} />}</td>
                <td>{source.authorized_worker_id ?? "any enrolled Worker"}</td>
                <td>{source.source_type === "discord" ? <>v{source.author_rules_version}<SourceRuleForm sourceId={source.id} /></> : "X 博主身份独立解析"}</td>
                <td>{source.source_type === "discord" ? <SourceAuthorProfilesForm sourceId={source.id} /> : "待 X 身份验证"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <p>No sources configured.</p>}
    </section>
  </AdminShell>;
}
