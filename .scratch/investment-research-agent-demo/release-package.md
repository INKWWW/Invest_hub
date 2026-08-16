# 投资研究 Agent 最小 Demo：本地验收包

日期：2026-08-16

## 结论

本次已在同一隔离 worktree 内完成 6-ticket Demo 的最小实现收口，形成可读的本地验收证据，但还没有执行外部发布。数据库、纯合同、Skill 文件隔离、Control Plane、Worker 和 production build 已通过；完整 typecheck 仍有既有非 Demo 测试类型错误，真实浏览器/真实 Provider 仍是发布门禁。

## 已实现范围

- 一般问答 Demo Run：用户消息与 Run 原子 admission、Worker claim/complete、owner-bound 回读、页面轮询和 scripted Provider seam。
- 一般问答合同：版本化产品指令、Thread 历史上限、来源/引用/投资建议校验和固定免责声明。
- Skill 路由：三个按钮/三个开头命令、显式优先、Auto/general/refuse 闭集、单 Run 最多一个 Skill，以及 `invocation_mode`/`skill_id` 持久化。
- Skill 隔离：冻结 commit `d64751635308d1920bcdae234e6dd957fd79e736` 的三份 `SKILL.md`、两个明确引用工具、provenance/hash 校验、Run 目录路径和 symlink 隔离。
- 并发与隔离：全局单 active Run、Worker freshness、busy/offline 拒绝、请求幂等、失败后新 request、owner RLS。

## 可回读验证

| 范围 | 命令/证据 | 结果 |
|---|---|---|
| 全量 Supabase 回归 | `supabase test db --local` | 47 files / 760 tests 通过 |
| Demo vertical slice | `supabase test db --local supabase/tests/054_agent_demo_vertical_slice.sql` | 16/16 通过 |
| Busy/offline/RLS | `supabase test db --local supabase/tests/055_agent_demo_admission_isolation.sql` | 8/8 通过 |
| Skill metadata | `supabase test db --local supabase/tests/056_agent_demo_skill_metadata.sql` | 8/8 通过 |
| 既有 Thread/RLS | `supabase test db --local supabase/tests/038_agent_research_threads.sql` | 27/27 通过 |
| 既有 Quota 回归 | `supabase test db --local supabase/tests/039_agent_research_quota.sql` | 38/38 通过 |
| Control Plane | `npm test` | 56 files / 285 tests 通过 |
| Control Plane lint | `npm run lint` | 通过 |
| Control Plane production build | `npm run build` | 通过 |
| 纯 Agent 合同 | Contract、General Answer、Skill Routing、Safe Markdown Vitest | 18/18 通过 |
| Skill Runtime | `test_skill_runtime` | 5/5 通过 |
| scripted Demo Worker seam | `test_agent_demo` | 4/4 通过 |
| Python 语法 | `py_compile`（Demo/Skill 文件） | 通过 |
| diff 空白 | `git diff --check` | 通过 |

## 未通过或未执行

- 完整 `npx tsc --noEmit` 仍报告 9 个既有非 Demo 测试类型错误，主要位于 X Reader、API integration 和 Invite 测试；Demo 相关类型错误已清零，Next production build 的 TypeScript 阶段已通过。
- 未执行真实 Codex、真实 Skill 外网调用、远程 migration、生产 Supabase 写入、Vercel deployment、Runner 安装/重启和生产页面验收。
- 未进行 375px/桌面浏览器 E2E；因此 Ticket 06 仍为 `in-progress`。

## Release Authorization 门禁

如需继续发布，必须由用户另行明确批准 Release Authorization；批准后才可按 Ticket 06 顺序执行远程 migration dry-run、部署、Runner 变更、真实 Provider/Skill case 和已登录生产验收。当前没有执行任何上述外部状态操作。
