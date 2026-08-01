import { beforeEach, describe, expect, it, vi } from "vitest";

const hooks = vi.hoisted(() => ({ cursor: 0, effects: [] as Array<() => void>, state: [] as unknown[] }));

vi.mock("react", async (importOriginal) => {
  const actual = await importOriginal<typeof import("react")>();
  return {
    ...actual,
    useEffect: (effect: () => void) => { hooks.effects.push(effect); },
    useMemo: <Value,>(factory: () => Value) => factory(),
    useState: <Value,>(initial: Value | (() => Value)) => {
      const index = hooks.cursor++;
      if (!(index in hooks.state)) hooks.state[index] = typeof initial === "function" ? (initial as () => Value)() : initial;
      return [hooks.state[index] as Value, (next: Value | ((current: Value) => Value)) => {
        hooks.state[index] = typeof next === "function" ? (next as (current: Value) => Value)(hooks.state[index] as Value) : next;
      }] as const;
    },
  };
});

import { XReader } from "./XReader";

type Element = { type?: unknown; props?: { children?: unknown; onChange?: (event: { target: { value: string } }) => void; value?: string } };

function elements(node: unknown, type: string): Element[] {
  if (Array.isArray(node)) return node.flatMap((child) => elements(child, type));
  if (!node || typeof node !== "object") return [];
  const element = node as Element;
  return [(element.type === type ? [element] : []), elements(element.props?.children, type)].flat();
}

const days = [{
  naturalDate: "2099-01-02", judgement: { visible: true, batches: [] },
  bloggers: [{ source: { sourceKey: "second", displayName: "Second Author" }, status: "succeeded", segments: [] }],
}, {
  naturalDate: "2099-01-01", judgement: { visible: true, batches: [] },
  bloggers: [{ source: { sourceKey: "second", displayName: "Second Author" }, status: "succeeded", segments: [] }],
}];

describe("XReader client selectors", () => {
  const replaceState = vi.fn();

  function renderClient(initialSourceKey?: string, initialNaturalDate?: string) {
    hooks.cursor = 0;
    hooks.effects = [];
    const tree = XReader({ days, initialSourceKey, initialNaturalDate });
    hooks.effects.forEach((effect) => effect());
    return tree;
  }

  beforeEach(() => {
    hooks.state = [];
    replaceState.mockReset();
    vi.stubGlobal("window", {
      history: { replaceState, state: null },
      location: { hash: "", pathname: "/x", search: "?source=all&date=2099-01-02" },
    });
  });

  it("retains date when source changes and retains source when date changes", () => {
    let tree = renderClient(undefined, "2099-01-02");
    const [source, date] = elements(tree, "select");
    source?.props?.onChange?.({ target: { value: "second" } });

    tree = renderClient(undefined, "2099-01-02");
    expect(elements(tree, "select")[0]?.props?.value).toBe("second");
    expect(replaceState).toHaveBeenLastCalledWith(null, "", "/x?source=second&date=2099-01-02");

    elements(tree, "select")[1]?.props?.onChange?.({ target: { value: "2099-01-01" } });
    tree = renderClient(undefined, "2099-01-02");
    expect(elements(tree, "select")[1]?.props?.value).toBe("2099-01-01");
    expect(replaceState).toHaveBeenLastCalledWith(null, "", "/x?source=second&date=2099-01-01");
  });

  it("uses one normalized URL update and removes only selectors set to all", () => {
    renderClient("second", "2099-01-02");

    expect(replaceState).toHaveBeenCalledTimes(1);
    expect(replaceState).toHaveBeenLastCalledWith(null, "", "/x?source=second&date=2099-01-02");

    hooks.state = ["all", "all"];
    renderClient("second", "2099-01-02");
    expect(replaceState).toHaveBeenLastCalledWith(null, "", "/x");
  });
});
