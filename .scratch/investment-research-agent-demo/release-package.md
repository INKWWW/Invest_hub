# 投资研究 Agent 最小 Demo：本地验收包

日期：2026-08-16

## 结论

本次已在同一隔离 worktree 内完成 6-ticket Demo 的最小实现收口，并执行了获批的 Supabase additive migration 与 Vercel production deployment。数据库、纯合同、Skill 文件隔离、Control Plane、Worker 和 production build 已通过；真实 Codex 已进入本机 Runner 探针，但当前执行环境无法解析 `chatgpt.com`，因此真实 Provider/生产页面验收停在外网执行面。

## 已实现范围

- 一般问答 Demo Run：用户消息与 Run 原子 admission、Worker claim/complete、owner-bound 回读、页面轮询和 scripted Provider seam。
- 一般问答合同：版本化产品指令、Thread 历史上限、来源/引用/投资建议校验和固定免责声明。
- Skill 路由：三个按钮/三个开头命令、显式优先、Auto/general/refuse 闭集、单 Run 最多一个 Skill，以及 `invocation_mode`/`skill_id` 持久化。
- Skill 隔离：冻结 commit `d64751635308d1920bcdae234e6dd957fd79e736` 的三份 `SKILL.md`、两个明确引用工具、provenance/hash 校验、Run 目录路径和 symlink 隔离。
- 并发与隔离：全局单 active Run、Worker freshness、busy/offline 拒绝、请求幂等、失败后新 request、owner RLS。
- 本机 Runner：新增一次一 Run 的 `run-agent-demo` CLI、`agent_demo` heartbeat capability、真实 Codex last-message 接缝、隔离 Codex Home 和终态临时目录清理；不安装常驻 launchd 服务，不复用旧 X/Discord Runner。

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
| Worker 全量回归 | `PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v` | 204/204 通过 |
| scripted/real Demo Worker seam | `test_agent_demo`、`test_protocol`、`test_cli` | 43/43 通过 |
| Python 语法 | `py_compile`（Demo/Skill 文件） | 通过 |
| diff 空白 | `git diff --check` | 通过 |

## 未通过或未执行

- 完整 `npx tsc --noEmit` 仍报告 9 个既有非 Demo 测试类型错误，主要位于 X Reader、API integration 和 Invite 测试；Demo 相关类型错误已清零，Next production build 的 TypeScript 阶段已通过。
- 真实 Codex/Skill 探针已执行但失败：登录态存在，`chatgpt.com` DNS/连接不可用，Codex WebSocket/HTTPS 均报告 `stream disconnected before completion`；原始模型响应未进入报告或 Supabase。
- 已执行目标 Supabase 的 additive migration 和 Vercel production deployment；Supabase migration history 使用 MCP 产生了新的登记时间戳，未做 history repair。
- Runner 尚未安装或重启为常驻服务；生产 Test Identity 页面验收、真实三 Skill case、portfolio、多轮恢复、busy/offline 仍未执行。
- 未进行 375px/桌面浏览器 E2E；因此 Ticket 06 仍为 `in-progress`。

## Release Authorization 门禁

当前 Release Authorization 已获用户明确批准；已执行 migration/deployment，但真实 Runner/Provider 验收在外网 DNS 边界停止。恢复验收只需在允许访问 `chatgpt.com` 的同一 Runner 环境重新执行一次代表性 case，再继续 Test Identity 页面矩阵；不应将当前本地 PASS 宣称为真实 Demo 发布完成。
