import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { DiscordReader, readerDateOptions, readerSourceOptions } from "./DiscordReader";
import { readerStatusLabel } from "./ReaderStatus";
import type { ReaderDay } from "../../lib/db/repositories/reader";

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

  it("renders summary-first content without serializing summary JSON or raw evidence", () => {
    const renderedDays: ReaderDay[] = [{
      source: { sourceKey: "source-a", displayName: "Source A" },
      naturalDate: "2099-01-02",
      status: "succeeded",
      dailySummary: {
        id: "daily-1",
        version: 1,
        output: {
          topics: [{
            title: "Earnings",
            summary: "Guidance changed.",
            source_message_ids: ["message-1", "message-2"],
            author_scope: "target",
            tickers: ["ABC"],
          }],
          warnings: ["Unparsed attachment"],
          local_raw_ref: "local://must-not-render",
        },
        coverage: { unparsed_media: true },
        history: [],
      },
      batches: [{
        id: "batch-1",
        inputMessageIds: ["message-1", "message-2"],
        structuredRunIds: ["run-1"],
        output: {
          topics: [{
            title: "Earnings",
            summary: "Guidance changed.",
            source_message_ids: ["message-1", "message-2"],
            author_scope: "target",
          }],
          warnings: [],
        },
        coverage: { unparsed_media: true },
      }],
      messages: [{
        externalMessageId: "message-1",
        occurredAt: "2099-01-02T09:00:00.000Z",
        authorDisplay: "Fixture Author",
        content: "Public fixture message.",
        hasUnparsedMedia: true,
        unresolved: false,
        evidenceExpired: false,
      }],
    }];

    const html = renderToStaticMarkup(<DiscordReader days={renderedDays} />);

    expect(html).toContain("Earnings");
    expect(html).toContain("2 evidence messages");
    expect(html).toContain("Unparsed media");
    expect(html).toContain("Batch summaries");
    expect(html).toContain("<details open=\"\">");
    expect(html).toContain("Channel");
    expect(html).toContain("Date");
    expect(html).not.toContain("Evidence-backed messages");
    expect(html).not.toContain("Fixture Author");
    expect(html).not.toContain("Public fixture message.");
    expect(html).not.toContain("source_message_ids");
    expect(html).not.toContain("local://");
  });
});
