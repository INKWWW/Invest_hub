export type MarkdownInline =
  | { kind: "text"; value: string }
  | { kind: "link"; label: string; href: string };

export type MarkdownBlock =
  | { kind: "heading"; level: 1 | 2 | 3; inlines: MarkdownInline[] }
  | { kind: "paragraph"; inlines: MarkdownInline[] }
  | { kind: "list"; ordered: boolean; items: MarkdownInline[][] }
  | { kind: "code"; value: string };

const linkPattern = /\[([^\]]+)\]\(([^)\s]+)\)/g;
const safeUrl = /^https:\/\/[^\s<>"']+$/i;

export function parseSafeMarkdown(markdown: string): MarkdownBlock[] {
  if (typeof markdown !== "string") throw new Error("invalid_markdown");
  const lines = markdown.replaceAll("\r\n", "\n").split("\n");
  const blocks: MarkdownBlock[] = [];
  let paragraph: string[] = [];
  let code: string[] | null = null;

  const flushParagraph = () => {
    const value = paragraph.join("\n").trim();
    if (value) blocks.push({ kind: "paragraph", inlines: parseInline(value) });
    paragraph = [];
  };

  for (const line of lines) {
    if (line.trim().startsWith("```") || code !== null) {
      if (line.trim().startsWith("```") && code === null) {
        flushParagraph();
        code = [];
      } else if (line.trim().startsWith("```") && code !== null) {
        blocks.push({ kind: "code", value: code.join("\n") });
        code = null;
      } else if (code !== null) {
        code.push(line);
      }
      continue;
    }
    if (!line.trim()) {
      flushParagraph();
      continue;
    }
    const heading = line.match(/^(#{1,3})\s+(.+)$/);
    if (heading) {
      flushParagraph();
      blocks.push({ kind: "heading", level: heading[1].length as 1 | 2 | 3, inlines: parseInline(heading[2]) });
      continue;
    }
    const list = line.match(/^\s*([-*]|\d+\.)\s+(.+)$/);
    if (list) {
      flushParagraph();
      const ordered = /\d+\./.test(list[1]);
      const previous = blocks.at(-1);
      if (previous?.kind === "list" && previous.ordered === ordered) previous.items.push(parseInline(list[2]));
      else blocks.push({ kind: "list", ordered, items: [parseInline(list[2])] });
      continue;
    }
    paragraph.push(line);
  }
  if (code !== null) blocks.push({ kind: "code", value: code.join("\n") });
  flushParagraph();
  return blocks;
}

export function parseInline(value: string): MarkdownInline[] {
  const result: MarkdownInline[] = [];
  let cursor = 0;
  for (const match of value.matchAll(linkPattern)) {
    const index = match.index ?? 0;
    if (index > cursor) result.push({ kind: "text", value: value.slice(cursor, index) });
    const label = match[1];
    const href = match[2];
    if (safeUrl.test(href)) result.push({ kind: "link", label, href });
    else result.push({ kind: "text", value: match[0] });
    cursor = index + match[0].length;
  }
  if (cursor < value.length) result.push({ kind: "text", value: value.slice(cursor) });
  return result.length ? result : [{ kind: "text", value }];
}
