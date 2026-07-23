# OpenCLI X Collection Receipt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 向 OpenCLI 上游的 `twitter tweets` 增加兼容的 collection receipt 模式，使时间范围采集器能可靠识别四类帖子关系并证明到达时间下界。

**Architecture:** 保持默认 `opencli twitter tweets` 的数组输出不变；仅当调用者显式传入 `--collection-receipt --until <RFC3339>` 时，返回 `{ posts, receipt }`。关系归一化与完成判定先实现为无浏览器副作用的纯函数，再接入现有的 Cookie/页面内 GraphQL 分页循环；任何不完整读取抛出 typed error 或返回非完成 receipt，不能伪装为成功。

**Tech Stack:** OpenCLI `clis/twitter` ESM JavaScript、Vitest adapter tests、TypeScript typecheck、OpenCLI registry validation、GitHub pull request。

## Global Constraints

- 只修改 OpenCLI 上游 Twitter Adapter；不得修改 Invest Hub 的共享协议、远程迁移、部署或真实数据。
- 不启用 `--collection-receipt` 时，既有参数、输出字段、数组形状、排序和 `top-by-engagement` 行为必须保持兼容。
- 新模式只能使用当前 OpenCLI 的 `Strategy.COOKIE` 和页面上下文已有的 GraphQL 路径；不得直接导出或存储 Cookie、CSRF、Bearer token、cursor token 或原始响应。
- `receipt.completed` 仅可由 `time_boundary_reached` 或 `cursor_exhausted` 产生；页数、滚动次数、`limit`、重复 cursor、错误或部分数据绝不能产生完成回执。
- 关系上下文不可见时使用 `unavailable` 或 `unknown`，不得从文本、`RT` 前缀或缺失字段推断为已确认关系。
- 测试只使用人工 GraphQL fixture；真实 X 验证留到上游版本可安装、Browser Bridge 健康且用户再次授权之后。
- 提交遵循上游 Conventional Commit；外部 push 与 PR 只在本 Plan 批准后执行。

---

## File Structure

| File | Responsibility |
| --- | --- |
| `clis/twitter/tweets.js` | 新 flag、范围参数、关系/时间纯函数，以及将回执接入现有 UserTweets 分页循环。 |
| `clis/twitter/tweets.test.js` | 人工 GraphQL 对象的关系、回执、兼容性和失败语义单元测试。 |
| `cli-manifest.json` | 由上游 build 生成；仅在生成结果包含新的 Adapter 参数时纳入提交。 |
| `docs/superpowers/plans/2026-07-23-opencli-x-collection-receipt.md` | Invest Hub 对上游 PR 的实施与验收记录；不复制真实数据。 |

## Public Interface

```text
opencli twitter tweets <username> [--limit N] [--page-delay N]
opencli twitter tweets <username> --collection-receipt --until <RFC3339> [--limit N] [--page-delay N]
```

Default mode returns the existing chronological post array. Collection mode returns:

```ts
type RelationshipTarget = {
  post_id: string | null;
  author_handle: string | null;
  author_id: string | null;
  url: string | null;
  context_status: 'complete' | 'unavailable' | 'unknown';
};

type TweetRelationship = {
  kind: 'original' | 'quote' | 'reply' | 'repost';
  target: RelationshipTarget | null;
};

type CollectionReceipt = {
  completed: boolean;
  stop_reason:
    | 'time_boundary_reached'
    | 'cursor_exhausted'
    | 'limit_reached'
    | 'page_guard_hit'
    | 'repeated_cursor';
  requested_until: string;
  pages_fetched: number;
  oldest_seen_at: string | null;
};

type CollectionResponse = {
  posts: Array<ExistingTweet & { relationship: TweetRelationship }>;
  receipt: CollectionReceipt;
};
```

For request, GraphQL-shape, timestamp or relation extraction failures, the command throws an existing typed OpenCLI error instead of returning a `CollectionResponse` with a misleading success state.

## Task 0: Create an isolated, current upstream PR workspace

**Files:**
- Create outside both repositories: `/private/tmp/opencli-x-collection-receipt-<random>/`
- Create outside both repositories: `/private/tmp/opencli-x-collection-pr-summary.md`

**Interfaces:**
- Produces an OpenCLI fork remote named `origin`, an `upstream` remote pointing to `jackwener/OpenCLI`, and branch `feat/twitter-collection-receipt` based on current `upstream/main`.
- Does not modify the Invest Hub worktree or installed global OpenCLI package.

- [ ] **Step 1: Verify GitHub identity and create the fork only after this Plan is approved.**

  Run:

  ```bash
  gh auth status
  gh api user --jq .login
  gh repo fork jackwener/OpenCLI --clone=false
  ```

  Expected: a writable fork exists under the authenticated GitHub account. If `gh auth status` fails or the fork cannot be created, stop before modifying any repository and report the classified authorization failure.

- [ ] **Step 2: Clone and pin the exact upstream base.**

  Run:

  ```bash
  opencli_pr_root=$(mktemp -d /private/tmp/opencli-x-collection-receipt.XXXXXX)
  git clone "git@github.com:$(gh api user --jq .login)/OpenCLI.git" "$opencli_pr_root/OpenCLI"
  cd "$opencli_pr_root/OpenCLI"
  git remote add upstream https://github.com/jackwener/OpenCLI.git
  git fetch upstream main
  git checkout -b feat/twitter-collection-receipt upstream/main
  git rev-parse HEAD
  ```

  Expected: the branch starts from a printed immutable upstream commit SHA. Retain only the SHA in the eventual PR summary; do not copy local Chrome/OpenCLI configuration into this checkout.

- [ ] **Step 3: Install and establish the upstream baseline.**

  Run from the new OpenCLI checkout:

  ```bash
  npm ci
  npx vitest run clis/twitter/tweets.test.js
  npm run typecheck
  npm run test:adapter
  git status --short
  ```

  Expected: the checked-out baseline is clean and its focused Twitter tests pass before feature work. If a baseline command fails, record only command name, exit status and public failure class in `/private/tmp/opencli-x-collection-pr-summary.md`; do not change feature tests or claim the new PR passes that gate.

## Task 1: Define collection options, relationship extraction and pure completion rules

**Files:**
- Modify: `clis/twitter/tweets.js`
- Test: `clis/twitter/tweets.test.js`

**Interfaces:**
- Produces `normalizeCollectionOptions(kwargs)`, `extractTweetRelationship(tweet)`, `parseCreatedAt(value)`, `inspectCollectionProgress(posts, until)` and `buildCollectionReceipt(input)` exported through `__test__`.
- `extractTweet(result, seen, { includeRelationship })` continues to return the existing row when `includeRelationship` is false and appends `relationship` only when true.

- [ ] **Step 1: Write failing tests for option validation and four relationship types.**

  Add artificial GraphQL tweet builders and the following tests to `clis/twitter/tweets.test.js`:

  ```js
  it('requires an RFC3339 until value with collection receipt', () => {
    expect(() => __test__.normalizeCollectionOptions({ 'collection-receipt': true }))
      .toThrow(/--until/);
    expect(__test__.normalizeCollectionOptions({
      'collection-receipt': true,
      until: '2026-07-23T00:00:00.000Z',
    })).toEqual({ enabled: true, until: '2026-07-23T00:00:00.000Z' });
  });

  it.each([
    ['original', originalGraphqlTweet()],
    ['quote', quoteGraphqlTweet()],
    ['reply', replyGraphqlTweet()],
    ['repost', repostGraphqlTweet()],
  ])('normalizes %s without inferring unavailable context', (kind, raw) => {
    expect(__test__.extractTweetRelationship(raw)).toMatchObject({ kind });
  });
  ```

  Include a tombstoned quote and a reply missing its parent body. Assert their stable target identity is retained when present and `context_status` is `unavailable`, never `complete`.

- [ ] **Step 2: Run the focused test and verify it fails.**

  Run from the OpenCLI clone root:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  ```

  Expected: FAIL because `normalizeCollectionOptions` and `extractTweetRelationship` are not exported.

- [ ] **Step 3: Implement the minimal pure helpers and opt-in arguments.**

  In `clis/twitter/tweets.js`, add named options after existing pagination options:

  ```js
  { name: 'collection-receipt', type: 'boolean', default: false,
    help: 'Return relationship facts and a non-sensitive range-completion receipt.' },
  { name: 'until', type: 'string',
    help: 'RFC3339 lower time boundary required by --collection-receipt.' },
  ```

  Implement exact validation and classification rules:

  ```js
  const RFC3339_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/;

  function normalizeCollectionOptions(kwargs) {
    if (!kwargs['collection-receipt']) return { enabled: false, until: null };
    const rawUntil = String(kwargs.until ?? '');
    const date = new Date(rawUntil);
    if (!RFC3339_TIMESTAMP.test(rawUntil) || Number.isNaN(date.getTime())) {
      throw new ArgumentError('--collection-receipt requires --until <RFC3339>.');
    }
    return { enabled: true, until: date.toISOString() };
  }

  function relationshipTarget({ id = null, authorHandle = null, authorId = null, complete = false }) {
    return {
      post_id: id,
      author_handle: authorHandle,
      author_id: authorId,
      url: id && authorHandle ? `https://x.com/${authorHandle}/status/${id}` : null,
      context_status: complete ? 'complete' : (id ? 'unavailable' : 'unknown'),
    };
  }
  ```

  Use the raw GraphQL relation fields (`quoted_status_result`, `in_reply_to_status_id_str`, `in_reply_to_screen_name`, `in_reply_to_user_id_str`, and the nested retweeted-status result) rather than text heuristics. Preserve default `extractTweet(result, seen)` output exactly by appending `relationship` only when its third argument enables collection mode.

- [ ] **Step 4: Run focused tests and adapter static checks.**

  Run:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  npm run typecheck
  npm run check:typed-error-lint
  ```

  Expected: all pass; invalid collection options raise `ArgumentError`, and no relation test treats missing context as complete.

- [ ] **Step 5: Commit the isolated parser contract.**

  ```bash
  git add clis/twitter/tweets.js clis/twitter/tweets.test.js
  git commit -m "feat(twitter): add collection relation contract"
  ```

## Task 2: Add bounded pagination receipt semantics without changing default reads

**Files:**
- Modify: `clis/twitter/tweets.js`
- Test: `clis/twitter/tweets.test.js`

**Interfaces:**
- Consumes `normalizeCollectionOptions`, the collection-aware `extractTweet`, and `parseUserTweets`.
- Produces `paginateCollection({ fetchPage, until, limit, pageGuard })`, which returns `{ posts, receipt }` only for boundary/cursor completion and otherwise throws `CommandExecutionError` with a safe reason code.

- [ ] **Step 1: Write failing receipt tests using a synthetic `fetchPage`.**

  Add pure pagination tests that do not create a browser session:

  ```js
  it('completes only after a page crosses the requested time boundary', async () => {
    const result = await __test__.paginateCollection({
      until: '2026-07-23T00:00:00.000Z',
      limit: 20,
      pageGuard: 5,
      fetchPage: async (cursor) => cursor
        ? pageWithTweets([tweetAt('2026-07-22T23:59:00.000Z')], null)
        : pageWithTweets([tweetAt('2026-07-23T00:01:00.000Z')], 'older'),
    });
    expect(result.receipt).toMatchObject({
      completed: true,
      stop_reason: 'time_boundary_reached',
      pages_fetched: 2,
    });
  });

  it('completes on cursor exhaustion but rejects limit and repeated-cursor stops', async () => {
    await expect(__test__.paginateCollection(limitReachedFixture)).rejects.toThrow(/limit_reached/);
    await expect(__test__.paginateCollection(repeatedCursorFixture)).rejects.toThrow(/repeated_cursor/);
  });
  ```

  Add a fixture for malformed `created_at`; assert it raises an error rather than setting `oldest_seen_at` to a guessed value. Add a compatibility test asserting default mode still returns `Array.isArray(result) === true` and has no `relationship` key.

- [ ] **Step 2: Run the focused test and verify it fails.**

  Run:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  ```

  Expected: FAIL because `paginateCollection` does not exist and current pagination silently stops on partial data.

- [ ] **Step 3: Implement the bounded collection loop.**

  Refactor only the existing pagination loop so the fetch mechanism remains page-context GraphQL. Implement the loop around this contract:

  ```js
  async function paginateCollection({ fetchPage, until, limit, pageGuard }) {
    const posts = [];
    const seen = new Set();
    let cursor = null;
    for (let pageIndex = 0; pageIndex < pageGuard; pageIndex += 1) {
      const { data, nextCursor } = await fetchPage(cursor);
      const page = parseUserTweets(data, seen, { includeRelationship: true });
      posts.push(...page.tweets);
      const progress = inspectCollectionProgress(posts, until);
      if (progress.boundaryReached) return {
        posts,
        receipt: buildCollectionReceipt('time_boundary_reached', until, pageIndex + 1, progress.oldestSeenAt),
      };
      if (!nextCursor) return {
        posts,
        receipt: buildCollectionReceipt('cursor_exhausted', until, pageIndex + 1, progress.oldestSeenAt),
      };
      if (nextCursor === cursor) throw new CommandExecutionError('twitter_collection_repeated_cursor');
      if (posts.length >= limit) throw new CommandExecutionError('twitter_collection_limit_reached');
      cursor = nextCursor;
    }
    throw new CommandExecutionError('twitter_collection_page_guard_hit');
  }
  ```

  In collection mode, HTTP/GraphQL failures after any successful page must throw rather than break and return partial rows. In default mode preserve the current behavior and call path, including existing `page-delay` and engagement reranking behavior.

- [ ] **Step 4: Run focused tests and build the generated manifest.**

  Run:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  npm run build
  opencli validate twitter/tweets
  ```

  Expected: receipt tests pass, build regenerates the manifest without secrets, and validation accepts the new named flags.

- [ ] **Step 5: Commit the bounded receipt path.**

  ```bash
  git add clis/twitter/tweets.js clis/twitter/tweets.test.js cli-manifest.json
  git commit -m "feat(twitter): add bounded collection receipt"
  ```

## Task 3: Run the complete upstream quality gate and prepare the PR

**Files:**
- Modify if generated: `cli-manifest.json`
- Create outside repositories: `/private/tmp/opencli-x-collection-pr-summary.md`

**Interfaces:**
- Consumes the Task 1–2 implementation and generated manifest.
- Produces a clean OpenCLI branch with an auditable PR description that contains no real X account, post body, URL, credential, cursor or raw payload.

- [ ] **Step 1: Add a regression test for default JSON compatibility.**

  Add this test before final verification:

  ```js
  it('keeps default tweets output as the legacy row array', () => {
    const row = __test__.extractTweet(originalGraphqlTweet(), new Set());
    expect(Object.keys(row)).toEqual([
      'id', 'author', 'name', 'text', 'likes', 'retweets', 'replies', 'views',
      'is_retweet', 'created_at', 'url', 'has_media', 'media_urls',
      'media_posters', 'quoted_tweet',
    ]);
    expect(row).not.toHaveProperty('relationship');
  });
  ```

  Adjust the expected ordering only if the checked-out upstream base has already added public default columns; do not remove, rename or reorder any existing column to accommodate this feature.

- [ ] **Step 2: Run the full applicable quality gate.**

  Run from the OpenCLI clone root:

  ```bash
  npx vitest run clis/twitter/tweets.test.js
  npm run test:adapter
  npm run typecheck
  npm run check:silent-column-drop
  npm run check:typed-error-lint
  npm run build
  opencli validate twitter/tweets
  git diff --check
  ```

  Expected: every command exits 0. If an upstream baseline failure is unrelated, capture only the command name and failure class in `/private/tmp/opencli-x-collection-pr-summary.md`; do not weaken or skip the focused `tweets.test.js` gate.

- [ ] **Step 3: Review the change for data-boundary regressions.**

  Inspect:

  ```bash
  git diff --check
  git diff -- clis/twitter/tweets.js clis/twitter/tweets.test.js cli-manifest.json
  rg -n -i 'cookie|csrf|bearer|authorization|cursor' clis/twitter/tweets.js cli-manifest.json
  ```

  Expected: request secrets remain internal to the existing page-context fetch; the user-visible collection response and committed fixtures contain none of those values. `cursor` may appear only in internal implementation identifiers, never as a response field or fixture value.

- [ ] **Step 4: Commit and publish the upstream PR.**

  ```bash
  git add clis/twitter/tweets.js clis/twitter/tweets.test.js cli-manifest.json
  git commit -m "feat(twitter): add collection receipt mode"
  git push -u origin feat/twitter-collection-receipt
  gh pr create \
    --title "feat(twitter): add collection receipt mode" \
    --body-file /private/tmp/opencli-x-collection-pr-summary.md
  ```

  The PR description must state: default output is unchanged; collection mode is opt-in; receipt success requires time-boundary or cursor exhaustion; missing relationship/context is not inferred; fixtures are artificial; and this is not a claim of production collection readiness.

- [ ] **Step 5: Record only the safe PR outcome in Invest Hub.**

  After PR creation, update the V2 engineering journal with the PR URL, commit SHA, tested OpenCLI version, and whether the capability is `proposed`, `merged`, or `installable`. Do not record real account identities, content, raw command output or local evidence paths. Commit that documentation separately:

  ```bash
  git add docs/engineering-journal/2026-07-23-v2-x-local-implementation.md docs/project-status.md
  git commit -m "docs(v2): record OpenCLI receipt proposal"
  ```

## Plan Self-Review

- **Spec coverage:** Task 0 creates a clean, pinned upstream review base; Task 1 covers opt-in compatibility and four relationship facts; Task 2 covers lower-bound/cursor completion and partial-read rejection; Task 3 covers generated manifest, upstream quality gates, PR hygiene and safe Invest Hub status recording.
- **No placeholders:** all files, command names, flag names, receipt values, error reason codes and expected outcomes are explicit.
- **Type consistency:** the `CollectionResponse`, `TweetRelationship`, `CollectionReceipt`, `normalizeCollectionOptions`, `extractTweetRelationship` and `paginateCollection` names are used consistently in every task.
- **Scope:** this Plan ends at the upstream PR and documentation. A separate approved follow-up is required before changing the Invest Hub runtime to consume the new mode or retrying real X collection.
