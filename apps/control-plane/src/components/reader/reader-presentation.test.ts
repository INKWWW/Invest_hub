import { describe, expect, it } from "vitest";

import { evidenceCount, presentSummary } from "./reader-presentation";

describe("presentSummary", () => {
  it("projects only approved structured fields", () => {
    const result = presentSummary({
      topics: [{
        title: "Earnings",
        summary: "Guidance changed.",
        source_message_ids: ["message-1", "message-2"],
        author_scope: "target",
        tickers: ["ABC"],
        operation_tendency: "watch",
        uncertainty: "Attachment is unparsed.",
        hidden_note: "must not render",
      }],
      warnings: ["Unparsed attachment"],
      local_raw_ref: "local://must-not-render",
    }, { unparsed_media: true });

    expect(result).toEqual({
      topics: [{
        title: "Earnings",
        summary: "Guidance changed.",
        sourceMessageIds: ["message-1", "message-2"],
        authorScope: "target",
        tickers: ["ABC"],
        operationTendency: "watch",
        uncertainty: "Attachment is unparsed.",
      }],
      warnings: ["Unparsed attachment"],
      mediaUnparsed: true,
    });
    expect(JSON.stringify(result)).not.toContain("local://");
    expect(JSON.stringify(result)).not.toContain("hidden_note");
    expect(evidenceCount(["message-1", "message-2"])).toBe(2);
  });

  it("fails closed for malformed output", () => {
    expect(presentSummary({ topics: "not-an-array", warnings: [3] }, { unparsed_media: true })).toEqual({
      topics: [],
      warnings: [],
      mediaUnparsed: false,
    });
  });
});
