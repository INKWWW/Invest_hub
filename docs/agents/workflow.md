# Agent 工作流治理

本文件是 Invest Hub 工程工作流、批准语义和执行来源的权威说明。开始新 feature、继续既有计划、切换工作流或准备发布前，先阅读本文件，再读取 docs/project-status.md、docs/project-pitfalls-reflections.md 与当前 feature 的正式产物。

## 统一生命周期

所有工作流都必须经过同一条治理链：

~~~text
Discovery
  → Feature Contract Approval
  → Delivery Plan Approval
  → Implementation
  → Verification
  → Release Authorization（如涉及外部状态）
~~~

Feature Contract 冻结问题、范围、设计边界和验收标准；Delivery Plan 冻结实现切片、阻塞关系、验证和发布步骤。两者分别获批前，不得开始应用实现。

## 选择 workflow profile

一个 feature 在同一时间只有一个权威 profile：

| Profile | 默认适用范围 | Feature Contract | Delivery Plan |
| --- | --- | --- | --- |
| Matt Pocock | 后续新 Agent 能力，以及用户明确指定采用 Matt 的新 feature | `.scratch/<feature-slug>/spec.md` | `.scratch/<feature-slug>/issues/*.md` 的完整 ticket graph |
| Superpowers | 已有 Superpowers Spec/Plan 的模块 1 工作、正在执行的既有计划，以及用户明确指定采用 Superpowers 的新 feature | `docs/superpowers/specs/` 下的已批准 Spec | `docs/superpowers/plans/` 下的已批准 Implementation Plan |

Matt 是后续新 Agent 能力的默认工程编排，但不会自动批准任何产品能力或扩大模块范围。模块 2–4 仍须先获得独立的产品范围和 Feature Contract 批准。

已有 Superpowers 产物继续是其所属工作的权威记录，不迁移、不复制、不按 Matt 模板重写。用户对新 feature 的明确 profile 选择优先于默认值。

## Matt profile

仓库内的主流程为：

~~~text
grill-with-docs
  → to-spec
  → 用户批准完整 spec.md
  → to-tickets
  → 用户批准完整 ticket graph
  → implement（逐 ticket）
  → code review + tests + 全量验证
  → release authorization（如适用）
~~~

grill-with-docs 形成的 CONTEXT.md 和 ADR 用于共享语言与跨 feature 架构决策，不产生实现授权。to-spec 写入文件或确认测试 seam 不等于批准；用户必须审阅完整 spec.md。to-tickets 产生的所有 ticket 及其 blocking edges 共同构成 Delivery Plan，完整 graph 获批后才能领取第一张实现 ticket。

每张 ticket 应是可独立验证的 tracer bullet，并继承已批准 Spec、项目安全边界、pitfalls 与上游 blocker。实现发现需要改变 Feature Contract、ticket graph、跨模块接口或 release gate 时，暂停当前 ticket 并先修订、重新批准相应产物。

## Superpowers profile

Superpowers profile 继续使用：

~~~text
brainstorming
  → 用户批准 Spec
  → writing-plans
  → 用户批准独立 Implementation Plan
  → executing-plans 或 subagent-driven-development
  → verification
  → release authorization（如适用）
~~~

已有已批准 Spec/Plan 的工作直接从其当前门禁继续，不为采用本治理规则而重走历史步骤。新 Superpowers feature 仍须独立完成 Spec 与 Plan 批准。

## Status 与 Approval

工作状态和用户授权是两个正交维度：

- Status 描述工作所处阶段，例如 needs-info、ready-for-agent、in-progress、done。
- Approval 只描述用户授权，只允许 draft 或 approved。

ready-for-agent 只表示材料完整、可由 Agent 执行，不等于用户批准。Matt spec.md 必须单独记录 Approval、Approved at 和 Approval evidence；每张 ticket 必须记录同一次 Delivery Plan 批准。只有全部 ticket 的批准记录一致，完整 graph 才算获批。

新增、删除、拆分、合并 ticket 或改变 blocking edge 后，完整 ticket graph 恢复 draft 并重新整体批准。skill 自动发布文件不得自行写成 approved。

## 单一执行来源与 profile 切换

Feature Contract 必须声明 Workflow profile: matt 或 Workflow profile: superpowers。选定后，只有该 profile 的 Feature Contract 与 Delivery Plan 能授权实现。

中途切换必须通过获批修订说明：

1. 切换原因；
2. 旧产物的终止状态；
3. 新旧范围、需求与验收条件映射；
4. 未完成工作的迁移边界。

旧产物保留为历史，但切换后不再授权后续实现。不得同时把 Superpowers Plan 和 Matt tickets 当作执行来源。

## Release Authorization

Feature Contract 和 Delivery Plan 只授权其中明确写明的本地实现、测试与 commit。以下操作必须在 Delivery Plan 或独立 release ticket 中明确列出并获得对应授权：

- Git push、PR 创建或合并；
- 远程 migration、生产写入、历史回刷或修复；
- Vercel 或其他生产部署；
- Worker 安装、重启、常驻调度；
- 真实 Provider 调用；
- 会改变外部状态的登录态生产验收。

高风险 Agent 能力采用 Matt 时，ticket graph 必须覆盖 release gate、回滚、失败恢复、脱敏与真实页面验收。工作流变化不降低 Invest Hub 的生产安全标准。

## 文档权威边界

| 文档 | 权威内容 |
| --- | --- |
| docs/intake.md | 项目背景、需求输入、历史方案与原始约束 |
| docs/project-status.md | 当前阶段、批准状态、已完成结果与下一门禁 |
| docs/project-pitfalls-reflections.md | 跨任务失败模式与防复发检查 |
| CONTEXT.md | 共享领域语言 |
| docs/adr/ | 跨 feature、难以逆转的架构决策 |
| Feature Contract | 当前 feature 的问题、范围、合同与验收标准 |
| Delivery Plan | 实现切片、阻塞关系、验证与发布步骤 |
| Engineering Journal / Final Report | 实际执行证据、偏差、结果与未决风险 |

后位文档不能事后补造前位授权：CONTEXT/ADR 不替代 Feature Contract，Journal/Final Report 不替代批准记录，pitfalls 不替代 Spec 或 Delivery Plan。
