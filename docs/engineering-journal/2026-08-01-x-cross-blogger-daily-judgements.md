# X 跨博主当日判断总结：确定性验收与受控生产清单

日期：2026-08-01

## 当前结论

Task 5 的非冲突确定性 E2E 覆盖、脚本入口和生产验收清单已准备，但本任务**不能标记为完成**。Spec §3 与验收标准 6 要求“判断重试成功”追加同一批次的 revision 2；现有 Task 1–3 状态机则在 Provider 失败时不写 version，并在成功后使唯一 run 终止，未提供对成功批次再次生成的授权路径。该情形在 E2E 中保留为明确的 skipped/blocked assertion，等待用户确认是否增加显式 regeneration 机制；没有为了让测试通过而改写现有失败状态机。

本记录不代表远程 migration、部署、Worker 重启、真实 X 读取或真实 Codex CLI 调用已经执行。公开 fixture 仅使用合成来源名、帖子标记和模型输出；其中的原文 sentinel 被安全投影与 HTML 断言排除。

## 实际本地验证结果

| 范围 | 命令 | 结果 |
| --- | --- | --- |
| 新增 E2E RED | `PYTHONPATH=workers/v0/src <existing-v0-venv>/bin/python -m unittest tests/e2e/v2/test_x_cross_blogger_daily_judgements.py -v` | 实现前 2 个用例因缺少 fixture `tick` 预期报错；指定 worktree 的 `workers/v0/.venv` 不存在，故使用现有主仓库 V0 virtualenv，不创建或修改依赖。 |
| 新增 E2E GREEN | 同上 | 2 个通过，1 个显式 skipped（revision-2 语义阻塞）。 |
| V2/V1.1 E2E runner | `V2_PYTHON_BIN=<existing-v0-venv>/bin/python bash scripts/v2/run-v2-e2e.sh` | 两个本地 OpenCLI 契约门禁通过；V2 discovery 6 个中 5 个通过、1 个 blocked skip；V1.1 5 个通过；脚本内 Worker window/scheduler 11 个通过；两组 control-plane 重点测试分别为 95 与 84 个通过。没有真实 OpenCLI/Browser/X/Codex 调用。 |
| 本地数据库 | `supabase db reset`、`supabase test db` | reset 成功；pgTAP 为 28 files / 386 tests 全部通过。首次受限沙箱仅因 CLI telemetry 写入被拒，受控本地重跑后通过。 |
| Worker | `PYTHONPATH=workers/v0/src <existing-v0-venv>/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v` | 152 个通过。 |
| 控制面测试与 lint | `cd apps/control-plane && npm test && npm run lint` | 40 files / 183 tests 通过；lint 通过。 |
| 控制面 build | `npm run build` | 未通过：worktree 中既有、未跟踪的 `node_modules` symlink 指向 filesystem root 外，Next Turbopack 拒绝该布局；未改变该目录。 |
| 等价 webpack build | `npm run build -- --webpack` | 通过，32 个路由完成 production build。 |
| 脱敏与格式 | `bash scripts/v0/redact-check.sh && git diff --check` | `redaction_check: pass`；diff 检查通过。 |

## 已覆盖的本地确定性行为

- 同一 cutoff 的重复 schedule tick 复用同一个 synthetic batch；三位合成博主中两位支持、第三位持不同意见的 complete judgement 正确投影。
- 一个来源被排除时生成 partial judgement，健康来源 coverage 前移，被排除来源 coverage 不前移；另一个来源无新增信息不被伪装为失败。
- 全部来源无新增信息时只形成 `no_new_information`，没有可 claim 的 judgement run。
- 过期 attempt 的 completion 被拒绝；Reader 日期倒序，单博主筛选只显示跨博主范围说明；ordinary 用户的 JSON/HTML 不含原文 sentinel、Provider、Prompt、任务或证据内部字段；375px fixture 输出单栏布局。
- `test_provider_retry_later_appends_revision_two_without_overwriting_revision_one` 保持 skipped，原因是上文所述 Spec §3/Plan Task 5 与当前状态机冲突，不能视为已验收。

## 受控生产验收清单（仅准备，未授权执行）

| 项目 | 执行前必须确认/操作 | 当前状态 |
| --- | --- | --- |
| 目标 Supabase project/ref | 通过生产 control-plane 的 server-only Supabase binding 做一次只读、脱敏核对，记录项目和 ref；不得从历史 Vercel 项目名或域名推断。 | 未确认，未读取 Sensitive value。 |
| additive migrations | 按顺序核对并仅在明确授权后应用 `20260801090000_x_cross_blogger_daily_judgements.sql`、`20260801120000_x_daily_judgement_worker_protocol.sql`、`20260801130000_x_daily_judgement_completion_lease_and_metadata.sql`。 | 未应用。 |
| rollback switch | 先停止新 judgement 的 scheduling/claiming，并将 Reader projection 回退到前一已验证 control-plane release；保留 immutable batches/runs/versions，绝不删除或改写既有 X tasks、coverage、segments、analyses 或 checkpoint。 | 仅有回滚步骤，未执行。 |
| X Worker | 服务名为 `com.investhub.x-worker`。只有取得单独授权后才可重启或使其领取新 judgement。 | 未重启。 |
| 正常批次 | 观察一个所有冻结来源完成的 complete batch，记录安全 cutoff、coverage、run 与 Reader 投影。 | 未执行。 |
| 部分批次 | 观察一个来源失败/隔离而健康来源继续完成的 partial batch，核对未纳入数量与各来源 coverage。 | 未执行。 |
| 无新增批次 | 观察一个所有完成来源均无新信息的 no-new batch，核对没有真实模型调用。 | 未执行。 |
| retry/revision | 观察一次 judgement Provider retry；在获得 revision regeneration 设计决定后，核对 revision history 不覆盖旧版本。 | 被 Spec/状态机冲突阻塞。 |
| Reader | 使用已认证普通用户检查 `/x` 的 desktop 与 375px 布局、日期顺序、单博主范围说明和无敏感字段。 | 未执行。 |
| 数据库只读核对 | 用授权的只读、脱敏查询核对 batch/run/version、来源结算与 coverage；不输出原文、Cookie、Prompt、Provider 原始诊断或本地 evidence 路径。 | 未执行。 |

## 授权边界

在用户逐项明确授权前，不得执行 remote migration、Vercel deploy、`com.investhub.x-worker` 重启、真实 X/OpenCLI/Browser 读取或对真实内容调用 Codex CLI。revision-2 语义还需要先获得独立的设计决定与计划更新；在此之前，生产清单中的 retry/revision 项不得执行。
