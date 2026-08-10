# Invest Hub Agent 工作流治理设计

## 文档状态

- 阶段：项目治理调整
- 状态：**已批准（用户确认 2026-08-10）**
- 日期：2026-08-10
- 关联：[项目踩坑反思](../../project-pitfalls-reflections.md)、[本地 Issue Tracker 规则](../../agents/issue-tracker.md)、[项目状态](../../project-status.md)

## 1. 问题与目标

Invest Hub 既有功能长期使用 Superpowers 的“Spec 批准 → Implementation Plan 批准 → 实现与验证”流程，正式产物位于 `docs/superpowers/`。仓库近期又配置了 Matt Pocock engineering skills，本地 Spec 与 tickets 约定放在 `.scratch/<feature-slug>/`，但当前治理文件尚未说明两套产物的授权关系，也没有区分 `ready-for-agent` 与用户批准。

如果直接开始使用 Matt 流程，不同 Agent 可能产生三种互相冲突的解释：认为 tickets 不能替代独立 Plan；把 skill 自动写入的 `ready-for-agent` 当作用户批准；或者同时维护 Superpowers Plan 和 Matt tickets 两套执行来源。本设计的目标是建立一个统一治理合同，让两种工作流共享相同的授权门禁，同时避免改写既有历史。

## 2. 第一性原则

工程流程的本质不是调用哪一组 skill，而是稳定回答四个问题：做什么、为什么这样做、允许执行到哪里、怎样证明完成。Invest Hub 因此统一保留以下生命周期：

```text
Discovery（探索）
  → Feature Contract Approval（功能合同批准）
  → Delivery Plan Approval（交付计划批准）
  → Implementation（实现）
  → Verification（验证）
  → Release Authorization（发布授权，如适用）
```

任何 profile（流程配置）都必须产生可追溯的 Feature Contract 和 Delivery Plan。skill 的名称、文件形态和上下文组织可以不同，批准门禁、事实边界、安全要求和验收责任保持不变。

## 3. 已确认方案

### 3.1 两种合法 profile

Invest Hub 支持两种工作流 profile，但一个 feature 在同一时间只能有一个权威 profile。

| Profile | 适用范围 | Feature Contract | Delivery Plan |
| --- | --- | --- | --- |
| Matt Pocock（默认） | 后续新 Agent 能力，以及用户明确指定采用 Matt 的新 feature | `.scratch/<feature-slug>/spec.md` | `.scratch/<feature-slug>/issues/*.md` 的完整 ticket graph |
| Superpowers（保留） | 已有 Superpowers Spec/Plan 的模块 1 工作、正在执行的既有计划，以及用户明确指定采用 Superpowers 的新 feature | `docs/superpowers/specs/` 下的已批准 Spec | `docs/superpowers/plans/` 下的已批准 Implementation Plan |

既有 Superpowers 文档继续作为其所属工作的权威记录，不迁移、不复制到 `.scratch/`，也不根据 Matt 模板重写。Matt 成为后续新 Agent 能力的默认 profile，但这个默认值只决定工程编排，不自动扩大产品范围；模块 2、模块 3 或模块 4 的任何能力仍需先获得独立的产品范围与功能批准。

### 3.2 Matt 主流程与批准门禁

在 Invest Hub 仓库内，Matt profile 的主流程固定为：

```text
grill-with-docs
  → to-spec
  → 用户批准完整 spec.md
  → to-tickets
  → 用户批准完整 ticket graph
  → implement（逐 ticket）
  → code review + tests + 全量验证
  → release authorization（如涉及外部状态）
```

`grill-with-docs` 形成的 `CONTEXT.md` 和 ADR 是领域语言与跨功能架构决策的辅助事实，不是 feature 实现授权。`to-spec` 生成文件后必须等待用户审阅完整 Spec；只确认测试 seam（测试接缝）或让 skill 完成文件写入，都不等于批准。`to-tickets` 生成的所有 ticket 及其 blocking edges（阻塞关系）共同构成 Delivery Plan，必须整体获批后才可领取第一张实现 ticket。

每张 ticket 应当是可单独验证的 tracer bullet（贯穿式垂直切片），并继承已批准 Spec、项目安全边界、pitfalls 检查和上游 blocking ticket 的约束。实现过程中发现需要改变 Feature Contract、ticket graph、跨模块接口或 release gate 时，应暂停当前 ticket，先修订并重新批准对应 Spec 或 tickets。

### 3.3 状态与批准必须分离

Matt 本地文件使用两个正交维度：

- `Status` 表示工作流状态，例如 `needs-info`、`ready-for-agent`、`in-progress`、`done`；
- `Approval` 表示是否获得用户授权，只允许 `draft` 或 `approved`。

`ready-for-agent` 只说明材料足以由 Agent 执行，永远不等于用户批准。`spec.md` 必须单独记录 Spec 的 `Approval: approved`、批准日期和用户确认。ticket graph 中的每一张 ticket 必须记录同一次 Delivery Plan 批准的 `Approval: approved`、批准日期和用户确认；只有全部 ticket 的批准记录一致，完整 Delivery Plan 才算获批。单张 ticket 自动获得 `ready-for-agent` 也不能越过未批准的父 Spec 或未批准的完整 ticket graph。新增、删除、拆分、合并 ticket 或改变 blocking edge 后，完整 ticket graph 恢复为 `draft`，必须重新整体批准。

### 3.4 一个 feature 只有一个执行来源

新 feature 启动时必须在其 Feature Contract 中声明 `Workflow profile: matt` 或 `Workflow profile: superpowers`。选择 Matt 后，以 `.scratch/<feature-slug>/spec.md` 和对应 tickets 为唯一执行来源；选择 Superpowers 后，以对应 Spec/Plan 为唯一执行来源。

中途切换 profile 只能通过获批修订完成。修订必须说明切换原因、旧产物的终止状态、新旧需求与验收条件的映射，以及尚未完成工作的迁移边界。切换后旧执行文档保留为历史记录，但不再授权后续实现。

### 3.5 发布授权独立于本地实现批准

Feature Contract 和 Delivery Plan 的批准只授权其中明确写明的本地实现、测试和 commit。以下操作只有在 Delivery Plan 或独立 release ticket 明确列出，并获得对应授权后才能执行：

- Git push、创建或合并 PR；
- 远程 migration、生产数据写入、历史回刷或修复；
- Vercel 或其他生产部署；
- Worker 安装、重启、常驻调度或真实 Provider 调用；
- 登录态生产页面验收中任何会改变外部状态的操作。

高风险 Agent 能力即使采用 Matt profile，也必须在 ticket graph 中包含 release gate、回滚、失败恢复、脱敏和真实页面验收 ticket。采用 Matt 不降低 Invest Hub 的生产安全标准。

## 4. 事实与文档层级

为避免同一事实散落在多个文件中，权威边界固定如下：

| 文档 | 权威内容 | 不承担的职责 |
| --- | --- | --- |
| `docs/intake.md` | 项目背景、需求输入、历史方案与原始约束 | 当前实现状态、自动授权 |
| `docs/project-status.md` | 当前阶段、批准状态、已完成结果与后续门禁 | feature 设计细节 |
| `docs/project-pitfalls-reflections.md` | 跨任务失败模式和强制防复发检查 | 替代 Spec、Plan 或 ticket |
| `CONTEXT.md` | 共享领域语言 | feature 批准、实现授权 |
| `docs/adr/` | 跨 feature、难以逆转的架构决策 | 单个 feature 的交付拆分 |
| Feature Contract | 当前 feature 的问题、范围、合同与验收标准 | 具体 ticket 进度 |
| Delivery Plan | 实现切片、阻塞关系、验证与发布步骤 | 改写已批准的 Feature Contract |
| Engineering Journal / Final Report | 实际执行证据、偏差、结果与未决风险 | 事后补造授权 |

根 `AGENTS.md` 只保留所有任务都需要的强制门禁和指向上述文档的 context pointers（上下文指针），不再复制易过期的项目阶段或两套 profile 的完整细节。

## 5. 治理文件修改范围

本设计批准后，由独立 Implementation Plan 约束以下文档修改：

1. 调整根 `AGENTS.md`：声明统一生命周期、Matt 默认范围、Superpowers 保留范围、批准与发布门禁，并把详细规则指向 `docs/agents/workflow.md`；将易过期的当前阶段描述改为读取 `docs/project-status.md`，不在根文件重复缓存。
2. 新建 `docs/agents/workflow.md`：作为两种 profile、产物映射、审批状态、切换规则和发布授权的单一事实来源。
3. 更新 `docs/agents/issue-tracker.md`：为本地 Spec/tickets 增加 `Workflow profile`、`Approval`、批准日期和确认引用规则，明确完整 ticket graph 共同构成 Delivery Plan。
4. 更新 `docs/agents/triage-labels.md`：明确 `ready-for-agent` 是 readiness（可执行就绪度）而不是用户批准。
5. 更新 `docs/project-status.md` 与 `docs/README.md`：记录治理决策并提供入口，不改写既有 Superpowers 项目的历史状态。

本次不修改 Matt Pocock 全局 skill 文件，也不修改 Superpowers 插件；项目差异只通过仓库治理文件约束。

## 6. 验收标准

1. 根 `AGENTS.md` 明确：后续新 Agent 能力默认使用 Matt；已有模块 1 Superpowers Spec/Plan 继续有效；用户可为新 feature 明确选择 Superpowers。
2. 两种 profile 都映射到同一组 `Feature Contract Approval → Delivery Plan Approval → Implementation` 门禁。
3. Matt profile 明确采用 `grill-with-docs → to-spec → spec 批准 → to-tickets → ticket graph 批准 → implement`，不存在从 `ready-for-agent` 直接推导用户批准的路径。
4. `.scratch/<feature-slug>/spec.md` 和全部 `issues/*.md` 的权威关系、审批字段、阻塞关系与完成状态可以被新上下文中的 Agent 唯一解释。
5. 一个 feature 不会同时把 Superpowers Plan 和 Matt tickets 作为执行来源；切换规则要求修订、重新批准并保留历史。
6. 采用 Matt 不自动授权模块 2–4，不放宽数据、Prompt、评估集、release gate、生产写入、部署或真实 Provider 边界。
7. 根 `AGENTS.md` 不再硬编码已经过期的 Discovery 状态；当前事实由 `docs/project-status.md` 提供。
8. 新增和修改的 Markdown 链接可解析，术语在各治理文件中一致，`git diff --check` 与仓库脱敏检查通过。
9. 现有未提交治理修改得到保留；本次修改不触碰应用代码、数据库、Worker、Prompt、评估 fixture、生产环境或外部服务。

## 7. 非目标

- 本设计不批准任何具体 Agent 产品能力，也不改变模块 1–4 的产品范围。
- 本设计不迁移、删除或重写已有 `docs/superpowers/` Spec、Plan、Engineering Journal 或 Final Report。
- 本设计不要求同时使用两套流程，也不把 Matt tickets 复制成一份 Superpowers Plan。
- 本设计不修改全局安装的 Matt/Superpowers skills，不保证第三方 skill 后续版本永远不变；仓库治理规则始终优先。
- 本设计不执行代码实现、测试、部署、migration、历史数据恢复或生产验收。

## 8. 后续门禁

用户批准本 Spec 后，下一步编写独立 Implementation Plan，精确列出每个治理文件的改动、兼容现有 dirty worktree 的方式、文档一致性检查、脱敏检查和提交边界。Plan 获批前不修改本 Spec 之外的治理文件。
