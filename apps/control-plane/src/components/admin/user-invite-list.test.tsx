import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { UserInviteList, inviteDisplayState } from "./UserInviteList";

const now = new Date("2099-01-01T00:00:00.000Z");

describe("UserInviteList", () => {
  it("renders masked codes, configured duration, and a live remaining time", () => {
    const html = renderToStaticMarkup(<UserInviteList
      now={now}
      invites={[{
        codeMask: "Ab••••7Q",
        validityHours: 24,
        createdAt: "2098-12-31T01:00:00.000Z",
        expiresAt: "2099-01-01T01:00:00.000Z",
        consumedAt: null,
      }]}
    />);

    expect(html).toContain("Ab••••7Q");
    expect(html).toContain("24 小时");
    expect(html).toContain("01:00:00");
    expect(html).toContain("有效");
    expect(html).not.toContain("code_hash");
  });

  it("prioritizes consumed and expired states and handles legacy rows", () => {
    const html = renderToStaticMarkup(<UserInviteList
      now={now}
      invites={[
        { codeMask: "Cd••••8R", validityHours: 1, createdAt: "2098-12-31T00:00:00.000Z", expiresAt: "2098-12-31T01:00:00.000Z", consumedAt: null },
        { codeMask: "Ef••••3T", validityHours: 2, createdAt: "2098-12-31T00:00:00.000Z", expiresAt: "2099-01-02T00:00:00.000Z", consumedAt: "2098-12-31T00:30:00.000Z" },
        { codeMask: null, validityHours: null, createdAt: "2098-12-31T00:00:00.000Z", expiresAt: "2099-01-02T00:00:00.000Z", consumedAt: null },
      ]}
    />);

    expect(html).toContain("已过期");
    expect(html).toContain("已使用");
    expect(html).toContain("旧邀请码（无掩码）");
  });

  it("calculates remaining state from the server expiry timestamp", () => {
    expect(inviteDisplayState({
      codeMask: "Ab••••7Q",
      validityHours: 24,
      createdAt: "2098-12-31T00:00:00.000Z",
      expiresAt: "2099-01-01T00:00:01.000Z",
      consumedAt: null,
    }, now)).toEqual({ label: "有效", remaining: "00:00:01" });
    expect(inviteDisplayState({
      codeMask: "Ab••••7Q",
      validityHours: 24,
      createdAt: "2098-12-31T00:00:00.000Z",
      expiresAt: "2099-01-01T00:00:00.000Z",
      consumedAt: null,
    }, now)).toEqual({ label: "已过期", remaining: "已过期" });
  });
});
