import { describe, expect, it } from "vitest";

import { buildSourceCreation, publicCreatedSource } from "./source-creation";

describe("server-owned source creation", () => {
  it("generates an opaque key and stable collection contract for each source type", () => {
    const discord = buildSourceCreation("discord");
    const x = buildSourceCreation("x");

    expect(discord).toMatchObject({ parameterVersion: "discord-standard-v1" });
    expect(discord.sourceKey).toMatch(/^discord:[0-9a-f-]{36}$/);
    expect(x).toMatchObject({ parameterVersion: "x-standard-v2" });
    expect(x.sourceKey).toMatch(/^x:[0-9a-f-]{36}$/);
    expect(x.sourceKey).not.toBe(discord.sourceKey);
  });

  it("projects a created source without technical metadata", () => {
    const source = publicCreatedSource({
      sourceType: "x",
      displayName: "Researcher",
      resolutionStatus: "pending",
      sourceKey: "x:private",
      parameterVersion: "x-standard-v2",
      id: "source-private",
    });

    expect(source).toEqual({ source_type: "x", display_name: "Researcher", resolution_status: "pending" });
    expect(JSON.stringify(source)).not.toContain("sourceKey");
    expect(JSON.stringify(source)).not.toContain("parameterVersion");
    expect(JSON.stringify(source)).not.toContain("source-private");
  });
});
