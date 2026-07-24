import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { isExactConfirmation, XSourceRemovalControl } from "./XSourceRemovalControl";

describe("XSourceRemovalControl", () => {
  it("requires an exact typed confirmation", () => {
    expect(isExactConfirmation("AllInvestHK", "AllInvestHK")).toBe(true);
    expect(isExactConfirmation(" AllInvestHK", "AllInvestHK")).toBe(false);

    const html = renderToStaticMarkup(<XSourceRemovalControl sourceId="source-x" displayName="AllInvestHK" canRemove />);
    expect(html).toContain("输入 AllInvestHK 以确认");
    expect(html).toContain("确认移除博主");
    expect(html).toContain("disabled");
    expect(html).toContain("已有任务或事实的来源会停止并归档");
  });

  it("does not render a confirmation action while an X task is active", () => {
    const html = renderToStaticMarkup(<XSourceRemovalControl sourceId="source-x" displayName="AllInvestHK" canRemove={false} />);

    expect(html).toContain("存在进行中或待恢复任务，暂不能移除。");
    expect(html).not.toContain("确认移除博主");
  });
});
