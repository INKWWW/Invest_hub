import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { SessionControls } from "./SessionControls";

describe("SessionControls", () => {
  it("shows a configuration-management link only to administrators", () => {
    const adminHtml = renderToStaticMarkup(<SessionControls viewer={{ email: "admin@example.invalid", role: "admin" }} />);
    const readerHtml = renderToStaticMarkup(<SessionControls viewer={{ email: "reader@example.invalid", role: "user" }} />);

    expect(adminHtml).toContain('href="/admin"');
    expect(adminHtml).toContain("配置管理");
    expect(readerHtml).not.toContain("配置管理");
  });
});
