import type { ReactNode } from "react";

import { parseSafeMarkdown, type MarkdownInline } from "../../lib/agent-demo/markdown";

function renderInline(inlines: MarkdownInline[]): ReactNode[] {
  return inlines.map((inline, index) => inline.kind === "link"
    ? <a href={inline.href} key={`${inline.href}-${index}`} target="_blank" rel="noreferrer">{inline.label}</a>
    : <span key={`text-${index}`}>{inline.value}</span>);
}

export function SafeMarkdown({ content }: { content: string }) {
  return <div className="agent-markdown">
    {parseSafeMarkdown(content).map((block, index) => {
      if (block.kind === "heading") {
        const Heading = `h${block.level}` as "h1" | "h2" | "h3";
        return <Heading key={index}>{renderInline(block.inlines)}</Heading>;
      }
      if (block.kind === "list") {
        const List = block.ordered ? "ol" : "ul";
        return <List key={index}>{block.items.map((item, itemIndex) => <li key={itemIndex}>{renderInline(item)}</li>)}</List>;
      }
      if (block.kind === "code") return <pre key={index}><code>{block.value}</code></pre>;
      return <p key={index}>{renderInline(block.inlines)}</p>;
    })}
  </div>;
}
