# Issue tracker: Local Markdown

Matt profile 的 issues 和 specs 使用 `.scratch/`。已有 Superpowers 工作继续以 `docs/superpowers/` 下的 Spec/Plan 为权威产物，不复制到本 tracker。

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` — never a single combined tickets file
- Spec 和每张 implementation ticket 都在文件顶部记录 `Workflow profile`、`Status`、`Approval`、`Approved at` 和 `Approval evidence`
- Implementation ticket 另外记录 `Blocked by`；全部 ticket 及其 blocking edges 共同构成 Delivery Plan
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## Approval contract

`Status` 表示 readiness 或工作进度，`Approval` 表示用户授权。二者相互独立；`ready-for-agent` 不等于用户批准。

`Approval` 只允许：

- `draft`：尚未获得批准，或者批准后的合同/graph 已发生变化；
- `approved`：用户已经审阅对应完整产物并明确批准。

`Approved at` 使用 ISO 日期 `YYYY-MM-DD`；`Approval evidence` 记录可追溯的用户确认。任一字段缺失或仍为 `—` 时，`Approval` 必须为 `draft`。skill 自动发布 Spec 或 ticket 时必须使用 `draft`，不得自行推断批准。

`spec.md` 单独记录 Feature Contract 批准。每张 implementation ticket 记录同一次 Delivery Plan 批准；只有全部 ticket 的 `Approval`、`Approved at` 和 `Approval evidence` 一致，完整 ticket graph 才获批。新增、删除、拆分、合并 ticket 或改变任何 `Blocked by` 后，全部 implementation tickets 恢复为 `draft`，等待重新整体批准。

### Spec metadata template

```text
Workflow profile: matt
Status: ready-for-agent
Approval: draft
Approved at: —
Approval evidence: —
```

### Implementation ticket metadata template

```text
Workflow profile: matt
Status: ready-for-agent
Approval: draft
Approved at: —
Approval evidence: —
Blocked by: None — can start after the complete ticket graph is approved
```

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed), include the required metadata, and default `Approval` to `draft`.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

Wayfinder child tickets resolve research and design fog; they are not implementation tickets and do not form a Delivery Plan. When Wayfinder finishes, `/to-spec` and `/to-tickets` must still produce and obtain approval for the Matt Feature Contract and implementation ticket graph.

- **Map**: `.scratch/<effort>/map.md` — the Notes / Decisions-so-far / Fog body.
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
