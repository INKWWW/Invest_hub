export function ReaderSourceNavigation({ active }: { active: "discord" | "x" }) {
  return <nav className="reader-source-navigation" aria-label="信息来源">
    <a href="/discord" aria-current={active === "discord" ? "page" : undefined}>Discord 信息</a>
    <a href="/x" aria-current={active === "x" ? "page" : undefined}>X 信息</a>
  </nav>;
}
