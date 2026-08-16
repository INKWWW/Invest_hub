import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { XReader } from "./XReader";

const v5Day = {
  naturalDate: "2099-01-06",
  judgement: {
    visible: true,
    batches: [{
      cutoffAt: "2099-01-06T12:00:00.000Z",
      coverageStatus: "partial",
      status: "succeeded",
      revision: 3,
      presentationKind: "v5",
      stockViewpoints: [],
      marketIndustryViewpoints: [],
      strategyMindsetViewpoints: [],
      aiSynthesis: {
        crossBloggerIntegrations: [{
          headline: "跨博主都把 AI 基建链条当作近期主线。",
          synthesis: "两位博主都围绕景气延续展开，但一位更偏向提前布局，另一位更强调验证节奏。",
          commonPoints: [{ statement: "两位博主都把 AI 基建需求变化当作观察主线。", displayNames: ["Alpha", "Beta"] }],
          conflictPoints: [{
            issue: "是否已经进入可以更积极配置的阶段。",
            positions: [
              { position: "Alpha 更倾向在确认主线后逐步提前布局。", displayNames: ["Alpha"] },
              { position: "Beta 仍希望先观察兑现节奏再决定是否扩大仓位。", displayNames: ["Beta"] },
            ],
          }],
          uncertainties: ["跨博主整合仍受未纳入窗口限制。"],
        }],
        aiAssessments: [{
          headline: "单博主的节奏主线仍值得重点跟踪。",
          judgement: "AI 认为这条节奏 thesis 虽然目前只由单一博主支持，但仍足以影响后续判断。",
          importanceReason: "它决定是否把当前主线从观察提升为更明确的配置判断。",
          reasoning: "该博主给出的链条约束和时间节奏更完整，因此值得作为 AI 研判单独保留。",
          keyAssumptions: ["订单兑现仍按当前节奏推进。"],
          risks: ["若兑现节奏继续延后，判断可能需要下修。"],
          watchVariables: ["订单兑现节奏", "库存变化"],
          uncertainties: ["AI 研判仅覆盖已纳入窗口。"],
        }],
      },
      securityIndustryTheses: [{
        headline: "两位博主都认为 AI 基建主线仍在延续。",
        synthesis: "两位博主都延续看多 AI 基建主线，但 Alpha 更强调可以逐步建立观察仓位。",
        scenarioBranches: [{ condition: "若新增需求继续兑现。", outcome: "产业链景气判断将进一步强化。", uncertainties: ["情景兑现仍需观察。"] }],
        attributedActions: [{
          displayName: "Alpha",
          actionIntent: "build_position",
          actionScope: "AI 基础设施链条龙头",
          actionScopeStatus: "specified",
          conditions: ["若新增需求继续兑现。"],
          uncertainties: ["博主仍保留节奏不确定性。"],
        }],
        supportingDisplayNames: ["Alpha", "Beta"],
        dissentingDisplayNames: [],
        uncertainties: ["主线仍受需求验证影响。"],
      }],
      marketStructureTheses: [{
        headline: "有博主认为当前市场节奏仍受兑现约束。",
        synthesis: "这条 thesis 主要来自单一博主，因此需要持续验证节奏是否改善。",
        scenarioBranches: [{ condition: "若兑现节奏开始改善。", outcome: "市场结构判断将逐步修复。", uncertainties: [] }],
        attributedActions: [{
          displayName: "Alpha",
          actionIntent: "hold",
          actionScope: "观察仓位",
          actionScopeStatus: "specified",
          conditions: ["等待兑现信号"],
          uncertainties: [],
        }],
        supportingDisplayNames: ["Alpha"],
        dissentingDisplayNames: [],
        uncertainties: ["目前仍缺少第二位博主确认。"],
      }],
      strategyMindsetTheses: [{
        headline: "策略上更适合保持耐心而非追涨。",
        synthesis: "博主更倾向在信号继续清晰前保持耐心，避免在高波动下追价。",
        scenarioBranches: [{ condition: "若波动继续放大。", outcome: "策略上继续保持耐心。", uncertainties: [] }],
        attributedActions: [{
          displayName: "Beta",
          actionIntent: "watch",
          actionScope: "当前仓位",
          actionScopeStatus: "specified",
          conditions: ["等待趋势确认。"],
          uncertainties: [],
        }],
        supportingDisplayNames: ["Beta"],
        dissentingDisplayNames: [],
        uncertainties: [],
      }],
      uncertainties: ["仅基于当日已完成采集的博主窗口，仍可能遗漏尚未纳入的覆盖范围。"],
      includedSourceCount: 2,
      noNewSourceCount: 1,
      excludedSourceCount: 1,
      timedOutSourceCount: 1,
      revisionHistory: [{
        revision: 2,
        coverageStatus: "complete",
        presentationKind: "legacy",
        stockViewpoints: [{ statement: "旧版原子观点仍只在 legacy 修订中展示。", supportingDisplayNames: ["Alpha"], dissentingDisplayNames: [], uncertainties: [] }],
        marketIndustryViewpoints: [],
        strategyMindsetViewpoints: [],
        uncertainties: [],
      }],
    }],
  },
  bloggers: [{
    source: { sourceKey: "alpha", displayName: "Alpha" },
    status: "succeeded",
    timedOut: false,
    lateArrival: false,
    collectionGaps: [],
    segments: [{
      occurredFromAt: "2099-01-06T10:00:00.000Z",
      occurredThroughAt: "2099-01-06T12:00:00.000Z",
      viewpoints: ["Alpha 最新博主观点"],
      uncertainties: [],
      analyses: [],
    }],
  }, {
    source: { sourceKey: "beta", displayName: "Beta" },
    status: "succeeded",
    timedOut: false,
    lateArrival: false,
    collectionGaps: [],
    segments: [{
      occurredFromAt: "2099-01-06T09:00:00.000Z",
      occurredThroughAt: "2099-01-06T11:00:00.000Z",
      viewpoints: ["Beta 最新博主观点"],
      uncertainties: [],
      analyses: [],
    }],
  }],
} as const;

function renderV5Day(dayOverrides?: Record<string, unknown>) {
  return renderToStaticMarkup(<XReader days={[{
    ...v5Day,
    ...(dayOverrides ?? {}),
    judgement: {
      ...v5Day.judgement,
      ...((dayOverrides?.judgement as Record<string, unknown> | undefined) ?? {}),
      batches: [({
        ...v5Day.judgement.batches[0],
        ...((((dayOverrides?.judgement as { batches?: Array<Record<string, unknown>> } | undefined)?.batches?.[0]) ?? {})),
      })],
    },
  }] as never} initialNaturalDate="2099-01-06" />);
}

function thesisCardByHeadline(html: string, headline: string) {
  const thesisCards = [...html.matchAll(/<article data-testid="x-thesis-card"[^>]*>([\s\S]*?)<\/article>/g)].map((match) => match[1]);
  const card = thesisCards.find((candidate) => candidate.includes(`<h4 class="x-thesis-headline">${headline}</h4>`));
  if (!card) throw new Error(`Missing thesis card for headline: ${headline}`);
  return card;
}

const days = [{
  naturalDate: "2099-01-02",
  judgement: {
    visible: true,
    batches: [{
      cutoffAt: "2099-01-02T12:00:00.000Z", coverageStatus: "complete", status: "succeeded", revision: 2,
      stockViewpoints: [{ statement: "跨博主股票判断", supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [] }],
      marketIndustryViewpoints: [{ statement: "市场结构仍需观察。", supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [] }], strategyMindsetViewpoints: [{ statement: "一位博主建议保持观望。", actionIntent: "watch", actionScope: "高波动市场", conditions: ["等待趋势确认"], supportingDisplayNames: ["Second Author"], dissentingDisplayNames: [], uncertainties: [] }], uncertainties: [], excludedSourceCount: 1, timedOutSourceCount: 0,
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
    source: { sourceKey: "second", displayName: "Second Author" }, status: "succeeded", timedOut: false, lateArrival: false,
    collectionGaps: [{ startAt: "2099-01-02T04:00:00.000Z", endAt: "2099-01-02T08:00:00.000Z" }],
    segments: [{ occurredFromAt: "2099-01-02T11:00:00.000Z", occurredThroughAt: "2099-01-02T12:00:00.000Z", viewpoints: ["最新博主观点"], securityIndustryViewpoints: [{ statement: "测试标的具备修复条件", actionIntent: "buy", actionScope: "测试标的", conditions: ["等待趋势确认"], supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties: ["缺少外部确认"] }], marketStructureViewpoints: [{ statement: "市场结构仍处于观察期", actionIntent: "watch", actionScope: "市场结构", conditions: ["等待宽度改善"], supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties: [] }], strategyMindsetViewpoints: [{ statement: "策略上保持耐心", actionIntent: "watch", actionScope: "当前仓位", conditions: [], supportingDisplayNames: [], dissentingDisplayNames: [], uncertainties: [] }], uncertainties: [], analyses: [{ postLink: "https://x.example/posts/analysis-1", postedAt: "2099-08-07T19:05:00.000Z", postType: "quote", bloggerViewpoint: "帖子中的降息观点", actionIntent: "buy", actionScope: "测试标的", conditions: ["等待数据确认"], arguments: ["博主此前已持续提及该判断"], quotedPostViewpoint: "引用帖的补充判断", uncertainties: ["未说明完整时间范围"] }, { postLink: "https://x.example/posts/analysis-legacy", bloggerViewpoint: "旧版帖子观点", actionIntent: null, conditions: [], arguments: [], quotedPostViewpoint: null, uncertainties: [] }] }, {
      occurredFromAt: "2099-01-02T07:00:00.000Z", occurredThroughAt: "2099-01-02T08:00:00.000Z", viewpoints: ["较早博主观点"], uncertainties: [], analyses: [],
    }],
  }, {
    source: { sourceKey: "third", displayName: "Third Author" }, status: "succeeded", timedOut: false, lateArrival: false, collectionGaps: [],
    segments: [{ occurredFromAt: "2099-01-02T10:00:00.000Z", occurredThroughAt: "2099-01-02T11:00:00.000Z", viewpoints: ["第三位最新观点"], uncertainties: [], analyses: [] }, {
      occurredFromAt: "2099-01-02T06:00:00.000Z", occurredThroughAt: "2099-01-02T07:00:00.000Z", viewpoints: ["第三位较早观点"], uncertainties: [], analyses: [],
    }],
  }],
}, {
  naturalDate: "2099-01-01",
  judgement: { visible: true, batches: [] },
  bloggers: [{
    source: { sourceKey: "first", displayName: "First Author" }, status: "succeeded", timedOut: false, lateArrival: false, collectionGaps: [],
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
    expect(html).toContain("操作表述：观望（高波动市场）");
    expect(html).not.toContain("个股与产业观点");
    expect(html).not.toContain("市场结构观点");
    expect(html).toContain('class="x-reader-viewpoint-group x-reader-viewpoint-group--security"');
    expect(html).toContain('class="x-reader-viewpoint-group x-reader-viewpoint-group--market"');
    expect(html).toContain('class="x-reader-viewpoint-group x-reader-viewpoint-group--strategy"');
    expect(html).toContain('class="topic-card"');
    expect(html).toContain("观点 01");
    expect(html).toContain('class="x-reader-viewpoint-statement"');
    expect(html).toContain("操作表述");
    expect(html).toContain("买入（测试标的）");
    expect(html).toContain("条件");
    expect(html).toContain("等待趋势确认");
    expect(html).toContain('<details class="x-analysis" open="">');
    expect(html).toContain('href="https://x.example/posts/analysis-1"');
    expect(html).toContain(">08-08 03:05 · 引用帖</a></summary>");
    expect(html).toContain('href="https://x.example/posts/analysis-legacy"');
    expect(html).toContain(">原始 X 帖子</a></summary>");
    expect(html).toContain("帖子中的降息观点");
    expect(html).toContain("买入（测试标的）");
    expect(html).toContain("等待数据确认");
    expect(html).toContain("博主此前已持续提及该判断");
    expect(html).toContain("引用帖的补充判断");
    expect(html).toContain("不确定性：未说明完整时间范围");
    expect(html).toContain("采集超时，未形成判断");
    expect(html).toContain("采集缺失：01月02日 12:00–16:00");
    expect(html).toContain("其中 1 位因采集未在结算截止前完成。");
    const bloggerStart = html.indexOf('<section class="x-reader-blogger">');
    const nextBloggerStart = html.indexOf('<section class="x-reader-blogger">', bloggerStart + 1);
    const firstBloggerHtml = html.slice(bloggerStart, nextBloggerStart === -1 ? undefined : nextBloggerStart);
    expect(firstBloggerHtml).not.toContain("个股与产业观点");
    expect(firstBloggerHtml).not.toContain("市场结构观点");
    expect(firstBloggerHtml).not.toContain("投资策略与心态");
    expect(html.indexOf("最新博主观点")).toBeLessThan(html.indexOf("较早博主观点"));
    expect(html.indexOf('<header class="x-reader-author-strip"><p>博主</p><h3 class="x-reader-author">Second Author</h3></header>')).toBeLessThan(html.indexOf('<header class="x-reader-author-strip"><p>博主</p><h3 class="x-reader-author">Third Author</h3></header>'));
    expect(html.indexOf("第三位最新观点")).toBeLessThan(html.indexOf("第三位较早观点"));
    expect(html).toContain('<details class="x-reader-segment" open="">');
    expect(html).toContain('<details class="x-reader-segment">');
    expect(html).toContain('<option value="second">Second Author</option>');
    expect(html).toContain('<option value="2099-01-02" selected="">2099-01-02</option>');
  });

  it("labels late-arrival content without changing normal blogger cards", () => {
    const lateDays = [{
      ...days[0],
      bloggers: days[0].bloggers.map((blogger) => blogger.source.sourceKey === "second" ? { ...blogger, lateArrival: true } : blogger),
    }, ...days.slice(1)];
    const html = renderToStaticMarkup(<XReader days={lateDays} initialNaturalDate="2099-01-02" />);
    const normalHtml = renderToStaticMarkup(<XReader days={days} initialNaturalDate="2099-01-02" />);

    expect(html).toContain("后补采集：该内容未纳入原跨博主日报。");
    expect(html).toContain("采集缺失：01月02日 12:00–16:00");
    expect(normalHtml).not.toContain("后补采集：该内容未纳入原跨博主日报。");
  });

  it("shows the range explanation, but never a narrowed judgement, for one blogger", () => {
    const html = renderToStaticMarkup(<XReader days={days} initialSourceKey="second" initialNaturalDate="2099-01-02" />);

    expect(html).toContain("跨博主当日判断总结仅在全部博主视图展示。");
    expect(html).not.toContain("跨博主股票判断");
    expect(html).toContain("Second Author");
    expect(html).not.toContain("首位博主观点");
  });

  it("renders v5 synthesis before full theses while preserving legacy revision history and blogger timeline", () => {
    const html = renderV5Day();

    expect(html.indexOf("输入覆盖")).toBeLessThan(html.indexOf("AI 综合研判"));
    expect(html.indexOf("跨博主观点整合")).toBeLessThan(html.indexOf("AI 研判"));
    expect(html.indexOf("AI 综合研判")).toBeLessThan(html.indexOf("个股与产业判断"));
    expect(html.indexOf("个股与产业判断")).toBeLessThan(html.indexOf("市场结构判断"));
    expect(html.indexOf("市场结构判断")).toBeLessThan(html.indexOf("投资策略与心态"));
    expect(html.indexOf("投资策略与心态")).toBeLessThan(html.indexOf("批次整体不确定性"));
    expect(html.indexOf("批次整体不确定性")).toBeLessThan(html.indexOf("单个博主观点"));
    expect(html).toContain("博主观点归纳");
    expect(html).toContain("AI 分析判断");
    expect(html).toContain("仅基于本批次已纳入的博主观点，不获取外部信息，不构成交易建议");
    expect(html).toContain("Alpha");
    expect(html).toContain("Beta");
    expect(html).toContain("情景 A");
    expect(html).toContain("若新增需求继续兑现。");
    expect(html).toContain("操作表述");
    expect(html).toContain("建仓（AI 基础设施链条龙头）");
    expect(html).toContain("观望（当前仓位）");
    expect(html).toContain("两位博主都认为 AI 基建主线仍在延续。");
    expect(html).toContain("有博主认为当前市场节奏仍受兑现约束。");
    expect(html).toContain("策略上更适合保持耐心而非追涨。");
    expect(html).toContain("仅基于当日已完成采集的博主窗口，仍可能遗漏尚未纳入的覆盖范围。");
    expect(html).toContain("旧版原子观点仍只在 legacy 修订中展示。");
  });

  it("scopes every thesis card's headline, synthesis, scenario, and action elements", () => {
    const html = renderV5Day();
    const thesisCards = [...html.matchAll(/<article data-testid="x-thesis-card"[^>]*>([\s\S]*?)<\/article>/g)].map((match) => match[1]);

    expect(thesisCards).toHaveLength(3);
    for (const thesisCard of thesisCards) {
      expect(thesisCard).toMatch(/<h4 class="x-thesis-headline">[\s\S]+?<\/h4>/);
      expect(thesisCard).toMatch(/<p class="x-thesis-synthesis">[\s\S]+?<\/p>/);
      expect(thesisCard).toMatch(/data-testid="x-thesis-scenario"/);
      expect(thesisCard).toMatch(/data-testid="x-thesis-actions"[\s\S]+?操作表述/);
    }
    expect(html.match(/data-testid="x-thesis-scenario"/g) ?? []).toHaveLength(thesisCards.length);
    expect(html.match(/data-testid="x-thesis-actions"/g) ?? []).toHaveLength(thesisCards.length);
  });

  it("keeps concrete scenarios and attributed actions inside the titled thesis card", () => {
    const html = renderV5Day();
    const infrastructureCard = thesisCardByHeadline(html, "两位博主都认为 AI 基建主线仍在延续。");
    const marketRhythmCard = thesisCardByHeadline(html, "有博主认为当前市场节奏仍受兑现约束。");

    expect(infrastructureCard).toContain("若新增需求继续兑现。");
    expect(infrastructureCard).toContain("Alpha");
    expect(infrastructureCard).toContain("建仓（AI 基础设施链条龙头）");
    expect(marketRhythmCard).toContain("若兑现节奏开始改善。");
    expect(marketRhythmCard).toContain("Alpha");
    expect(marketRhythmCard).toContain("持有（观察仓位）");
    expect(infrastructureCard).not.toContain("若兑现节奏开始改善。");
    expect(infrastructureCard).not.toContain("持有（观察仓位）");
    expect(marketRhythmCard).not.toContain("若新增需求继续兑现。");
    expect(marketRhythmCard).not.toContain("建仓（AI 基础设施链条龙头）");
  });

  it("keeps the strategy thesis scenario, outcome, and Beta action scoped to its titled card", () => {
    const html = renderV5Day();
    const strategyCard = thesisCardByHeadline(html, "策略上更适合保持耐心而非追涨。");
    const securityCard = thesisCardByHeadline(html, "两位博主都认为 AI 基建主线仍在延续。");
    const marketCard = thesisCardByHeadline(html, "有博主认为当前市场节奏仍受兑现约束。");
    const strategyEvidence = ["若波动继续放大。", "策略上继续保持耐心。", "观望（当前仓位）"];
    const securityEvidence = ["若新增需求继续兑现。", "建仓（AI 基础设施链条龙头）"];
    const marketEvidence = ["若兑现节奏开始改善。", "持有（观察仓位）"];

    expect(strategyCard).toContain("若波动继续放大。");
    expect(strategyCard).toContain("策略上继续保持耐心。");
    expect(strategyCard).toContain("Beta");
    expect(strategyCard).toContain("观望（当前仓位）");
    for (const otherCard of [securityCard, marketCard]) {
      for (const evidence of strategyEvidence) expect(otherCard).not.toContain(evidence);
    }
    for (const evidence of [...securityEvidence, ...marketEvidence]) expect(strategyCard).not.toContain(evidence);
  });

  it("scopes common and conflicting blogger names to their integration evidence cells", () => {
    const html = renderV5Day();
    const integrationCards = [...html.matchAll(/<article data-testid="x-ai-integration-card"[^>]*>([\s\S]*?)<\/article>/g)].map((match) => match[1]);
    const commonCell = integrationCards[0]?.match(/<section data-testid="x-ai-common-points"[^>]*>([\s\S]*?)<\/section>/)?.[1];
    const conflictPositions = [...(integrationCards[0]?.matchAll(/<li data-testid="x-ai-conflict-position"[^>]*>([\s\S]*?)<\/li>/g) ?? [])].map((match) => match[1]);

    expect(integrationCards).toHaveLength(1);
    expect(integrationCards[0]).toContain("Alpha");
    expect(integrationCards[0]).toContain("Beta");
    expect(commonCell).toContain("Alpha");
    expect(commonCell).toContain("Beta");
    expect(conflictPositions).toHaveLength(2);
    expect(conflictPositions[0]).toContain("Alpha");
    expect(conflictPositions[0]).not.toContain("Beta");
    expect(conflictPositions[1]).toContain("Beta");
    expect(conflictPositions[1]).not.toContain("Alpha");
  });

  it("shows only the integration child when assessments are empty", () => {
    const html = renderV5Day({
      judgement: {
        batches: [{
          aiSynthesis: {
            ...v5Day.judgement.batches[0].aiSynthesis,
            aiAssessments: [],
          },
        }],
      },
    });

    expect(html).toContain("AI 综合研判");
    expect(html).toContain("跨博主观点整合");
    expect(html).not.toContain("AI 研判");
  });

  it("shows only the assessment child when integrations are empty", () => {
    const html = renderV5Day({
      judgement: {
        batches: [{
          aiSynthesis: {
            ...v5Day.judgement.batches[0].aiSynthesis,
            crossBloggerIntegrations: [],
          },
        }],
      },
    });

    expect(html).toContain("AI 综合研判");
    expect(html).not.toContain("跨博主观点整合");
    expect(html).toContain("AI 研判");
  });

  it("hides the whole synthesis container only when both child arrays are empty", () => {
    const html = renderV5Day({
      judgement: {
        batches: [{
          aiSynthesis: {
            crossBloggerIntegrations: [],
            aiAssessments: [],
          },
        }],
      },
    });

    expect(html).not.toContain("AI 综合研判");
    expect(html).not.toContain("跨博主观点整合");
    expect(html).not.toContain("AI 研判");
    expect(html).toContain("个股与产业判断");
    expect(html).toContain("单个博主观点");
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
    expect(html).toContain("当日判断未能完成，已停止自动重试。");
    expect(html).not.toContain("本窗口没有新的可判断信息。");
    expect(html.indexOf('<details class="x-reader-judgement" open="">')).toBeLessThan(html.indexOf('<details class="x-reader-judgement">'));
    expect(html).toContain("可见判断");
  });

  it("keeps an original failed judgement visible before its non-scheduled verification recovery", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      naturalDate: "2099-01-05",
      judgement: { visible: true, batches: [{
        cutoffAt: "2099-01-05T08:00:00.000Z", coverageStatus: null, status: "judgement_failed", revision: 0,
        stockViewpoints: [], marketIndustryViewpoints: [], strategyMindsetViewpoints: [], uncertainties: [], includedSourceCount: 3, noNewSourceCount: 0, excludedSourceCount: 0, timedOutSourceCount: 0, revisionHistory: [],
        verificationRecovery: {
          stockViewpoints: [{ statement: "恢复后的判断", actionIntent: "watch", actionScope: "测试标的", conditions: [], supportingDisplayNames: ["Alpha"], dissentingDisplayNames: [], uncertainties: [] }],
          marketIndustryViewpoints: [], strategyMindsetViewpoints: [], uncertainties: [],
        },
      }] }, bloggers: [],
    }]} initialNaturalDate="2099-01-05" />);

    expect(html).toContain("判断失败");
    expect(html).toContain("当日判断未能完成，已停止自动重试。");
    expect(html).toContain("验证恢复（非定时任务）");
    expect(html).toContain("恢复后的判断");
    expect(html.indexOf("当日判断未能完成，已停止自动重试。")).toBeLessThan(html.indexOf("验证恢复（非定时任务）"));
    for (const forbidden of ["analysis_ids", "evidence_post_ids", "replay_id", "prompt_version", "provider", "raw_content"]) expect(html).not.toContain(forbidden);
  });

  it("renders batch-derived no-new, pending, failed, and excluded blogger placeholders", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      naturalDate: "2099-01-04", judgement: { visible: true, batches: [] },
      bloggers: [{ source: { sourceKey: "no-new", displayName: "No New" }, status: "no_new_messages", timedOut: false, lateArrival: false, collectionGaps: [], segments: [] },
        { source: { sourceKey: "pending", displayName: "Pending" }, status: "processing", timedOut: false, lateArrival: false, collectionGaps: [], segments: [] },
        { source: { sourceKey: "failed", displayName: "Failed" }, status: "failed", timedOut: false, lateArrival: false, collectionGaps: [], segments: [] },
        { source: { sourceKey: "excluded", displayName: "Excluded" }, status: "partial_failure", timedOut: true, lateArrival: false, collectionGaps: [], segments: [] }],
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
