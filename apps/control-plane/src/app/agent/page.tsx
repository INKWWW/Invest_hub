import { redirect } from "next/navigation";

import { ResearchAgentShell } from "../../components/agent/ResearchAgentShell";
import { SessionControls } from "../../components/auth/SessionControls";
import { getCurrentUser } from "../../lib/auth/current-user";
import { listResearchThreads } from "../../lib/db/repositories/research-threads";
import { getResearchQuota } from "../../lib/db/repositories/research-quota";

export default async function AgentPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login?next=%2Fagent");
  const [threads, quota] = await Promise.all([listResearchThreads(user.id), getResearchQuota(user.id)]);
  return <main className="agent-page">
    <header className="agent-page-header">
      <div className="agent-header-top">
        <a className="product-mark" href="/">Invest Hub</a>
        <SessionControls viewer={user} />
      </div>
      <p className="agent-kicker">Independent workspace</p>
      <h1>投资研究 Agent</h1>
      <p className="agent-page-intro">把投资问题留在私有 Research Thread 中，保留可追溯的纯文本对话。</p>
    </header>
    <ResearchAgentShell initialThreads={threads} initialQuota={quota} />
  </main>;
}
