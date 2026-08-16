export function ReaderSourceNavigation({ active }: { active: "agent" | "discord" | "x" }) {
  return <nav className="reader-source-navigation" aria-label="主要模块">
    <div className="reader-source-links">
      <a href="/agent" aria-current={active === "agent" ? "page" : undefined}>投资研究 Agent</a>
      <a href="/x" aria-current={active === "x" ? "page" : undefined}>X 信息</a>
      <a href="/discord" aria-current={active === "discord" ? "page" : undefined}>Discord 信息-WIP</a>
    </div>
  </nav>;
}
