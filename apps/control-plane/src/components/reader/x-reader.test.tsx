import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { XReader } from "./XReader";

const days = [{
  naturalDate: "2099-01-02",
  judgement: {
    visible: true,
    batches: [{
      cutoffAt: "2099-01-02T12:00:00.000Z", coverageStatus: "complete", status: "succeeded", revision: 2,
      stockViewpoints: [{ statement: "跨博主股票判断", supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [] }],
      marketIndustryViewpoints: [], strategyMindsetViewpoints: [{ statement: "一位博主建议保持观望。", actionIntent: "watch", actionScope: "高波动市场", conditions: ["等待趋势确认"], supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [] }], uncertainties: [], excludedSourceCount: 1, timedOutSourceCount: 0,
      includedSourceCount: 4, noNewSourceCount: 2,
      revisionHistory: [{
        revision: 1, coverageStatus: "partial",
        stockViewpoints: [{ statement: "较早修订判断", supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: ["旧不确定性"] }],
        marketIndustryViewpoints: [], uncertainties: [],
      }],
    }, {
      cutoffAt: "2099-01-02T08:00:00.000Z", coverageStatus: "partial", status: "succeeded", revision: 1,
      stockViewpoints: [], marketIndustryViewpoints: [], uncertainties: ["覆盖未完整"], excludedSourceCount: 1, timedOutSourceCount: 1,
      includedSourceCount: 0, noNewSourceCount: 0,
      revisionHistory: [],
    }],
  },
  bloggers: [{
    source: { sourceKey: "second", displayName: "Second Author" }, status: "succeeded", timedOut: false,
    segments: [{ occurredFromAt: "2099-01-02T11:00:00.000Z", occurredThroughAt: "2099-01-02T12:00:00.000Z", viewpoints: ["最新博主观点"], uncertainties: [], analyses: [] }, {
      occurredFromAt: "2099-01-02T07:00:00.000Z", occurredThroughAt: "2099-01-02T08:00:00.000Z", viewpoints: ["较早博主观点"], uncertainties: [], analyses: [],
    }],
  }, {
    source: { sourceKey: "third", displayName: "Third Author" }, status: "succeeded", timedOut: false,
    segments: [{ occurredFromAt: "2099-01-02T10:00:00.000Z", occurredThroughAt: "2099-01-02T11:00:00.000Z", viewpoints: ["第三位最新观点"], uncertainties: [], analyses: [] }, {
      occurredFromAt: "2099-01-02T06:00:00.000Z", occurredThroughAt: "2099-01-02T07:00:00.000Z", viewpoints: ["第三位较早观点"], uncertainties: [], analyses: [],
    }],
  }],
}, {
  naturalDate: "2099-01-01",
  judgement: { visible: true, batches: [] },
  bloggers: [{
    source: { sourceKey: "first", displayName: "First Author" }, status: "succeeded", timedOut: false,
    segments: [{ occurredFromAt: "2099-01-01T12:00:00.000Z", occurredThroughAt: "2099-01-01T12:00:00.000Z", viewpoints: ["首位博主观点"], uncertainties: [], analyses: [] }],
  }],
}];

describe("XReader", () => {
  it("renders each date as judgement first then stable one-column blogger sections", () => {
    const html = renderToStaticMarkup(<XReader days={days} initialNaturalDate="2099-01-02" />);

    expect(html.indexOf("2099-01-02")).toBeLessThan(html.indexOf("2099-01-01"));
    expect(html.indexOf("当日判断总结")).toBeLessThan(html.indexOf("单个博主观点"));
    expect(html.indexOf("跨博主股票判断")).toBeLessThan(html.indexOf('<header class="x-reader-author-strip"><p>博主</p><h3 class="x-reader-author">Second Author</h3></header>'));
    expect(html).toContain('class="x-reader-bloggers"');
    expect(html.match(/class="x-reader-blogger"/g) ?? []).toHaveLength(2);
    expect(html).not.toContain('class="reader-source-card"');
    expect(html).toContain('<details class="x-reader-judgement" open="">');
    expect(html).toContain('<details class="x-reader-judgement">');
    expect(html).toContain('<details class="x-reader-revision">');
    expect(html).toContain("较早修订判断");
    expect(html).toContain("修订版本 1");
    expect(html).toContain("输入覆盖：4 位博主观点已纳入，2 位无新增信息，1 位未纳入。");
    expect(html).toContain("下方主题仅列出直接支持或反对该主题的博主。");
    expect(html).toContain("投资策略与心态");
    expect(html).toContain("博主倾向：观望（高波动市场）");
    expect(html).toContain("条件：等待趋势确认");
    expect(html).toContain("采集超时，未形成判断");
    expect(html).toContain("其中 1 位因采集未在结算截止前完成。");
    expect(html.indexOf("最新博主观点")).toBeLessThan(html.indexOf("较早博主观点"));
    expect(html.indexOf('<header class="x-reader-author-strip"><p>博主</p><h3 class="x-reader-author">Second Author</h3></header>')).toBeLessThan(html.indexOf('<header class="x-reader-author-strip"><p>博主</p><h3 class="x-reader-author">Third Author</h3></header>'));
    expect(html.indexOf("第三位最新观点")).toBeLessThan(html.indexOf("第三位较早观点"));
    expect(html).toContain('<details class="x-reader-segment" open="">');
    expect(html).toContain('<details class="x-reader-segment">');
    expect(html).toContain('<option value="second">Second Author</option>');
    expect(html).toContain('<option value="2099-01-02" selected="">2099-01-02</option>');
  });

  it("shows the range explanation, but never a narrowed judgement, for one blogger", () => {
    const html = renderToStaticMarkup(<XReader days={days} initialSourceKey="second" initialNaturalDate="2099-01-02" />);

    expect(html).toContain("跨博主当日判断总结仅在全部博主视图展示。");
    expect(html).not.toContain("跨博主股票判断");
    expect(html).toContain("Second Author");
    expect(html).not.toContain("首位博主观点");
  });

  it("keeps the latest cutoff open even when pending while failed states show no fabricated body", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      naturalDate: "2099-01-03",
      judgement: { visible: true, batches: [{ cutoffAt: "2099-01-03T12:00:00.000Z", coverageStatus: null, status: "judgement_pending", revision: 0, stockViewpoints: [], marketIndustryViewpoints: [], uncertainties: [], includedSourceCount: 0, noNewSourceCount: 0, excludedSourceCount: 0, timedOutSourceCount: 0, revisionHistory: [] }, {
        cutoffAt: "2099-01-03T08:00:00.000Z", coverageStatus: "complete", status: "succeeded", revision: 1, stockViewpoints: [{ statement: "可见判断", supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties: [] }], marketIndustryViewpoints: [], uncertainties: [], includedSourceCount: 1, noNewSourceCount: 0, excludedSourceCount: 0, timedOutSourceCount: 0, revisionHistory: [] }, {
        cutoffAt: "2099-01-03T04:00:00.000Z", coverageStatus: null, status: "judgement_failed", revision: 0, stockViewpoints: [], marketIndustryViewpoints: [], uncertainties: [], includedSourceCount: 0, noNewSourceCount: 0, excludedSourceCount: 0, timedOutSourceCount: 0, revisionHistory: [] }] },
      bloggers: [],
    }]} initialNaturalDate="2099-01-03" />);

    expect(html).toContain("当日判断仍在处理中。");
    expect(html).toContain("当日判断未能完成，稍后会重试。");
    expect(html).not.toContain("本窗口没有新的可判断信息。");
    expect(html.indexOf('<details class="x-reader-judgement" open="">')).toBeLessThan(html.indexOf('<details class="x-reader-judgement">'));
    expect(html).toContain("可见判断");
  });

  it("renders batch-derived no-new, pending, failed, and excluded blogger placeholders", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      naturalDate: "2099-01-04", judgement: { visible: true, batches: [] },
      bloggers: [{ source: { sourceKey: "no-new", displayName: "No New" }, status: "no_new_messages", timedOut: false, segments: [] },
        { source: { sourceKey: "pending", displayName: "Pending" }, status: "processing", timedOut: false, segments: [] },
        { source: { sourceKey: "failed", displayName: "Failed" }, status: "failed", timedOut: false, segments: [] },
        { source: { sourceKey: "excluded", displayName: "Excluded" }, status: "partial_failure", timedOut: true, segments: [] }],
    }]} />);

    expect(html).toContain("已核实：截至当前时间没有新增消息。");
    expect(html).toContain("处理中：最新内容仍在整理");
    expect(html).toContain("更新失败：保留上次可用摘要");
    expect(html).toContain("采集超时：本机未在结算时间前完成采集。");
    expect(html).toContain("本批次未纳入该博主的完整信息。");
    expect(html).not.toContain("覆盖不完整：当前摘要可能未包含该时段的全部内容。");
  });

  it("does not render internal evidence, task, raw-content, provider, or local fields", () => {
    const unsafeDays = [{
      ...days[0],
      judgement: {
        visible: true,
        batches: [{
          ...days[0]!.judgement.batches[0]!,
          stockViewpoints: [{ statement: "安全展示", supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [] }],
          revisionHistory: [{
            revision: 1, coverageStatus: "complete", stockViewpoints: [{
              statement: "安全旧修订", supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [],
              analysis_ids: ["private-analysis"], raw_content: "FORBIDDEN_RAW_HISTORY",
            }], marketIndustryViewpoints: [], uncertainties: [], provider: "private-provider",
          }],
        }],
      },
    }];
    const html = renderToStaticMarkup(<XReader days={unsafeDays as never} />);

    expect(html).toContain("安全旧修订");
    for (const forbidden of ["analysis_ids", "evidence_post_ids", "task-", "raw post", "provider", "/Users/", "FORBIDDEN_RAW_HISTORY"]) expect(html).not.toContain(forbidden);
  });
});
