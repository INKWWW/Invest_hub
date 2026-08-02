import { redirect } from "next/navigation";

import { SessionControls } from "../../components/auth/SessionControls";
import { ReaderSourceNavigation } from "../../components/reader/ReaderSourceNavigation";
import { XReader } from "../../components/reader/XReader";
import { getCurrentUser } from "../../lib/auth/current-user";
import { readXDay } from "../../lib/db/repositories/reader";

type XPageSearchParams = { source?: string | string[] };

function singleValue(value: string | string[] | undefined) {
  return typeof value === "string" ? value : undefined;
}

function shanghaiNaturalDate(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const value = Object.fromEntries(parts
    .filter((part) => part.type !== "literal")
    .map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

export default async function XPage({ searchParams }: { searchParams?: Promise<XPageSearchParams> }) {
  const user = await getCurrentUser();
  if (!user) redirect("/login?next=%2Fx");
  const filters = await searchParams;
  const days = await readXDay();
  return <main className="reader-page">
    <header className="reader-page-header">
      <div className="reader-header-top"><a className="product-mark" href="/">Invest Hub</a><SessionControls viewer={user} /></div>
      <ReaderSourceNavigation active="x" />
      <h1>X 信息采集</h1>
    </header>
    <XReader days={days} initialSourceKey={singleValue(filters?.source)} initialNaturalDate={shanghaiNaturalDate()} />
  </main>;
}
