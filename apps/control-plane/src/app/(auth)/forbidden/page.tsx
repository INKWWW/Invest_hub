import Link from "next/link";
import { redirect } from "next/navigation";

import { SessionControls } from "../../../components/auth/SessionControls";
import { getCurrentUser } from "../../../lib/auth/current-user";

export default async function ForbiddenPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login?next=%2Fadmin");
  if (user.role === "admin") redirect("/admin");

  return <main className="forbidden-page">
    <header className="forbidden-page-header">
      <a className="product-mark" href="/discord">Invest Hub</a>
      <SessionControls viewer={user} />
    </header>
    <section className="forbidden-card">
      <p className="reader-kicker">Access boundary</p>
      <h1>此区域仅限管理员</h1>
      <p>你当前登录的是普通用户账号。管理员配置、任务操作与普通用户阅读权限保持隔离。</p>
      <Link href="/discord">返回 Discord 日度研判</Link>
    </section>
  </main>;
}
