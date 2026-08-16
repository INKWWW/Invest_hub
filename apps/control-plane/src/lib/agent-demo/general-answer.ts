export const GENERAL_PRODUCT_INSTRUCTION_VERSION = "invest-hub.agent-demo.general.v1";
export const MAX_THREAD_MESSAGES = 100;
export const INVESTMENT_ADVICE_DISCLAIMER = "AI投资建议，仅供参考。";

export type GeneralHistoryMessage = { role: "user" | "assistant"; content: string };
export type GeneralSource = { id: string; title: string; publisher: string; date: string; url: string };
export type GeneralAnswer = { markdown: string; sources: GeneralSource[]; contains_investment_advice: boolean };

const safeUrl = /^https:\/\/[^\s<>"']+$/i;

export function buildGeneralPrompt(history: GeneralHistoryMessage[], question: string): string {
  if (!Array.isArray(history) || history.length > MAX_THREAD_MESSAGES) throw new Error("thread_context_too_long");
  if (typeof question !== "string" || !question.trim()) throw new Error("invalid_message");
  const messages = history.map((message) => {
    if (!message || !["user", "assistant"].includes(message.role) || typeof message.content !== "string") throw new Error("invalid_thread_context");
    return { role: message.role, content: message.content };
  });
  return [
    `Invest Hub general chat product instruction ${GENERAL_PRODUCT_INSTRUCTION_VERSION}.`,
    "只用于一般投资问答，不适用于 Skill 执行。区分来源事实、来源观点和 Agent 推断；关键判断必须提供可回读来源。证据不足时明确说明，不捏造来源、数字、日期或链接。若包含投资建议，必须绑定来源、条件、期限、风险和失效条件，并显示固定免责声明。",
    "Thread history (ordered):",
    JSON.stringify(messages),
    "Current question:",
    question.trim(),
  ].join("\n\n");
}

export function validateGeneralAnswer(value: unknown): GeneralAnswer {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_general_answer");
  const candidate = value as Partial<GeneralAnswer>;
  if (typeof candidate.markdown !== "string" || !candidate.markdown.trim() || !Array.isArray(candidate.sources) || typeof candidate.contains_investment_advice !== "boolean") throw new Error("invalid_general_answer");
  const ids = new Set<string>();
  for (const source of candidate.sources) {
    if (!source || typeof source !== "object" || typeof source.id !== "string" || !source.id || ids.has(source.id) || typeof source.title !== "string" || !source.title || typeof source.publisher !== "string" || !source.publisher || typeof source.date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(source.date) || typeof source.url !== "string" || !safeUrl.test(source.url)) throw new Error("invalid_general_answer");
    ids.add(source.id);
  }
  const references = [...candidate.markdown.matchAll(/\[([A-Za-z0-9_-]+)\]/g)].map((match) => match[1]);
  if (references.some((reference) => !ids.has(reference))) throw new Error("invalid_general_answer");
  if (candidate.contains_investment_advice && (ids.size === 0 || !candidate.markdown.includes(INVESTMENT_ADVICE_DISCLAIMER))) throw new Error("invalid_general_answer");
  return { markdown: candidate.markdown.trim(), sources: candidate.sources as GeneralSource[], contains_investment_advice: candidate.contains_investment_advice };
}
