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
    expect(readerStatusLabel("processing")).toContain("处理中");
    expect(readerStatusLabel("partial_failure")).toContain("覆盖不完整");
    expect(readerStatusLabel("retryable_failed")).toContain("可重试失败");
    expect(readerStatusLabel("failed")).toContain("失败");
    expect(readerStatusLabel("no_new_messages")).toContain("没有新增消息");
  });

  it("renders V1.1 summary-first content without raw evidence and keeps refresh admin-only", () => {
    const renderedDays: ReaderDay[] = [{
      source: { sourceKey: "source-a", displayName: "Source A" },
      naturalDate: "2099-01-02",
      status: "succeeded",
      dailySummary: {
        version: 1,
        presentation: {
          kind: "v1.1",
          asOf: "2099-01-02T09:00:00.000Z",
          authorCards: [{ authorDisplay: "作者甲", marketTrend: "趋势等待确认", stockJudgments: [], marketTendency: null, stockTendency: null, methodology: [], uncertainty: [], evidenceCount: 2 }],
          topicDiscussions: [{ title: "Earnings", overview: "Guidance changed.", viewpoints: [], uncertainty: [], evidenceCount: 2 }],
          warnings: ["存在未解析媒体"],
        },
        history: [],
      },
      batches: [{
        presentation: { kind: "legacy", topics: [], warnings: [], mediaUnparsed: false },
      }],
    }];

    const ordinary = renderToStaticMarkup(<DiscordReader days={renderedDays} />);
    const admin = renderToStaticMarkup(<DiscordReader days={renderedDays} manualRefreshSources={{ "source-a": "source-private-id" }} />);

    expect(ordinary).toContain("截至 2099/01/02 17:00");
    expect(ordinary).toContain("作者甲");
    expect(ordinary).toContain("未表达");
    expect(ordinary).toContain("频道话题");
    expect(ordinary).toContain("存在未解析媒体");
    expect(ordinary).toContain("批次摘要");
    expect(ordinary).toContain("<details open=\"\">");
    expect(ordinary).toContain("频道");
    expect(ordinary).toContain("日期");
    expect(ordinary).not.toContain("更新至当前时间");
    expect(ordinary).not.toContain("source-private-id");
    expect(admin).toContain("更新至当前时间");
    expect(ordinary).not.toContain("Evidence-backed messages");
    expect(ordinary).not.toContain("message-1");
    expect(ordinary).not.toContain("author-1");
    expect(ordinary).not.toContain("source_message_ids");
  });

  it("keeps the 375px reader DOM summary-only", () => {
    const viewportWidth = 375;
    const mobileDays: ReaderDay[] = [{
      source: { sourceKey: "source-a", displayName: "Source A" },
      naturalDate: "2099-01-02",
      status: "succeeded",
      dailySummary: { version: 1, presentation: { kind: "legacy", topics: [], warnings: [], mediaUnparsed: false }, history: [] },
      batches: [],
    }];

    const mobile = renderToStaticMarkup(<DiscordReader days={mobileDays} />);

    expect(viewportWidth).toBe(375);
    expect(mobile).toContain("批次摘要");
    expect(mobile).not.toContain("Evidence-backed messages");
    expect(mobile).not.toContain("证据消息");
  });
});
