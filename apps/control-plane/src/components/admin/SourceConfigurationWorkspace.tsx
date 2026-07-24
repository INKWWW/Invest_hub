"use client";

import { useState, type ReactNode } from "react";

import type { AdminSourceCard } from "../../lib/db/repositories/sources";
import { SourceConfigurationCard } from "./SourceConfigurationCard";

type SourceType = "discord" | "x";

function tabLabel(sourceType: SourceType, count: number) {
  return `${sourceType === "discord" ? "Discord" : "X"} 配置 · ${count}`;
}

function persistSourceType(sourceType: SourceType) {
  const url = new URL(window.location.href);
  url.searchParams.set("type", sourceType);
  window.history.replaceState({}, "", url);
}

export function SourceConfigurationWorkspace({
  discordSources,
  xSources,
  initialSourceType,
  discordCreateForm,
  xCreateForm,
  discordDetails,
  xDetails,
}: {
  discordSources: AdminSourceCard[];
  xSources: AdminSourceCard[];
  initialSourceType: SourceType;
  discordCreateForm: ReactNode;
  xCreateForm: ReactNode;
  discordDetails: Record<string, ReactNode>;
  xDetails: Record<string, ReactNode>;
}) {
  const [activeSourceType, setActiveSourceType] = useState<SourceType>(initialSourceType);
  const [selectedSourceId, setSelectedSourceId] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const sources = activeSourceType === "discord" ? discordSources : xSources;
  const details = activeSourceType === "discord" ? discordDetails : xDetails;
  const visibleSources = sources.filter((source) => showArchived || !source.archivedAt);

  function activate(sourceType: SourceType) {
    setActiveSourceType(sourceType);
    setSelectedSourceId(null);
    persistSourceType(sourceType);
  }

  function onTabsKeyDown(event: React.KeyboardEvent<HTMLButtonElement>, sourceType: SourceType) {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    activate(sourceType === "discord" ? "x" : "discord");
  }

  return <div className="source-workspace" data-source-type={activeSourceType}>
    <div role="tablist" aria-label="来源配置类型" className="source-workspace-tabs">
      {(["discord", "x"] as const).map((sourceType) => <button
        key={sourceType}
        type="button"
        role="tab"
        id={`${sourceType}-source-tab`}
        aria-selected={activeSourceType === sourceType}
        aria-controls={`${sourceType}-source-panel`}
        tabIndex={activeSourceType === sourceType ? 0 : -1}
        onClick={() => activate(sourceType)}
        onKeyDown={(event) => onTabsKeyDown(event, sourceType)}
      >{tabLabel(sourceType, sourceType === "discord" ? discordSources.length : xSources.length)}</button>)}
    </div>
    <section
      id={`${activeSourceType}-source-panel`}
      role="tabpanel"
      aria-labelledby={`${activeSourceType}-source-tab`}
      className="source-workspace-panel"
    >
      <header className="source-workspace-panel-header">
        <div>
          <p className="source-card-type">{activeSourceType === "discord" ? "Discord 配置" : "X 配置"}</p>
          <h2>{activeSourceType === "discord" ? "管理 Discord 来源" : "管理 X 博主"}</h2>
        </div>
        <label className="source-archived-toggle"><input type="checkbox" checked={showArchived} onChange={(event) => setShowArchived(event.target.checked)} /> 显示已归档</label>
      </header>
      <div className="source-create-zone">{activeSourceType === "discord" ? discordCreateForm : xCreateForm}</div>
      <div className="source-card-list">
        {visibleSources.length > 0 ? visibleSources.map((source) => <SourceConfigurationCard
          key={source.id}
          source={source}
          selected={selectedSourceId === source.id}
          onManage={() => setSelectedSourceId((current) => current === source.id ? null : source.id)}
        >{details[source.id]}</SourceConfigurationCard>) : <p className="source-empty">{showArchived ? "尚无该类型来源。" : "尚无活动来源。"}</p>}
      </div>
    </section>
  </div>;
}
