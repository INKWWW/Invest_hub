import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import InvitePage from "./page";

describe("invited registration page", () => {
  it("renders exactly the four Chinese registration inputs and password guidance", () => {
    const html = renderToStaticMarkup(<InvitePage />);

    expect(html).toContain("创建受邀账号");
    expect(html).toContain("注册邀请码");
    expect(html).toContain("邮箱");
    expect(html).toContain("确认密码");
    expect(html).toContain("至少 8 位，且包含大写字母、小写字母和数字");
    expect((html.match(/<input\b/g) ?? []).length).toBe(4);
    expect(html).toContain('name="code"');
    expect(html).toContain('name="email"');
    expect(html).toContain('name="password"');
    expect(html).toContain('name="password_confirmation"');
    expect(html).toContain('href="/login"');
  });
});
