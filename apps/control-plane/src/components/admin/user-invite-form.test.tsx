import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { UserInviteForm } from "./UserInviteForm";

describe("UserInviteForm", () => {
  it("places the per-creation duration control before the create action", () => {
    const html = renderToStaticMarkup(<UserInviteForm />);

    expect(html).toContain("有效时长（小时）");
    expect(html).toContain('value="24"');
    expect(html).toContain("生成后立即开始计时");
    expect(html).toContain("创建 24 小时邀请码");
    expect(html.indexOf("有效时长（小时）")).toBeLessThan(html.indexOf("创建 24 小时邀请码"));
  });
});
