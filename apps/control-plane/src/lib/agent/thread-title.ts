const MAX_THREAD_TITLE_LENGTH = 40;

export const DEFAULT_THREAD_TITLE = "新研究会话";

export function automaticThreadTitle(message: string): string {
  const normalized = message.replace(/\s+/g, " ").trim();
  if (!normalized) return DEFAULT_THREAD_TITLE;
  const title = normalized.replace(/^(?:请帮我|帮我)研究(?:一下)?/, "").trim() || normalized;
  return Array.from(title).slice(0, MAX_THREAD_TITLE_LENGTH).join("");
}

export function automaticThreadTitleUpdate(storedTitle: string, firstUserMessage: string | null | undefined): string | null {
  if (storedTitle !== DEFAULT_THREAD_TITLE || !firstUserMessage?.trim()) return null;
  const title = automaticThreadTitle(firstUserMessage);
  return title === DEFAULT_THREAD_TITLE ? null : title;
}
