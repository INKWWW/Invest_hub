import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { discordCreationPayload, SourceCreateForm } from "./SourceCreateForm";

describe("SourceCreateForm", () => {
  it("renders only the Discord source information an administrator understands", () => {
    const html = renderToStaticMarkup(<SourceCreateForm />);

    expect(html).toContain("显示名称（社区名 · 频道名）");
    expect(html).toContain("标准采集（推荐）");
    expect(html).toContain("系统自动维护");
    expect(html).not.toContain("内部来源标识");
    expect(html).not.toContain("参数版本");
    expect(html).not.toContain('name="source_key"');
    expect(html).not.toContain('name="parameter_version"');
  });

  it("builds a creation request from only the display name", () => {
    expect(discordCreationPayload("研究社区 · #美股讨论")).toEqual({ display_name: "研究社区 · #美股讨论" });
  });
});
