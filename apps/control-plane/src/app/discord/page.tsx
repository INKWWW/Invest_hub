import { redirect } from "next/navigation";

import { DiscordReader } from "../../components/reader/DiscordReader";
import { getCurrentUser } from "../../lib/auth/current-user";
import { readDiscordDay } from "../../lib/db/repositories/reader";

export default async function DiscordPage() {
  if (!await getCurrentUser()) redirect("/login?next=%2Fdiscord");
  return <main><h1>Discord research</h1><p>Generated summaries and their permitted evidence. Local raw files and Worker diagnostics are never shown here.</p><DiscordReader days={await readDiscordDay()} /></main>;
}
