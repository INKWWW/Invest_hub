import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { SourceAuthorProfilesForm, authorOptionLabel, profileStatusLabel, resolutionStatusLabel } from "./SourceAuthorProfilesForm";

describe("SourceAuthorProfilesForm", () => {
  it("treats observed identities as suggestions and accepts a direct author selector", () => {
    expect(authorOptionLabel({ author_id: "stable-id", author_display: "作者甲", author_handle: "author-a" })).toBe("作者甲 @author-a");
    expect(authorOptionLabel({ author_id: "stable-id", author_display: "作者甲", author_handle: null })).toBe("作者甲");
    expect(profileStatusLabel(true)).toBe("已启用");
    expect(profileStatusLabel(false)).toBe("已停用");
    expect(resolutionStatusLabel("pending")).toBe("等待匹配");
    expect(resolutionStatusLabel("resolved")).toBe("已匹配");
    expect(resolutionStatusLabel("ambiguous")).toBe("匹配不唯一");

    const html = renderToStaticMarkup(<SourceAuthorProfilesForm sourceId="source-private-id" />);
    expect(html).toContain("已观察到的作者");
    expect(html).toContain("仅作为输入提示");
    expect(html).toContain("指定作者");
    expect(html).toContain("datalist");
    expect(html).toContain("仅影响后续任务");
    expect(html).not.toContain("必须来自已观察到的稳定身份");
    expect(html).not.toContain("消息内容");
  });
});
