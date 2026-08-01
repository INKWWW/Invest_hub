# X 跨博主当日判断总结：最终边界本地验收记录

日期：2026-08-01

## 当前结论

已批准的初始 Implementation Plan 和最终边界修复 Implementation Plan 均已完成本地确定性验收。批次会冻结截止时刻的全部 enabled/resolved X 来源；00:00 上海 cutoff 归属前一自然日；落后来源保留在快照中并形成 `partial`，不会被隐藏。租约最多三次，initial 终态失败使 batch 进入 `judgement_failed`，regeneration 终态失败则保留既有 succeeded batch 和 immutable revision。同一 batch 的 revision 1 保持不可改写，管理员再生成经既有 `claim_next_x_daily_judgement` Worker 路径领取并完成后追加 revision 2，Reader 投影 revision 2 并保留安全的历史版本。

实际 `GET /api/reader/x` handler 在 `NextResponse.json` 前建立 runtime whitelist，只复制 `XReaderDate` 的 Reader-safe 字段；route test 向 `readXDay` mock 注入 raw sentinel、provider、prompt、task、内部 ID 和本地路径，证明这些字段不会因未来 repository DTO 回归而泄露。V2 runner 直接运行实际 Node route、repository、page 和 component tests，覆盖 Reader safe output、管理员 regeneration、revision history，以及 all/source/date URL hydration 与双向恢复。Python acceptance 只验证公开的本地批次/租约/版本状态，实际 Worker contract 由完整 Worker unittest 验证；synthetic fixture 不被当作 Reader route 或 HTML 的生产证明。

这只是本地验证，不代表 remote migration、控制面部署、Worker 重启、真实 X/OpenCLI/Browser 读取、真实 Codex CLI 调用或生产页面验收已经执行。没有新增 Worker 命令，也没有自动再生成调度循环。

## 本地验证结果

| 范围 | 命令 | 结果 |
| --- | --- | --- |
| pgTAP | `supabase db reset`；`supabase test db` | reset 成功；31 files / 496 tests 通过。 |
| final Node 边界 | V2 runner 中的实际 route/repository/page/component 聚焦组 | 9 files / 122 tests 通过：Worker completion API、Reader runtime whitelist、admin regeneration、revision history、all/source/date URL 恢复。 |
| 全量 Worker | `PYTHONPATH=workers/v0/src /Users/hanyuec/Desktop/Invest_hub/workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v` | 使用现有 main V0 virtualenv；156/156 通过。 |
| V2 runner | `V2_PYTHON_BIN=/Users/hanyuec/Desktop/Invest_hub/workers/v0/.venv/bin/python bash scripts/v2/run-v2-e2e.sh` | 两个本地 OpenCLI 静态/fixture 门禁通过；V2 8/8、V1.1 16/16、既有 control-plane 聚焦组 6 files / 107 tests、final Node 聚焦组 9 files / 122 tests 通过；0 skipped。 |
| 控制面测试与 lint | `npm test`；`npm run lint` | 42 files / 217 tests 通过；lint 通过。 |
| 默认 build | `npm run build` | **未通过（exit 1）**：Next.js 16.2.10 Turbopack 报 `Symlink [project]/node_modules is invalid, it points out of the filesystem root`。本 worktree 的既有未跟踪 `node_modules` symlink 指向主工作区依赖目录；这是 plan-required 默认命令的环境失败，不能标记为 build 通过。 |
| supplemental Webpack build | `npm run build -- --webpack` | 通过；Next.js 16.2.10 Webpack 完成 TypeScript 和 32 个页面的 production build。它只提供独立补充证据，不能替代默认 Turbopack build。 |
| 脱敏与格式 | `bash scripts/v0/redact-check.sh`；`git diff --check` | `redaction_check: pass`；diff 检查通过。 |

## 受控生产验收清单（仅准备，未授权执行）

| 项目 | 执行前必须确认/操作 | 当前状态 |
| --- | --- | --- |
| 目标 Supabase project/ref | 通过生产 control-plane 的 server-only binding 做只读、脱敏核对；不得从历史 Vercel 项目名或域名推断。 | 未确认，未读取 Sensitive value。 |
| additive migrations | 按顺序核对并仅在明确授权后应用 `20260801090000_x_cross_blogger_daily_judgements.sql`、`20260801100000_x_daily_judgement_hardening.sql`、`20260801120000_x_daily_judgement_worker_protocol.sql`、`20260801130000_x_daily_judgement_completion_lease_and_metadata.sql`、`20260801140000_x_daily_judgement_regeneration.sql`、`20260801150000_x_daily_judgement_batch_identity.sql`、`20260801160000_x_daily_judgement_state_security.sql`。 | 未应用。 |
| rollback switch | 停止新的 judgement claiming，并回退 Reader projection 到前一已验证 control-plane release；保留 immutable batches/runs/versions，绝不删除或改写既有 X task、coverage、segment、analysis 或 checkpoint。 | 仅有步骤，未执行。 |
| X Worker | 服务名 `com.investhub.x-worker`；只在单独授权后重启或使其领取新 judgement。 | 未重启。 |
| revision 1 → 2 | 在生产中先确认已成功且有 revision 1 的 batch；管理员显式 regenerate 后，由正常 Worker claim 领取，并验证 revision 1 保留、revision 2 成为 Reader 投影。 | 未执行。 |
| Reader | 使用已认证普通用户检查 `/x` desktop 与 375px、日期顺序、单博主范围说明和无敏感字段。 | 未执行。 |

在用户逐项明确授权前，不得执行 remote migration、Vercel deploy、`com.investhub.x-worker` 重启、真实 X/OpenCLI/Browser 读取或对真实内容调用 Codex CLI。
