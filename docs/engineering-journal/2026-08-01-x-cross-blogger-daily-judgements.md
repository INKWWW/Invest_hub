# X 跨博主当日判断总结：regeneration 本地验收记录

日期：2026-08-01

## 当前结论

已批准的显式 regeneration 语义已在本地确定性边界验证：同一 batch 的 revision 1 保持不可改写，管理员再生成经既有 `claim_next_x_daily_judgement` Worker 路径领取并完成后追加 revision 2，Reader 只投影 revision 2。实际 `GET /api/reader/x` handler 在 `NextResponse.json` 前建立 runtime whitelist，只复制 `XReaderDate` 的 Reader-safe 字段；route test 向 `readXDay` mock 注入 raw sentinel、provider、prompt、task、内部 ID 和本地路径，证明这些字段不会因未来 repository DTO 回归而泄露。Python synthetic fixture 不再被用作 Reader 或 HTML 的生产证明。

这只是本地验证，不代表 remote migration、控制面部署、Worker 重启、真实 X/OpenCLI/Browser 读取、真实 Codex CLI 调用或生产页面验收已经执行。没有新增 Worker 命令，也没有自动再生成调度循环。

## 本地验证结果

| 范围 | 命令 | 结果 |
| --- | --- | --- |
| pgTAP | `supabase db reset`；`supabase test db` | reset 成功；29 files / 416 tests 通过。 |
| regeneration 边界 | 聚焦 Node route/repository tests | 3 files / 13 tests 通过：实际 Reader handler runtime whitelist、admin regeneration route、revision 2 safe projection。 |
| regeneration Worker | `test_x_cross_blogger_judgements.py` | 11/11 通过；标准 claim 完成 regeneration 且来源 task/coverage fixture 不变。 |
| V2 runner | `V2_PYTHON_BIN=/opt/homebrew/bin/python3.12 bash scripts/v2/run-v2-e2e.sh` | 两个本地 OpenCLI 门禁通过；V2 4/4、V1.1 16/16、control-plane 95/95 和 regeneration Node 13/13 通过；0 skipped。 |
| 全量 Worker | `PYTHONPATH=workers/v0/src /opt/homebrew/bin/python3.12 -m unittest discover -s workers/v0/tests -p 'test_*.py' -v` | 未通过：112 tests 通过，4 个模块因本 worktree 无 virtualenv 且 Python 3.12 缺少 `jsonschema` 无法导入（`test_cli`、`test_contracts`、`test_protocol`、`test_x_windowed_runtime`）；未安装依赖或改写环境。 |
| 控制面测试与 lint | `npm test`；`npm run lint` | 42 files / 194 tests 通过；lint 通过。 |
| 默认 build | `npm run build` | 未通过：既有未跟踪 `node_modules` symlink 指向 filesystem root 外，Next Turbopack 拒绝该布局。此失败仍是 plan-required 默认命令的环境门禁。 |
| supplemental Webpack build | `npm run build -- --webpack` | 通过，32 个路由完成 production build；不能替代默认 build。 |
| 脱敏与格式 | `bash scripts/v0/redact-check.sh`；`git diff --check` | `redaction_check: pass`；diff 检查通过。 |

## 受控生产验收清单（仅准备，未授权执行）

| 项目 | 执行前必须确认/操作 | 当前状态 |
| --- | --- | --- |
| 目标 Supabase project/ref | 通过生产 control-plane 的 server-only binding 做只读、脱敏核对；不得从历史 Vercel 项目名或域名推断。 | 未确认，未读取 Sensitive value。 |
| additive migrations | 按顺序核对并仅在明确授权后应用 `20260801090000_x_cross_blogger_daily_judgements.sql`、`20260801100000_x_daily_judgement_hardening.sql`、`20260801120000_x_daily_judgement_worker_protocol.sql`、`20260801130000_x_daily_judgement_completion_lease_and_metadata.sql`、`20260801140000_x_daily_judgement_regeneration.sql`。 | 未应用。 |
| rollback switch | 停止新的 judgement claiming，并回退 Reader projection 到前一已验证 control-plane release；保留 immutable batches/runs/versions，绝不删除或改写既有 X task、coverage、segment、analysis 或 checkpoint。 | 仅有步骤，未执行。 |
| X Worker | 服务名 `com.investhub.x-worker`；只在单独授权后重启或使其领取新 judgement。 | 未重启。 |
| revision 1 → 2 | 在生产中先确认已成功且有 revision 1 的 batch；管理员显式 regenerate 后，由正常 Worker claim 领取，并验证 revision 1 保留、revision 2 成为 Reader 投影。 | 未执行。 |
| Reader | 使用已认证普通用户检查 `/x` desktop 与 375px、日期顺序、单博主范围说明和无敏感字段。 | 未执行。 |

在用户逐项明确授权前，不得执行 remote migration、Vercel deploy、`com.investhub.x-worker` 重启、真实 X/OpenCLI/Browser 读取或对真实内容调用 Codex CLI。
