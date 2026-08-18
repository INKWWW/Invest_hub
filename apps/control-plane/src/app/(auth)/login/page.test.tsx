import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import LoginPage from "./page";

describe("login page invited-registration entry", () => {
  it("renders Chinese login copy and one discoverable invited-registration link", () => {
    const html = renderToStaticMarkup(<LoginPage />);

    expect(html).toContain("登录 Invest Hub");
    expect(html).toContain("邮箱");
    expect(html).toContain("密码");
    expect(html).toContain("登录");
    expect(html).toContain('href="/invite"');
    expect(html).toContain("有邀请码？创建账号");
    expect(html).not.toContain("公开注册");
  });
});
