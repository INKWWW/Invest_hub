import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  rows: new Map<string, unknown>(),
  selects: [] as Array<{ table: string; columns: string }>,
  filters: [] as Array<{ table: string; field: string; value: unknown }>,
}));

vi.mock("../supabase-server", () => ({
  createSupabaseServerClient: async () => ({
    from(table: string) {
      const query = {
        select(columns: string) {
          databaseMocks.selects.push({ table, columns });
          return query;
        },
        eq(field: string, value: unknown) {
          databaseMocks.filters.push({ table, field, value });
          return query;
        },
        in(field: string, value: unknown[]) {
          databaseMocks.filters.push({ table, field, value });
          return query;
        },
        maybeSingle() {
          return Promise.resolve({ data: databaseMocks.rows.get(table) ?? null, error: null });
        },
        order() { return query; },
        then(resolve: (value: { data: unknown; error: null }) => unknown) {
          return resolve({ data: databaseMocks.rows.get(table) ?? [], error: null });
        },
      };
      return query;
    },
  }),
}));

import { getResearchThread } from "./research-threads";

describe("research thread Skill metadata compatibility", () => {
  beforeEach(() => {
    databaseMocks.rows.clear();
    databaseMocks.selects.length = 0;
    databaseMocks.filters.length = 0;
    databaseMocks.rows.set("research_threads", {
      id: "thread-one",
      owner_id: "user-one",
      title: "宁德时代研究",
      created_at: "2099-01-01T00:00:00.000Z",
      updated_at: "2099-01-01T00:00:00.000Z",
    });
    databaseMocks.rows.set("research_messages", [
      { id: "message-one", thread_id: "thread-one", owner_id: "user-one", role: "user", content: "研究公开公司", created_at: "2099-01-01T00:00:01.000Z" },
      { id: "message-two", thread_id: "thread-one", owner_id: "user-one", role: "assistant", content: "# 结论", created_at: "2099-01-01T00:00:02.000Z" },
    ]);
    databaseMocks.rows.set("research_thread_artifacts", []);
    databaseMocks.rows.set("agent_demo_runs", [
      { user_message_id: "message-one", skill_id: "investment-research" },
    ]);
  });

  it("maps the run Skill onto its user message without changing order or title", async () => {
    await expect(getResearchThread("user-one", "thread-one")).resolves.toMatchObject({
      title: "宁德时代研究",
      messages: [
        { id: "message-one", role: "user", skillId: "investment-research" },
        { id: "message-two", role: "assistant", skillId: null },
      ],
    });
    expect(databaseMocks.selects).toContainEqual({ table: "agent_demo_runs", columns: "user_message_id,skill_id" });
    expect(databaseMocks.filters).toContainEqual({ table: "agent_demo_runs", field: "owner_id", value: "user-one" });
    expect(databaseMocks.filters).toContainEqual({ table: "agent_demo_runs", field: "user_message_id", value: ["message-one"] });
  });
});
