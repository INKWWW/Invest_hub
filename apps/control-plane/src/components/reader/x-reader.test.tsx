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
      marketIndustryViewpoints: [], uncertainties: [], excludedSourceCount: 0,
    }, {
      cutoffAt: "2099-01-02T08:00:00.000Z", coverageStatus: "partial", status: "succeeded", revision: 1,
      stockViewpoints: [], marketIndustryViewpoints: [], uncertainties: ["覆盖未完整"], excludedSourceCount: 1,
    }],
  },
  bloggers: [{
    source: { sourceKey: "second", displayName: "Second Author" }, status: "succeeded",
    segments: [{ occurredFromAt: "2099-01-02T11:00:00.000Z", occurredThroughAt: "2099-01-02T12:00:00.000Z", viewpoints: ["最新博主观点"], uncertainties: [], analyses: [] }, {
      occurredFromAt: "2099-01-02T07:00:00.000Z", occurredThroughAt: "2099-01-02T08:00:00.000Z", viewpoints: ["较早博主观点"], uncertainties: [], analyses: [],
    }],
  }, {
    source: { sourceKey: "third", displayName: "Third Author" }, status: "succeeded",
    segments: [{ occurredFromAt: "2099-01-02T10:00:00.000Z", occurredThroughAt: "2099-01-02T11:00:00.000Z", viewpoints: ["第三位最新观点"], uncertainties: [], analyses: [] }, {
      occurredFromAt: "2099-01-02T06:00:00.000Z", occurredThroughAt: "2099-01-02T07:00:00.000Z", viewpoints: ["第三位较早观点"], uncertainties: [], analyses: [],
    }],
  }],
}, {
  naturalDate: "2099-01-01",
  judgement: { visible: true, batches: [] },
  bloggers: [{
    source: { sourceKey: "first", displayName: "First Author" }, status: "succeeded",
    segments: [{ occurredFromAt: "2099-01-01T12:00:00.000Z", occurredThroughAt: "2099-01-01T12:00:00.000Z", viewpoints: ["首位博主观点"], uncertainties: [], analyses: [] }],
  }],
}];

describe("XReader", () => {
  it("renders each date as judgement first then stable one-column blogger sections", () => {
    const html = renderToStaticMarkup(<XReader days={days} initialNaturalDate="2099-01-02" />);

    expect(html.indexOf("2099-01-02")).toBeLessThan(html.indexOf("2099-01-01"));
    expect(html.indexOf("当日判断总结")).toBeLessThan(html.indexOf("单个博主观点"));
    expect(html.indexOf("跨博主股票判断")).toBeLessThan(html.indexOf('<h3 class="x-reader-author">Second Author</h3>'));
    expect(html).toContain('class="x-reader-bloggers"');
    expect(html.match(/class="x-reader-blogger"/g) ?? []).toHaveLength(2);
    expect(html).not.toContain('class="reader-source-card"');
    expect(html).toContain('<details class="x-reader-judgement" open="">');
    expect(html).toContain('<details class="x-reader-judgement">');
    expect(html.indexOf("最新博主观点")).toBeLessThan(html.indexOf("较早博主观点"));
    expect(html.indexOf('<h3 class="x-reader-author">Second Author</h3>')).toBeLessThan(html.indexOf('<h3 class="x-reader-author">Third Author</h3>'));
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

  it("keeps the newest completed judgement open while pending and failed states show no fabricated body", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      naturalDate: "2099-01-03",
      judgement: { visible: true, batches: [{ cutoffAt: "2099-01-03T12:00:00.000Z", coverageStatus: "no_new_information", status: "judgement_pending", revision: 0, stockViewpoints: [], marketIndustryViewpoints: [], uncertainties: [], excludedSourceCount: 0 }, {
        cutoffAt: "2099-01-03T08:00:00.000Z", coverageStatus: "complete", status: "succeeded", revision: 1, stockViewpoints: [{ statement: "可见判断", supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties: [] }], marketIndustryViewpoints: [], uncertainties: [], excludedSourceCount: 0 }, {
        cutoffAt: "2099-01-03T04:00:00.000Z", coverageStatus: "no_new_information", status: "judgement_failed", revision: 0, stockViewpoints: [], marketIndustryViewpoints: [], uncertainties: [], excludedSourceCount: 0 }] },
      bloggers: [],
    }]} initialNaturalDate="2099-01-03" />);

    expect(html).toContain("当日判断仍在处理中。");
    expect(html).toContain("当日判断未能完成，稍后会重试。");
    expect(html.indexOf('<details class="x-reader-judgement">')).toBeLessThan(html.indexOf('<details class="x-reader-judgement" open="">'));
    expect(html).toContain("可见判断");
  });

  it("does not render internal evidence, task, raw-content, provider, or local fields", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      ...days[0],
      judgement: {
        visible: true,
        batches: [{ ...days[0]!.judgement.batches[0]!, stockViewpoints: [{ statement: "安全展示", supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [] }] }],
      },
    }]} />);

    for (const forbidden of ["analysis_ids", "evidence_post_ids", "task-", "raw post", "provider", "/Users/"]) expect(html).not.toContain(forbidden);
  });
});
