import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { nextXDisplayName, xCreationPayload, XSourceForm } from "./XSourceForm";

describe("XSourceForm", () => {
  it("renders an account-first X form without technical configuration inputs", () => {
    const html = renderToStaticMarkup(<XSourceForm />);

    expect(html).toContain("X 账号");
    expect(html).toContain("展示名称");
    expect(html).toContain("标准采集（推荐）");
    expect(html).toContain("系统自动维护");
    expect(html).not.toContain("内部来源标识");
    expect(html).not.toContain("参数版本");
    expect(html).not.toContain('name="source_key"');
    expect(html).not.toContain('name="parameter_version"');
  });

  it("suggests an X display name until the administrator edits it", () => {
    expect(nextXDisplayName({ requestedHandle: "@ShanghaoJin", currentDisplayName: "", displayNameEdited: false })).toBe("@ShanghaoJin");
    expect(nextXDisplayName({ requestedHandle: "new_handle", currentDisplayName: "赫曼·金", displayNameEdited: true })).toBe("赫曼·金");
  });

  it("builds a creation request from only the public X fields", () => {
    expect(xCreationPayload("赫曼·金", " @ShanghaoJin ")).toEqual({
      display_name: "赫曼·金",
      requested_handle: "ShanghaoJin",
    });
  });
});
