import { randomUUID } from "node:crypto";

export type NewSourceType = "discord" | "x";

const defaultParameterVersion = {
  discord: "discord-standard-v1",
  x: "x-standard-v2",
} as const;

export function buildSourceCreation(type: NewSourceType) {
  return {
    sourceKey: `${type}:${randomUUID()}`,
    parameterVersion: defaultParameterVersion[type],
  };
}

type CreatedSource = {
  sourceType: NewSourceType;
  displayName: string;
  resolutionStatus?: "pending";
  sourceKey: string;
  parameterVersion: string;
  id: string;
};

export function publicCreatedSource(source: CreatedSource) {
  const receipt = {
    source_type: source.sourceType,
    display_name: source.displayName,
  };
  return source.resolutionStatus === "pending"
    ? { ...receipt, resolution_status: "pending" as const }
    : receipt;
}
