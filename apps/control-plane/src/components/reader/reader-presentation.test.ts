import { describe, expect, it } from "vitest";

import { presentSummary } from "./reader-presentation";

describe("presentSummary", () => {
  it("projects V1.1 author and topic presentation without identities or evidence references", () => {
    const result = presentSummary({
      schema_version: "v1.1",
      natural_date: "2099-01-02",
      as_of: "2099-01-02T09:30:00.000Z",
      author_cards: [{
        author_id: "author-1",
        author_display: "作者甲",
        core_logic: {
          market_trend: "市场仍在观察政策落地。",
          stock_judgments: [{ subject: "ABC", judgment: "等待财报确认。", reasoning: "估值仍偏高。", source_message_ids: ["message-1"] }],
        },
        operation_tendency: { market: null, stocks: "观望" },
        methodology: ["跟踪盈利修正"],
        uncertainty: ["财报附件未解析"],
        source_message_ids: ["message-1", "message-2"],
      }],
      topic_discussions: [{
        title: "财报预期",
        summary: "频道围绕指引调整展开讨论。",
        viewpoints: [{
          author_id: "author-1",
          author_display: "作者甲",
          viewpoint: "等待确认",
          reasoning: "估值仍偏高。",
          operation_tendency: null,
          source_message_ids: ["message-1"],
        }],
        uncertainty: [],
        source_message_ids: ["message-1", "message-2"],
      }],
      warnings: [],
    }, { partial_failure: false });

    expect(result).toMatchObject({
      kind: "v1.1",
      asOf: "2099-01-02T09:30:00.000Z",
      authorCards: [{
        authorDisplay: "作者甲",
        marketTrend: "市场仍在观察政策落地。",
        stockJudgments: [{ subject: "ABC", judgment: "等待财报确认。", reasoning: "估值仍偏高。", evidenceCount: 1 }],
        marketTendency: null,
        stockTendency: "观望",
        methodology: ["跟踪盈利修正"],
        uncertainty: ["财报附件未解析"],
        evidenceCount: 2,
      }],
      topicDiscussions: [{
        title: "财报预期",
        overview: "频道围绕指引调整展开讨论。",
        viewpoints: [{ authorDisplay: "作者甲", viewpoint: "等待确认", reasoning: "估值仍偏高。", tendency: null, evidenceCount: 1 }],
        evidenceCount: 2,
      }],
    });
    expect(JSON.stringify(result)).not.toContain("author-1");
    expect(JSON.stringify(result)).not.toContain("message-1");
  });

  it("fails closed for malformed or unknown versioned output", () => {
    expect(presentSummary({ schema_version: "v1.1", author_cards: "not-an-array" }, {})).toEqual({ kind: "empty" });
    expect(presentSummary({ schema_version: "v2", topics: [] }, {})).toEqual({ kind: "empty" });
    expect(presentSummary({
      schema_version: "v1.1", natural_date: "2099-01-02", as_of: "2099-01-02T09:30:00.000Z", author_cards: [], topic_discussions: [], warnings: [], unexpected: true,
    }, {})).toEqual({ kind: "empty" });
  });

  it("fails closed when V1.1 media coverage lacks its required warning", () => {
    expect(presentSummary({
      schema_version: "v1.1",
      natural_date: "2099-01-02",
      as_of: "2099-01-02T09:30:00.000Z",
      author_cards: [],
      topic_discussions: [],
      warnings: [],
    }, { unparsed_media: true })).toEqual({ kind: "empty" });
  });
});
