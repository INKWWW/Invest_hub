import { redirect } from "next/navigation";

import { DiscordReader } from "../../components/reader/DiscordReader";
import { getCurrentUser } from "../../lib/auth/current-user";
import { readDiscordDay } from "../../lib/db/repositories/reader";

export default async function DiscordPage() {
  if (!await getCurrentUser()) redirect("/login?next=%2Fdiscord");
  return <main className="reader-page">
    <header className="reader-page-header">
      <a className="product-mark" href="/">Invest Hub</a>
      <h1>Daily research, grounded in evidence.</h1>
      <p>Generated summaries and their permitted evidence.</p>
    </header>
    <DiscordReader days={await readDiscordDay()} />
  </main>;
}
