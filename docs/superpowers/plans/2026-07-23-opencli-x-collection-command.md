# OpenCLI X Collection Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增独立的 `opencli twitter collection` 只读命令，返回关系完整的帖子与可证明的时间范围完成回执，同时保持 `opencli twitter tweets` 的输出完全不变。

**Architecture:** 新命令独立注册，columns 固定为 `posts` 与 `receipt`，调用者以 `-f json` 消费 envelope；它与 `tweets` 复用一个无 CLI 副作用的 UserTweets GraphQL 支持模块。`tweets` 只做等价内部重构，默认参数、行数组、columns、排序、分页和错误行为不变；collection 单独拥有关系归一化和范围完成循环。

**Tech Stack:** OpenCLI ESM JavaScript、Vitest adapter tests、TypeScript typecheck、OpenCLI manifest/validation gates、GitHub pull request。

## Global Constraints

- 只修改 OpenCLI 上游 Twitter Adapter；不改 Invest Hub runtime、共享协议、远程迁移、部署或真实数据。
- `twitter tweets` 不新增参数、不新增 columns、不返回 envelope，行为与上游基线完全兼容。
- `twitter collection <username> --until <RFC3339> -f json` 的 columns 恰为 `posts`、`receipt`；不得以静态检查绕过、基线更新或隐藏字段方式规避 OpenCLI columns 契约。
- 只复用现有 Cookie/页面上下文的 UserTweets GraphQL 路径；不得导出 Cookie、CSRF、Bearer token、cursor token、原始请求或原始响应。
- receipt 只在 `time_boundary_reached` 或 `cursor_exhausted` 时 `completed=true`；limit、页数保护、重复 cursor、协议错误、时间错误或未解决关系均为 typed failure。
- 回复/引用/转发上下文不可见时明确为 `unavailable` 或 `unknown`；不从文本或 `RT` 前缀推断已确认关系。
- 真实 X 验证、Codex CLI、远程 migration 与部署仍需上游可安装版本后的单独授权。

---

## File Structure

| File | Responsibility |
| --- | --- |
| `clis/twitter/user-timeline.js` | 不注册 CLI；封装 UserTweets query metadata、用户解析、带 cursor 的页面获取和 payload unwrap。 |
| `clis/twitter/tweets.js` | 导入 shared helpers，保持既有行数组与 public command contract 不变。 |
| `clis/twitter/collection.js` | 注册新命令、关系事实、时间下界/耗尽 receipt 与 typed failure。 |
| `clis/twitter/collection.test.js` | 人工 GraphQL fixture 的关系、范围、失败与 envelope 测试。 |
| `clis/twitter/tweets.test.js` | 默认 `tweets` 无回归测试。 |
| `cli-manifest.json` | 由 build 生成，并包含新 command 的 `posts` / `receipt` columns。 |

## Public Interface

```text
opencli twitter tweets <username> [--limit N] [--page-delay N]
opencli twitter collection <username> --until <RFC3339> [--limit N] [--page-delay N] -f json
```

```ts
type CollectionResponse = {
  posts: Array<{
    id: string;
    author: string;
    created_at: string;
    url: string;
    relationship: {
      kind: 'original' | 'quote' | 'reply' | 'repost';
      target: {
        post_id: string | null;
        author_handle: string | null;
        author_id: string | null;
        url: string | null;
        context_status: 'complete' | 'unavailable' | 'unknown';
      } | null;
    };
  }>;
  receipt: {
    completed: true;
    stop_reason: 'time_boundary_reached' | 'cursor_exhausted';
    requested_until: string;
    pages_fetched: number;
    oldest_seen_at: string | null;
  };
};
```

## Task 0: Preserve the exploratory branch and start a clean command branch

**Files:**
- Create outside repositories: `/private/tmp/opencli-x-collection-command-<random>/`
- Create outside repositories: `/private/tmp/opencli-x-collection-pr-summary.md`

**Interfaces:**
- Produces local branch `feat/twitter-collection-command` at the recorded `upstream/main` SHA.
- Keeps the existing unpushed `feat/twitter-collection-receipt` exploratory branch intact; it is neither pushed nor deleted.

- [ ] **Step 1: Inspect and preserve the rejected mode-switch work.**

  Run in the existing OpenCLI workspace:

  ```bash
  git status --short
  git log --oneline upstream/main..HEAD
  git diff -- clis/twitter/tweets.js clis/twitter/tweets.test.js cli-manifest.json
  ```

  Expected: only the rejected `twitter tweets --collection-receipt` exploration is present. Do not push it, amend it, reset it, or copy its mode-switch interface into the new branch.

- [ ] **Step 2: Create a clean branch from current upstream main.**

  Run:

  ```bash
  collection_root=$(mktemp -d /private/tmp/opencli-x-collection-command.XXXXXX)
  git clone https://github.com/INKWWW/OpenCLI.git "$collection_root/OpenCLI"
  cd "$collection_root/OpenCLI"
  git remote add upstream https://github.com/jackwener/OpenCLI.git
  git fetch upstream main
  git checkout -b feat/twitter-collection-command upstream/main
  git rev-parse HEAD
  npm ci
  ```

  Expected: the printed SHA is the sole PR base; no rejected flag exists in the clean checkout.

- [ ] **Step 3: Verify the clean baseline.**

  Run:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  npm run typecheck
  npm run test:adapter
  git status --short
  ```

  Expected: focused Twitter test, typecheck and adapter suite pass; the checkout is clean before feature work.

## Task 1: Extract shared UserTweets transport without changing `tweets`

**Files:**
- Create: `clis/twitter/user-timeline.js`
- Modify: `clis/twitter/tweets.js`
- Test: `clis/twitter/tweets.test.js`

**Interfaces:**
- `resolveUserTimelineContext(page, rawUsername, { allowLoggedInDefault })` returns `{ username, userId, headers, userTweetsOperation }` or throws existing `ArgumentError`, `AuthRequiredError` or `CommandExecutionError`. `tweets` passes `true`; `collection` passes `false`, so collection never silently substitutes the logged-in account.
- `buildUserTweetsUrl(operation, userId, count, cursor)` is a named export used by both commands and focused fixture tests.
- `USER_TWEETS_PAGE_SIZE`, `MAX_USER_TWEETS_PAGES`, and `DEFAULT_USER_TWEETS_PAGE_DELAY_SECONDS` are named exports used by both commands; each command keeps its own CLI-facing `limit` and `page-delay` validation/messages.
- `fetchUserTimelinePage(page, context, cursor, count)` returns normalized UserTweets payload or a typed execution failure.
- `tweets.js` retains its existing CLI registration and `__test__` helpers, delegating only transport setup/page fetch.

- [ ] **Step 1: Write a failing default-command regression test.**

  Add this import and test to `clis/twitter/tweets.test.js`:

  ```js
  import { buildUserTweetsUrl } from './user-timeline.js';

  it('keeps tweets command arguments and columns unchanged after transport extraction', () => {
    const cmd = getRegistry().get('twitter/tweets');
    expect(cmd?.args?.map((arg) => arg.name)).toEqual([
      'username', 'limit', 'page-delay', 'top-by-engagement',
    ]);
    expect(cmd?.columns).toEqual([
      'id', 'author', 'created_at', 'is_retweet', 'text', 'likes',
      'retweets', 'replies', 'views', 'url', 'has_media', 'media_urls',
      'media_posters', 'quoted_tweet',
    ]);
    expect(buildUserTweetsUrl('query', '42', 20, 'cursor')).toContain('/UserTweets');
  });
  ```

- [ ] **Step 2: Run the test to verify the absent shared module.**

  Run:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  ```

  Expected: FAIL because `./user-timeline.js` does not yet exist; the current registry assertion documents the unchanged public contract.

- [ ] **Step 3: Create the shared transport module and refactor only internals.**

  In `clis/twitter/user-timeline.js`, move the current UserTweets/UserByScreenName query metadata, URL builders, logged-in-profile discovery, `ct0` lookup, and page-context fetch construction. Export `buildUserTweetsUrl`, `USER_TWEETS_PAGE_SIZE`, `MAX_USER_TWEETS_PAGES`, `DEFAULT_USER_TWEETS_PAGE_DELAY_SECONDS`, and:

  ```js
  export async function resolveUserTimelineContext(page, rawUsername, { allowLoggedInDefault }) {
    // normalize the handle; resolve the logged-in profile only when the caller allows it,
    // require ct0 in the page cookie jar, resolve UserTweets/UserByScreenName metadata,
    // and return opaque request headers plus the target user ID.
  }

  export async function fetchUserTimelinePage(page, context, cursor, count) {
    const url = buildUserTweetsUrl(context.userTweetsOperation, context.userId, count, cursor);
    const payload = normalizeTwitterGraphqlPayload(await page.evaluate(`async () => {
      const r = await fetch("${url}", { headers: ${context.headers}, credentials: 'include' });
      return r.ok ? await r.json() : { error: r.status };
    }`));
    if (payload?.error) throw new CommandExecutionError(describeTwitterApiError('UserTweets', payload.error));
    return payload;
  }
  ```

  Update `tweets.js` to import the helpers, preserve its local `normalizeLimit` and `normalizePageDelaySeconds` functions (including their current messages), and pass `{ allowLoggedInDefault: true }`. Preserve its current delay, cursor loop, partial-read behavior, `applyTopByEngagement` call and default output exactly. The collection command will use its own validators, named `normalizeCollectionLimit` and `normalizeCollectionPageDelaySeconds`, whose error messages name `twitter collection`.

- [ ] **Step 4: Verify the refactor has no public effect.**

  Run:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  npm run typecheck
  npm run check:typed-error-lint
  ```

  Expected: all pass, and the test proves no collection parameter or column appears on `twitter tweets`.

- [ ] **Step 5: Commit the shared transport extraction.**

  ```bash
  git add clis/twitter/user-timeline.js clis/twitter/tweets.js clis/twitter/tweets.test.js
  git commit -m "refactor(twitter): share user timeline transport"
  ```

## Task 2: Implement the independent `twitter collection` command by TDD

**Files:**
- Create: `clis/twitter/collection.js`
- Create: `clis/twitter/collection.test.js`
- Modify if generated: `cli-manifest.json`

**Interfaces:**
- CLI registration has `site: 'twitter'`, `name: 'collection'`, `access: 'read'`, `strategy: Strategy.COOKIE`, `browser: true`, `columns: ['posts', 'receipt']`.
- `normalizeUntil(raw)`, `extractRelationship(result)`, `parseCollectionPage(payload, seen)`, and `paginateCollection(input)` are exported under `__test__`.
- `paginateCollection` never returns an incomplete receipt; it throws a typed `CommandExecutionError` for `twitter_collection_limit_reached`, `twitter_collection_page_guard_hit`, `twitter_collection_repeated_cursor`, `twitter_collection_invalid_timestamp`, or `twitter_collection_unresolved_relationship`.

- [ ] **Step 1: Write failing tests with artificial GraphQL objects.**

  Create `clis/twitter/collection.test.js` with tests equivalent to:

  ```js
  it('registers an independent read command with posts and receipt columns', () => {
    const cmd = getRegistry().get('twitter/collection');
    expect(cmd).toMatchObject({ access: 'read', browser: true, columns: ['posts', 'receipt'] });
    expect(getRegistry().get('twitter/tweets')?.args?.map((arg) => arg.name))
      .not.toContain('collection-receipt');
  });

  it('classifies original, quote, reply and repost without inventing context', () => {
    expect(__test__.extractRelationship(originalFixture())).toEqual({ kind: 'original', target: null });
    expect(__test__.extractRelationship(replyFixture())).toMatchObject({
      kind: 'reply', target: { post_id: '30', context_status: 'unavailable' },
    });
    expect(__test__.extractRelationship(tombstonedQuoteFixture())).toMatchObject({
      kind: 'quote', target: { post_id: '50', context_status: 'unavailable' },
    });
    expect(__test__.extractRelationship(repostFixture())).toMatchObject({
      kind: 'repost', target: { post_id: '60', context_status: 'complete' },
    });
  });

  it('completes only at the lower boundary or cursor exhaustion', async () => {
    const result = await __test__.paginateCollection(boundaryCrossingFixture);
    expect(result.receipt).toMatchObject({ completed: true, stop_reason: 'time_boundary_reached' });
    await expect(__test__.paginateCollection(repeatedCursorFixture))
      .rejects.toThrow(/twitter_collection_repeated_cursor/);
  });
  ```

  Add explicit tests for invalid RFC3339 `--until`, malformed `created_at`, collection-specific `limit` and page-delay validation, limit reached, page guard, incomplete repost target, and command-level `{ posts, receipt }` JSON response. Fixtures must include a stable ID, a non-sensitive synthetic handle, and valid X-style timestamp strings; they must not copy a real post, account, link, cursor, cookie, or response.

- [ ] **Step 2: Run collection tests and verify they fail.**

  Run:

  ```bash
  npx vitest run clis/twitter/collection.test.js
  ```

  Expected: FAIL because the collection Adapter and helper exports do not exist.

- [ ] **Step 3: Implement collection-only relation and receipt semantics.**

  Register the command exactly as follows:

  ```js
  cli({
    site: 'twitter',
    name: 'collection',
    access: 'read',
    description: 'Fetch a user timeline with relationship facts and a bounded completion receipt.',
    domain: 'x.com',
    strategy: Strategy.COOKIE,
    browser: true,
    args: [
      { name: 'username', type: 'string', positional: true, required: true, help: 'Twitter screen name (with or without @).' },
      { name: 'until', type: 'string', required: true, help: 'RFC3339 lower time boundary that must be reached or exhausted.' },
      { name: 'limit', type: 'int', default: 10000, help: 'Safety ceiling; reaching it is a typed failure.' },
      { name: 'page-delay', type: 'int', default: 2, help: 'Seconds to wait between cursor pages.' },
    ],
    columns: ['posts', 'receipt'],
    func: async (page, kwargs) => paginateCollection({
      page,
      context: await resolveUserTimelineContext(page, kwargs.username),
      until: normalizeUntil(kwargs.until),
      limit: normalizeCollectionLimit(kwargs.limit),
      pageDelaySeconds: normalizeCollectionPageDelaySeconds(kwargs['page-delay']),
    }),
  });
  ```

  Use payload fields for relationships: `quoted_status_result` plus `quoted_status_id_str`; `in_reply_to_status_id_str`, `in_reply_to_screen_name`, `in_reply_to_user_id_str`; and nested `retweeted_status_result`. Do not classify a text-only `RT` prefix as complete. Each page obtains 100 rows, persists no response, and stops successfully only when a timestamp is at or before `until`, or no cursor exists. Do not return cursor tokens.

- [ ] **Step 4: Run focused verification and generate the manifest.**

  Run:

  ```bash
  npx vitest run clis/twitter/collection.test.js clis/twitter/tweets.test.js
  npm run typecheck
  npm run build
  ./dist/src/main.js validate twitter/collection
  npm run check:silent-column-drop
  npm run check:typed-error-lint
  ```

  Expected: all pass. The manifest exposes only the two collection output columns, and `twitter tweets` remains unchanged.

- [ ] **Step 5: Commit the new command.**

  ```bash
  git add clis/twitter/collection.js clis/twitter/collection.test.js cli-manifest.json
  git commit -m "feat(twitter): add bounded collection command"
  ```

## Task 3: Final review, publish PR, and record safe status

**Files:**
- Modify if generated: `cli-manifest.json`
- Create outside repositories: `/private/tmp/opencli-x-collection-pr-summary.md`
- Modify after PR creation: `docs/engineering-journal/2026-07-23-v2-x-local-implementation.md`, `docs/project-status.md`

**Interfaces:**
- Produces a GitHub PR from `INKWWW:feat/twitter-collection-command` to `jackwener:main`.
- PR body and Invest Hub record contain only public command semantics, commit SHA, PR URL, version and test aggregate; no account, content, URL, cursor, credentials or raw payload.

- [ ] **Step 1: Run the complete upstream quality gate.**

  Run:

  ```bash
  npx vitest run clis/twitter/collection.test.js clis/twitter/tweets.test.js
  npm run test:adapter
  npm run typecheck
  npm run check:silent-column-drop
  npm run check:typed-error-lint
  npm run build
  ./dist/src/main.js validate twitter/tweets twitter/collection
  git diff --check
  git status --short
  ```

  Expected: every command exits 0. Upstream warnings unrelated to Twitter remain visible but are not fixed in this PR.

- [ ] **Step 2: Perform the output-boundary review.**

  Run:

  ```bash
  git diff upstream/main -- clis/twitter/user-timeline.js clis/twitter/tweets.js clis/twitter/collection.js clis/twitter/tweets.test.js clis/twitter/collection.test.js cli-manifest.json
  rg -n -i 'cookie|csrf|bearer|authorization|cursor' clis/twitter/user-timeline.js clis/twitter/collection.js cli-manifest.json
  ```

  Expected: auth material is used only inside page-context fetch construction; no output object, generated manifest or fixture exposes it. Cursor may exist only as private control flow, never in receipt or fixture data.

- [ ] **Step 3: Push and create the PR.**

  Create `/private/tmp/opencli-x-collection-pr-summary.md` with this exact structure:

  ```markdown
  ## Summary
  - Adds `opencli twitter collection <username> --until <RFC3339> -f json`.
  - Keeps `opencli twitter tweets` arguments, columns and output unchanged.
  - Completion requires a reached lower boundary or cursor exhaustion; partial reads fail explicitly.
  - Uses only artificial fixtures; no browser credentials or real X content are included.

  ## Verification
  - `npx vitest run clis/twitter/collection.test.js clis/twitter/tweets.test.js`
  - `npm run test:adapter`
  - `npm run typecheck`
  - `npm run check:silent-column-drop`
  - `npm run check:typed-error-lint`
  - `npm run build`
  - `./dist/src/main.js validate twitter/tweets twitter/collection`
  ```

  Then run:

  ```bash
  git push -u origin feat/twitter-collection-command
  gh pr create \
    --repo jackwener/OpenCLI \
    --base main \
    --head INKWWW:feat/twitter-collection-command \
    --title "feat(twitter): add bounded collection command" \
    --body-file /private/tmp/opencli-x-collection-pr-summary.md
  ```

- [ ] **Step 4: Record the proposed upstream capability without claiming V2 Go.**

  Update the Invest Hub V2 journal and project status with PR URL, head SHA, base SHA, tested version, and `proposed` status. State that V2 remains `x_collection_unverified` until upstream merge, an installable version and a separately authorized real Go/No-Go. Then commit documentation separately:

  ```bash
  git add docs/engineering-journal/2026-07-23-v2-x-local-implementation.md docs/project-status.md
  git commit -m "docs(v2): record OpenCLI collection proposal"
  ```

## Plan Self-Review

- **Spec coverage:** Task 0 avoids rewriting or publishing the rejected mode branch; Task 1 preserves `tweets`; Task 2 introduces the independently typed collection envelope and all reliability boundaries; Task 3 verifies, publishes and records only safe status.
- **Columns consistency:** `tweets` keeps its existing row columns, while `collection` has only `posts` and `receipt`; no collection relation key is emitted as an undeclared row column.
- **Scope:** no Invest Hub runtime switch, real X test, migration or deployment is included. Those remain separately gated after upstream release.
