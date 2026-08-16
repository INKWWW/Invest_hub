import { redirect } from "next/navigation";

import { ResearchAgentShell } from "../../components/agent/ResearchAgentShell";
import { SessionControls } from "../../components/auth/SessionControls";
import { ReaderSourceNavigation } from "../../components/reader/ReaderSourceNavigation";
import { getCurrentUser } from "../../lib/auth/current-user";
import { listResearchThreads } from "../../lib/db/repositories/research-threads";

export default async function AgentPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login?next=%2Fagent");
  const threads = await listResearchThreads(user.id);
  return <main className="agent-page">
    <header className="agent-page-header">
      <div className="agent-header-top">
        <a className="product-mark" href="/">Invest Hub</a>
        <SessionControls viewer={user} />
      </div>
      <ReaderSourceNavigation active="agent" />
      <p className="agent-kicker">Independent workspace</p>
      <h1>投资研究 Agent</h1>
      <p className="agent-page-intro">把投资问题留在私有 Research Thread 中，保留可追溯的纯文本对话。</p>
    </header>
    <ResearchAgentShell initialThreads={threads} />
  </main>;
}
