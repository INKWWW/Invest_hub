import { redirect } from "next/navigation";

import { DiscordReader } from "../../components/reader/DiscordReader";
import { ReaderSourceNavigation } from "../../components/reader/ReaderSourceNavigation";
import { SessionControls } from "../../components/auth/SessionControls";
import { getCurrentUser } from "../../lib/auth/current-user";
import { readDiscordDay } from "../../lib/db/repositories/reader";
import { listSources } from "../../lib/db/repositories/sources";

export default async function DiscordPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login?next=%2Fdiscord");
  const days = await readDiscordDay();
  const manualRefreshSources = user.role === "admin"
    ? Object.fromEntries((await listSources()).map((source) => [source.source_key, source.id]))
    : undefined;
  return <main className="reader-page">
    <header className="reader-page-header">
      <div className="reader-header-top">
        <a className="product-mark" href="/">Invest Hub</a>
        <SessionControls viewer={user} />
      </div>
      <ReaderSourceNavigation active="discord" />
      <h1>Discord 日度研判</h1>
    </header>
    <DiscordReader days={days} manualRefreshSources={manualRefreshSources} />
  </main>;
}
