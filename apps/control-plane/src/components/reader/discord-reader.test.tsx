import { describe, expect, it } from "vitest";

import { readerDateOptions, readerSourceOptions } from "./DiscordReader";
import { readerStatusLabel } from "./ReaderStatus";

const days = [
  { source: { sourceKey: "source-b", displayName: "Source B" }, naturalDate: "2099-01-02" },
  { source: { sourceKey: "source-a", displayName: "Source A" }, naturalDate: "2099-01-02" },
  { source: { sourceKey: "source-a", displayName: "Source A" }, naturalDate: "2099-01-01" },
] as never[];

describe("DiscordReader", () => {
  it("keeps channel and date choices bounded to the safe reader DTO", () => {
    expect(readerSourceOptions(days)).toEqual([
      { sourceKey: "source-b", displayName: "Source B" },
      { sourceKey: "source-a", displayName: "Source A" },
    ]);
    expect(readerDateOptions(days, "source-a")).toEqual(["2099-01-02", "2099-01-01"]);
  });

  it("makes failure states explicit instead of calling them no-new-data", () => {
    expect(readerStatusLabel("processing")).toContain("Processing");
    expect(readerStatusLabel("partial_failure")).toContain("Partial failure");
    expect(readerStatusLabel("retryable_failed")).toContain("Retryable failure");
    expect(readerStatusLabel("failed")).toContain("Failed");
  });
});
