export const DEMO_MESSAGE_LIMIT = 20_000;

export type DemoRunStatus = "queued" | "running" | "succeeded" | "failed";

export type DemoRun = {
  ownerId: string;
  threadId: string;
  requestId: string;
  question: string;
  status: DemoRunStatus;
  assistantContent: string | null;
  provider: string | null;
};

export class DemoRunStateError extends Error {
  constructor(message = "invalid_demo_run_state") {
    super(message);
    this.name = "DemoRunStateError";
  }
}

export function validateDemoMessage(value: string): string {
  if (typeof value !== "string") throw new Error("invalid_message");
  const content = value.trim();
  if (content.length < 1 || content.length > DEMO_MESSAGE_LIMIT) throw new Error("invalid_message");
  return content;
}

export function safeAssistantMarkdown(value: string): string {
  const content = value.trim();
  if (!content || content.length > DEMO_MESSAGE_LIMIT) throw new Error("invalid_assistant_message");
  if (/(?:^|[\s"'(=])(?:[A-Za-z]:)?\/(?:Users|home|private|tmp)(?:[\s"')\]=]|$)/i.test(content)) {
    throw new Error("unsafe_assistant_message");
  }
  return content;
}

export function acceptDemoMessage(input: {
  ownerId: string;
  threadId: string;
  requestId: string;
  question: string;
}): DemoRun {
  return {
    ownerId: input.ownerId,
    threadId: input.threadId,
    requestId: input.requestId,
    question: validateDemoMessage(input.question),
    status: "queued",
    assistantContent: null,
    provider: null,
  };
}

export function claimDemoRun(run: DemoRun): DemoRun {
  if (run.status !== "queued") throw new DemoRunStateError();
  return { ...run, status: "running" };
}

export function completeDemoRun(run: DemoRun, output: { content: string; provider: string }): DemoRun {
  if (run.status !== "queued" && run.status !== "running") throw new DemoRunStateError();
  if (!output.provider.trim()) throw new Error("invalid_provider");
  return {
    ...run,
    status: "succeeded",
    assistantContent: safeAssistantMarkdown(output.content),
    provider: output.provider,
  };
}
