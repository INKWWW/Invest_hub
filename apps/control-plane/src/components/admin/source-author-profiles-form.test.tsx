import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { SourceAuthorProfilesForm, authorOptionLabel, profileStatusLabel } from "./SourceAuthorProfilesForm";

describe("SourceAuthorProfilesForm", () => {
  it("labels observed identities safely and never asks for a free-text identity", () => {
    expect(authorOptionLabel({ author_id: "stable-id", author_display: "作者甲", author_handle: "author-a" })).toBe("作者甲 @author-a");
    expect(authorOptionLabel({ author_id: "stable-id", author_display: "作者甲", author_handle: null })).toBe("作者甲");
    expect(profileStatusLabel(true)).toBe("已启用");
    expect(profileStatusLabel(false)).toBe("已停用");

    const html = renderToStaticMarkup(<SourceAuthorProfilesForm sourceId="source-private-id" />);
    expect(html).toContain("已观察到的作者");
    expect(html).toContain("仅影响后续任务");
    expect(html).not.toContain("textarea");
    expect(html).not.toContain("消息内容");
  });
});
