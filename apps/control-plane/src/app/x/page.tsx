import { redirect } from "next/navigation";

import { SessionControls } from "../../components/auth/SessionControls";
import { ReaderSourceNavigation } from "../../components/reader/ReaderSourceNavigation";
import { XReader } from "../../components/reader/XReader";
import { getCurrentUser } from "../../lib/auth/current-user";
import { readXDay } from "../../lib/db/repositories/reader";

export default async function XPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login?next=%2Fx");
  const days = await readXDay();
  return <main className="reader-page">
    <header className="reader-page-header">
      <div className="reader-header-top"><a className="product-mark" href="/">Invest Hub</a><SessionControls viewer={user} /></div>
      <ReaderSourceNavigation active="x" />
      <h1>X 信息采集</h1>
    </header>
    <XReader days={days} />
  </main>;
}
