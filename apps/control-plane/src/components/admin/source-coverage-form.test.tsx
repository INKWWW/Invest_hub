import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { SourceCoverageForm, coverageBoundaryInstant } from "./SourceCoverageForm";

describe("SourceCoverageForm", () => {
  it("creates an explicit Shanghai boundary from an administrator-selected date and allowed time", () => {
    expect(coverageBoundaryInstant("2026-07-22", "00:00")).toBe("2026-07-22T00:00:00+08:00");
    expect(coverageBoundaryInstant("2026-07-22", "20:50")).toBe("2026-07-22T20:50:00+08:00");

    const html = renderToStaticMarkup(<SourceCoverageForm sourceId="source-private-id" />);
    expect(html).toContain("首次采集范围");
    expect(html).toContain("上海时间边界");
    expect(html).toContain("00:00");
    expect(html).toContain("08:00");
    expect(html).toContain("16:00");
    expect(html).toContain("20:50");
    expect(html).toContain("初始化采集范围");
    expect(html).toContain('placeholder="YYYY-MM-DD"');
    expect(html).toContain('inputMode="numeric"');
    expect(html).not.toContain('type="date"');
    expect(html).not.toContain("source-private-id");
    expect(html).not.toContain("max_pages");
  });
});
