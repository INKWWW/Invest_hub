import { listAdminSources } from "../../../lib/db/repositories/sources";
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
import { XSourceRemovalControl } from "../../../components/admin/XSourceRemovalControl";
import { getCurrentUser } from "../../../lib/auth/current-user";
import { SourceConfigurationWorkspace } from "../../../components/admin/SourceConfigurationWorkspace";

export default async function AdminSourcesPage({ searchParams }: { searchParams?: Promise<{ type?: string }> }) {
  const [{ type }, discordSources, xSources, viewer] = await Promise.all([
    searchParams ?? Promise.resolve<{ type?: string }>({}),
    listAdminSources({ sourceType: "discord", includeArchived: true }),
    listAdminSources({ sourceType: "x", includeArchived: true }),
    getCurrentUser(),
  ]);
  if (!viewer) return null;
  const initialSourceType = type === "x" ? "x" : "discord";
  const discordDetails = Object.fromEntries(discordSources.map((source) => [source.id, <div className="source-detail-grid" key={source.id}>
    <SourceAdministrationForm sourceId={source.id} />
    <SourceCoverageForm sourceId={source.id} />
    <SourceRuleForm sourceId={source.id} />
    <SourceAuthorProfilesForm sourceId={source.id} />
  </div>]));
  const xDetails = Object.fromEntries(xSources.map((source) => [source.id, <div className="source-detail-grid" key={source.id}>
    <SourceAdministrationForm sourceId={source.id} />
    <XCoverageForm sourceId={source.id} />
    <XManualRefreshForm sourceId={source.id} />
    <XHistoryBackfillForm sourceId={source.id} />
    {!source.archivedAt ? <XSourceRemovalControl sourceId={source.id} displayName={source.displayName} canRemove={source.lifecycle !== "active_task"} /> : null}
  </div>]));
  return <AdminShell active="sources" viewer={viewer}>
    <section className="source-page">
      <h1>信息来源</h1>
      <p>按来源类型管理配置、采集边界与运行操作。页面只展示决定下一步的安全状态，不显示 URL、浏览器 Profile 或原始内容。</p>
      <SourceConfigurationWorkspace
        discordSources={discordSources}
        xSources={xSources}
        initialSourceType={initialSourceType}
        discordCreateForm={<SourceCreateForm />}
        xCreateForm={<XSourceForm />}
        discordDetails={discordDetails}
        xDetails={xDetails}
      />
    </section>
  </AdminShell>;
}
