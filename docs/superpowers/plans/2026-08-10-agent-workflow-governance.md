# Invest Hub Agent Workflow Governance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将 Matt Pocock 设为后续新 Agent 能力的默认工程流程，同时保留既有 Superpowers 工作的权威性，并让两者共享明确、不可绕过的批准与发布门禁。

**Architecture:** 根 AGENTS.md 只保留常驻强制门禁和 context pointer；详细 profile、审批、切换与发布规则集中在 docs/agents/workflow.md。本地 tracker 文档负责 .scratch 文件格式与状态语义，docs/project-status.md 和 docs/README.md 只记录当前治理决策与导航入口。

**Tech Stack:** Markdown、Git、POSIX shell、仓库既有 scripts/v0/redact-check.sh。

## 文档状态

- 状态：**已完成（2026-08-10）**
- 授权：用户于 2026-08-10 确认 Spec 并要求完成后续工作
- 执行方式：Inline Execution

## Global Constraints

- 已批准 Spec：docs/superpowers/specs/2026-08-10-agent-workflow-governance-design.md。
- 后续新 Agent 能力默认采用 Matt；已有模块 1 Superpowers Spec/Plan 继续有效，新 feature 仍可由用户明确选择 Superpowers。
- 统一门禁为 Feature Contract Approval → Delivery Plan Approval → Implementation → Verification → Release Authorization。
- ready-for-agent 只表示 readiness，不表示用户批准。
- 一个 feature 同一时间只能有一个权威 workflow profile；profile 切换必须修订、重新批准并保留历史。
- Matt 默认值不授权模块 2–4，不放宽数据、Prompt、评估集、生产写入、部署或真实 Provider 边界。
- 本计划只修改治理 Markdown；不修改应用代码、数据库、Worker、Prompt、评估 fixture、生产环境或外部服务。
- 工作区开始时已有未提交修改；必须保留所有既有内容，不得覆盖、回退或把不相关改动纳入本任务提交。
- 本次授权只覆盖计划内的本地文档修改、验证与可安全隔离的本地提交，不授权 push、PR、部署或远程状态变更。

---

### Task 1: 建立工作流单一事实来源并接入根 AGENTS.md

**Files:**
- Create: docs/agents/workflow.md
- Modify: AGENTS.md

**Interfaces:**
- Consumes: 已批准治理 Spec、docs/project-status.md、docs/project-pitfalls-reflections.md。
- Produces: 统一生命周期、Matt/Superpowers profile 映射和根级强制 workflow pointer。

- [x] **Step 1: 创建 workflow 权威文档**

创建 docs/agents/workflow.md，依次写明统一生命周期、两种 profile、Matt 主流程、Status/Approval 分离、单一执行来源、profile 切换、release authorization 和文档权威层级。

- [x] **Step 2: 移除 AGENTS.md 的过期状态缓存**

把硬编码的 Discovery、尚无批准 Spec/Plan 和 V0–V3 后续顺序改为正向规则：当前阶段、已批准范围和下一门禁必须读取 docs/project-status.md。保留未获批准前只能澄清、设计和治理，不得开始应用实现或生产变更的门禁。

- [x] **Step 3: 添加强制 workflow pointer**

在 AGENTS.md 中明确：
- 任何新 feature 先读 docs/agents/workflow.md；
- 新 Agent 能力默认 Matt，既有模块 1 Superpowers 继续有效；
- ready-for-agent 不等于批准；
- 一个 feature 只有一个执行来源；
- push、远程 migration、部署和真实生产操作需要独立授权。

- [x] **Step 4: 验证根入口与权威正文一致**

Run:

~~~bash
rg -n "Matt|Superpowers|ready-for-agent|Feature Contract|Delivery Plan|release|project-status|workflow.md" AGENTS.md docs/agents/workflow.md
~~~

Expected: 根文件包含触发条件和强制门禁；详细定义集中在 workflow.md；不存在仍宣称项目整体处于初始 Discovery 或没有任何已批准 Spec/Plan 的句子。

### Task 2: 固化本地 Spec/Ticket 的审批合同

**Files:**
- Modify: docs/agents/issue-tracker.md
- Modify: docs/agents/triage-labels.md

**Interfaces:**
- Consumes: docs/agents/workflow.md 的 Matt profile 与批准语义。
- Produces: .scratch feature 文件的可机械检查元数据，以及 readiness 与 authorization 的清晰边界。

- [x] **Step 1: 扩展 tracker conventions**

规定 spec.md 和每张 ticket 都必须包含 Workflow profile、Status、Approval、Approved at、Approval evidence；ticket 继续包含 Blocked by。Approval 只允许 draft/approved，批准日期或证据为空时不得为 approved。

- [x] **Step 2: 添加元数据模板**

写入以下模板：

~~~text
Workflow profile: matt
Status: ready-for-agent
Approval: draft
Approved at: —
Approval evidence: —
~~~

只有用户批准后才更新 Approval、ISO 日期和可追溯确认。全部 ticket 共享同一次批准记录时，完整 graph 才获批；ticket 数量、内容或 blocking edge 改变后，完整 graph 恢复 draft。

- [x] **Step 3: 澄清 triage label**

把 ready-for-agent 定义为“材料完整、可由 Agent 执行；仍必须满足独立 Approval 门禁”，并明确所有 triage labels 都不产生用户授权。

- [x] **Step 4: 验证审批字段**

Run:

~~~bash
rg -n "Workflow profile|Status|Approval|Approved at|Approval evidence|ready-for-agent|Blocked by|draft|approved" docs/agents/issue-tracker.md docs/agents/triage-labels.md
~~~

Expected: Spec 和 ticket 都有完整字段；ready-for-agent 只描述 readiness；graph 变化使整体 approval 失效。

### Task 3: 更新项目状态与文档入口

**Files:**
- Modify: docs/project-status.md
- Modify: docs/README.md
- Modify: docs/superpowers/specs/2026-08-10-agent-workflow-governance-design.md
- Modify: docs/superpowers/plans/2026-08-10-agent-workflow-governance.md

**Interfaces:**
- Consumes: Task 1–2 的最终治理文件。
- Produces: 当前治理决策状态、维护者导航入口和 Spec/Plan 完成状态。

- [x] **Step 1: 记录治理决策**

在 project-status 的 Current phase 产品状态之后加入 2026-08-10 治理记录，明确 Matt 默认范围、Superpowers 历史权威、统一批准门禁和“不自动授权模块 2–4”。不得改写既有产品状态或 V2 结论。

- [x] **Step 2: 添加 docs README 入口**

在项目协作/文档索引位置增加 workflow、local tracker、pitfalls 和本次治理 Spec/Plan 的链接。

- [x] **Step 3: 标记批准与执行状态**

Spec 保持“已批准（用户确认 2026-08-10）”。本 Plan 完成后勾选所有步骤；若任一步失败，保留未完成状态并记录阻塞证据。

- [x] **Step 4: 验证导航**

Run:

~~~bash
test -f docs/agents/workflow.md
test -f docs/agents/issue-tracker.md
test -f docs/project-pitfalls-reflections.md
rg -n "workflow|Matt|Superpowers|工作流|pitfalls|workflow-governance" docs/README.md docs/project-status.md
~~~

Expected: 所有入口存在，状态文档只新增治理记录。

### Task 4: 全量治理验证与安全收口

**Files:**
- Verify: AGENTS.md
- Verify: docs/agents/workflow.md
- Verify: docs/agents/issue-tracker.md
- Verify: docs/agents/triage-labels.md
- Verify: docs/project-status.md
- Verify: docs/README.md
- Verify: 本次治理 Spec/Plan

**Interfaces:**
- Consumes: Task 1–3 的全部治理修改。
- Produces: 无矛盾、无断链、无敏感信息且保留既有 dirty worktree 的最终文档集合。

- [x] **Step 1: 检查合同覆盖**

Run:

~~~bash
rg -n "grill-with-docs|to-spec|to-tickets|implement|Feature Contract|Delivery Plan|ready-for-agent|Approval|release" AGENTS.md docs/agents docs/project-status.md
~~~

Expected: Matt 主流程、两次批准、状态分离、单一执行来源和发布授权均有权威定义与入口。

- [x] **Step 2: 检查过期和矛盾表述**

Run:

~~~bash
rg -n "当前项目状态为 Discovery|尚无批准后的 specification|尚无批准后的 implementation plan|只允许.*Superpowers|ready-for-agent.*批准" AGENTS.md docs/agents docs/project-status.md
~~~

Expected: 只有明确说明“ready-for-agent 不等于批准”的正向防误用文本可以命中；不存在过期项目状态或 Superpowers-only 限制。

- [x] **Step 3: 检查 Markdown whitespace**

Run:

~~~bash
git diff --check
~~~

Expected: exit 0。

- [x] **Step 4: 运行脱敏检查**

Run:

~~~bash
bash scripts/v0/redact-check.sh
~~~

Expected: exit 0，未发现真实 URL、Cookie、Token、私有 Prompt、真实 fixture 或本地 evidence。

- [x] **Step 5: 审查 dirty worktree 与提交边界**

Run:

~~~bash
git status --short
git diff -- AGENTS.md docs/agents docs/project-status.md docs/README.md docs/superpowers/specs/2026-08-10-agent-workflow-governance-design.md docs/superpowers/plans/2026-08-10-agent-workflow-governance.md
~~~

Expected: 只有批准范围内增量和任务开始前已有用户改动；.superpowers、docs/handoffs 及其他未授权文件未被修改。无法安全隔离的重叠改动保留在工作区，不得为了制造干净状态覆盖用户内容。

- [x] **Step 6: 提交可安全隔离的治理产物**

优先提交本任务新建的 workflow.md 与 Plan/Spec 状态更新。任务开始前已 dirty 或 untracked 的文件，只有全部内容都直接属于 Matt 治理配置时才纳入；否则保持未提交。建议提交信息：

~~~bash
git commit -m "docs: adopt Matt workflow governance"
~~~

完成标准：提交不含应用代码、生产配置、真实数据或不相关用户改动；最终报告精确列出已提交与仍留在工作区的文件。
