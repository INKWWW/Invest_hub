"use client";

import type { ReactNode } from "react";

import type { AdminSourceCard } from "../../lib/db/repositories/sources";

const lifecycleLabels: Record<AdminSourceCard["lifecycle"], string> = {
  ready: "可更新与回填",
  identity_pending: "身份验证",
  coverage_uninitialized: "初始化覆盖",
  active_task: "等待任务收口",
  archived: "已归档",
};

function dateLabel(value: string | null): string {
  if (!value) return "尚无完成任务";
  return new Intl.DateTimeFormat("zh-CN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Shanghai",
  }).format(new Date(value));
}

function stageState(lifecycle: AdminSourceCard["lifecycle"], stage: "configuration" | "identity" | "coverage" | "updates") {
  if (lifecycle === "archived") return "blocked";
  const order = lifecycle === "identity_pending" ? 2
    : lifecycle === "coverage_uninitialized" ? 3
      : lifecycle === "ready" || lifecycle === "active_task" ? 4 : 1;
  const stageOrder = stage === "configuration" ? 1 : stage === "identity" ? 2 : stage === "coverage" ? 3 : 4;
  return stageOrder < order ? "complete" : stageOrder === order ? "current" : "upcoming";
}

export function SourceConfigurationCard({
  source,
  selected,
  onManage,
  children,
}: {
  source: AdminSourceCard;
  selected: boolean;
  onManage: () => void;
  children?: ReactNode;
}) {
  const stages = source.sourceType === "x"
    ? [["configuration", "配置"], ["identity", "身份验证"], ["coverage", "初始化覆盖"], ["updates", "更新与回填"]] as const
    : [["configuration", "配置"], ["coverage", "初始化覆盖"], ["updates", "更新与回填"]] as const;

  return <article className="source-configuration-card" data-lifecycle={source.lifecycle}>
    <header className="source-card-header">
      <div>
        <p className="source-card-type">{source.sourceType === "discord" ? "Discord" : "X"}</p>
        <h2>{source.displayName}</h2>
      </div>
      <div className="source-card-actions">
        <span className="source-state" data-enabled={source.enabled}>{source.archivedAt ? "已归档" : source.enabled ? "已启用" : "已停用"}</span>
        <button type="button" aria-expanded={selected} onClick={onManage}>{selected ? "收起管理" : "管理"}</button>
      </div>
    </header>
    <dl className="source-card-facts">
      <div><dt>当前步骤</dt><dd>{lifecycleLabels[source.lifecycle]}</dd></div>
      <div><dt>Worker</dt><dd>{source.workerName ?? "任一已注册 Worker"}</dd></div>
      <div><dt>最近完成</dt><dd>{dateLabel(source.latestCompletedAt)}</dd></div>
    </dl>
    <ol className="source-lifecycle" aria-label={`${source.displayName} 生命周期`}>
      {stages.map(([stage, label]) => <li key={stage} data-state={stageState(source.lifecycle, stage)}>{label}</li>)}
    </ol>
    {selected ? <section className="source-detail" aria-label={`${source.displayName} 管理详情`}>{children}</section> : null}
  </article>;
}
