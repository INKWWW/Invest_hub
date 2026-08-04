# X 跨博主当日判断总结：最终边界本地验收记录

## 08:00 v3 一次性验证回放生产执行（2026-08-04）

production 已应用 `20260804081609_x_v3_verification_replay_0800.sql`，并确认四张 replay 表和 completion RPC 存在。Control Plane 的 v3 replay API 已在 Vercel production Ready 部署中上线，稳定 `/x` 别名已切换到该部署；为解除平台阻断，Git author 已改为 GitHub 账户已验证邮箱后以无内容提交重新触发部署。该 author 修复不改动应用、数据库或定时任务。

在精确预检通过后，只创建了一条面向 `2026-08-04T08:00+08:00` judgement-failed batch 的冻结 replay。它冻结了 3 个 included 来源，未创建 sync task，原 batch 仍保持 `judgement_failed`。one-shot Worker 只运行 `run-x-v3-verification`，没有启动 OpenCLI、浏览器采集或 normal scheduler。单帖 v3、博主窗口 v3 和每日 v3 输出均完成本地结构化解析，但最终 completion 持久化边界终态为 `persistence_failure`；没有写入 replay segment、replay version 或 v3 analysis。该 replay 的 attempt=1 已 terminal failed，按批准的 fail-closed/no-retry 约束不重跑、不新建第二条验证链，也不回写原 08:00 judgement。

## Worker Protocol v3 断层修复（2026-08-04，本地验证）

v3 Prompt 发布后，`XDailyJudgementRuntime` 已固定构造 `v3-x-cross-blogger-1` context 和 `v3-x-cross-blogger` completion，但 `WorkerProtocol` 仍只接受 v2。于是 Worker 会在调用 Provider 前拒绝有效的 v3 context；即使越过该处，旧 completion validator 也会拒绝三类 v3 输出。该本地 ProtocolError 没有 failure class，旧代码将它默认登记为 `persistence_failure`，从而错误描述为持久化失败。

用户批准的最小修复只改 Worker 的本地 HTTP 边界：context 只接受 v3 prompt version，completion 只接受三类 v3 arrays 及其行动倾向、范围、条件、来源、分析、证据和不确定性字段；Runtime 继续是来源归属、证据闭包、opaque ID 和系统建议的权威验证点。Worker 对 ProtocolError 现在提交 `schema_error`。未改数据库、控制面、Reader、调度、单帖/窗口 Prompt 或任何历史 judgement，也未手工创建任务、调用 Provider 或回写生产记录。

TDD 先证明有效 v3 context 被旧 Protocol 拒绝、v2 却被旧 Protocol 接受，并证明旧 ProtocolError 被记为 `persistence_failure`；最小实现后，聚焦 Protocol 18 tests、Worker recovery 13 tests 和完整 Worker 168 tests 全部通过。`git diff --check` 与 `bash scripts/v0/redact-check.sh` 均通过。提交 `4b6ba4a` 已推送到 `origin/main`；`com.investhub.x-worker` 已用 `launchctl kickstart -k` 重启，launchd 状态为 `running`，进程工作目录为本仓库 checkout。只读数据库查询确认本次没有创建 run，2026-08-03 20:00 与次日 00:00 的三个 attempt 终态失败记录仍不可变地保留。没有控制面、数据库或 Reader 改动，故不做 Vercel deployment；后续仅由下一次正常 scheduler 产生新的 v3 judgement，不会回刷 2026-08-03 或恢复其终态失败 run。

## Prompt v3 本地验收（2026-08-03）

在用户确认的 v3 Prompt 合同下，新增版本化公共 Prompt `v3-x-cross-blogger-1`。新生成记录将内容分为“个股与产业判断”“市场结构判断”“投资策略与心态”三类；`action_intent` 仅记录博主明确表达的建仓、买入、加仓、持有、减仓、卖出、观望或回避，且必须同时给出其适用范围。模型、Worker、Worker HTTP、数据库和 Reader 均拒绝或隐藏未经合同校验的操作倾向、系统建议、内部 ID 和非投资内容。历史 v2 记录未被改写，仍以原来的两类安全展示。

本地确定性证据为：新增 v3 Worker schema 测试，完整 Worker 回归 165 tests 通过；新增 v3 pgTAP 契约测试，完整数据库回归 35 files / 580 tests 通过；控制面 42 files / 232 tests 通过，Reader 投影与界面测试覆盖第三类、行动倾向和条件；lint 与默认 `next build` 均通过。production 已应用 `20260803100000_x_daily_judgement_prompt_v3.sql` 并由远端 migration history 确认，control-plane deployment `dpl_EfqWarB463BqpLjEdeSXZx9nxkbU` 为 Ready，稳定入口为 `https://invest-hub-v0-control-plane.vercel.app/x`。新版本机 Worker 已恢复并从 main 加载。已认证 `/x` 只读验收确认页面层级、筛选、覆盖说明和历史 v2 阅读均正常；没有为了展示 v3 而伪造博主输入或回写任何历史判断。新三类栏目将在下一次正常 v3 judgement 持久化后显示。

日期：2026-08-01

## 当前结论

[初始 Plan](../superpowers/plans/2026-07-31-x-cross-blogger-daily-judgement-summary.md)、[再生成 Plan](../superpowers/plans/2026-08-01-x-daily-judgement-regeneration.md)、[最终边界修复 Plan](../superpowers/plans/2026-08-01-x-daily-judgement-final-remediation.md)和[最终审查修复 Plan](../superpowers/plans/2026-08-01-x-daily-judgement-final-review-remediation.md)四个已批准 Implementation Plan 的本地确定性 gate 已执行。数据库生命周期结论只以真实 pgTAP 为 authority：`026_v2_x_daily_judgement_completion_lease.sql`、`026_v2_x_daily_judgement_regeneration.sql`、`027_v2_x_daily_judgement_batch_identity.sql`、`028_v2_x_daily_judgement_state_security.sql` 和 `029_v2_x_daily_judgement_final_authority.sql` 直接验证 00:00 上海 cutoff 归属前一自然日、完整冻结 enabled/resolved 来源、落后来源保留为 `partial`、租约三次上限、initial/regeneration 终态失败区别，以及 immutable revision 1 → 2。仓库不再保留模拟这些数据库状态转移的 cross-blogger Python state-machine。

最终审查修复补齐两条此前未闭合的投影与授权边界。Reader DTO 只有在真实持久化 version 存在时才公开 `complete`、`partial` 或 `no_new_information`；collecting、judgement pending、judgement failed 等无 version 状态统一为 `coverageStatus: null`，HTTP runtime whitelist 还会把 revision 0 或未知 coverage 值降为 `null`，UI 继续显示处理中/失败正文而不出现伪造的“无新信息”。数据库保持 ensure 的当前 enabled/resolved 来源资格不变，但新增冻结 claim authority：Worker 必须 online、心跳在两分钟内且具有 `x_sync` capability，其 X 授权从 immutable batch source snapshot 关联的来源取得，不再依赖当前 source/profile enabled。pgTAP 直接归档该 Worker 的全部当前 enabled/resolved 来源，证明既有 queued regeneration 仍由原授权 Worker 领取，未授权 Worker 仍被拒绝，且 batch-source snapshot、immutable version input 和 source coverage 均不改变。

Worker 边界由实际 `test_cli.py`、`test_x_cross_blogger_judgements.py`、`test_protocol.py` 和 `test_worker_recovery.py` 验证，覆盖 scheduled CLI 保留 `judgement_dispatch_failed` 的安全布尔 telemetry、绝不透传私有调度详情、结构化证据关系、管理员 regeneration 走标准 claim/complete、协议安全字段和失败不影响来源 coverage。前置 V1 control-plane 聚焦组实际运行 `api.integration.test.ts`，其中包含 Worker completion API；final Node 组不重复运行该文件。实际 `GET /api/reader/x` handler 在 `NextResponse.json` 前建立 runtime whitelist，只复制 `XReaderDate` 的 Reader-safe 字段；Node route test 向 `readXDay` mock 注入 raw sentinel、provider、prompt、task、内部 ID 和本地路径，证明这些字段不会因未来 repository DTO 回归而泄露。final Node 组直接运行其余实际 route、repository、page 和 component tests，覆盖 Reader safe output、管理员 regeneration、revision history，以及 all/source/date URL hydration 与双向恢复。

这只是本地验证，不代表 remote migration、控制面部署、Worker 重启、真实 X/OpenCLI/Browser 读取、真实 Codex CLI 调用或生产页面验收已经执行。没有新增 Worker 命令，也没有自动再生成调度循环。

2026-08-02 的 production preflight 发现远端 history 已记录 `20260731084640`，但仓库缺少同版本文件，故 `supabase db push --linked --dry-run` 正确拒绝继续。该版本在 2026-07-31 工程记录中已被确认是终态失败来源隔离修复，且已只读确认远端 `public.enqueue_due_x_tasks` 保留 `deferred_source_ids`。本次只新增同版本的本地历史 marker：它只执行 `select 1`，不重放 DDL，空库再由 `20260731100000_x_defer_terminal_failed_sources.sql` 提供最终 `create or replace function` 定义。对账 pgTAP 3/3 与该函数的既有终态失败隔离回归 6/6 已在本地通过；禁止 `migration repair`、`db pull`、Dashboard SQL 或推测性历史 SQL。此时 marker 尚未进入远端，因此尚未重试 remote dry-run，也没有执行新的 remote migration、Vercel deploy、Worker restart、真实 X/Codex 调用或 authenticated `/x` 验收。

## 生产对账与页面验收（2026-08-02）

对账分支快进至 `main` 并推送 `origin/main` 后，远端 dry-run 不再报告缺失 history，且只列出十条计划内 migration：`20260731100000`、`20260801090000`、`20260801100000`、`20260801120000`、`20260801130000`、`20260801140000`、`20260801150000`、`20260801160000`、`20260801170000` 和 `20260801180000`。实际 `supabase db push --linked` 逐条应用了这十条 migration；命令随后只在本地 migration catalog cache 阶段报告缺少临时证书文件，故没有把 CLI 结束语作为成功依据。独立只读核对确认远端 history 已包含 `20260731084640` 加上述十条版本，并确认 `public.enqueue_due_x_tasks` 仍含 `deferred_source_ids`。

control-plane 目录被精确链接到 Vercel 项目 `invest-hub-v1-control-plane`，随后 production deployment `dpl_8TVpwmZfW2FnYmJ2zNJQdLV5Hxbb` 为 Ready。稳定别名 `https://invest-hub-v0-control-plane.vercel.app` 已直接核对指向该 deployment；匿名 `/x` 请求仍转至 `/login?next=%2Fx`。`com.investhub.x-worker` 已通过 `launchctl kickstart -k` 重启，check-only 验证报告 loaded。没有通过临时脚本创建 task、读取真实 X 内容或调用 Codex；后续 judgement 只由正常 scheduler 处理。

已认证普通用户会话在正式 `/x` 完成了实际验收。只记录结构性结果，不复制真实内容：页面无错误覆盖层；包含博主与日期两个筛选控件；10 个日期卡片按降序；每个卡片的结构为日期、当日判断总结、单个博主观点；页面存在 3 个 judgement batch 和 47 个独立博主区块。375px 本地截图检查显示页面没有横向溢出，筛选与当日判断总结均保持可读。

## 当日判断延迟结算宽限期发布（2026-08-03）

用户授权后，`20260802160849_x_daily_judgement_grace_deadline.sql` 已在 production 应用，远端 history 已独立核对包含该版本。它只对正常调度器在此后新建的 X batch 生效：同一上海 `natural_date` 的 08:00、12:00、16:00、20:00 与次日 00:00 cutoff 统一在次日 01:00 结算；既有 batch、来源结算、coverage、judgement run 和 version 均保持不可变。实际 migration 应用后的本地 catalog 缓存出现证书文件缺失警告，但远端 migration list 已确认该版本存在，因此不以该缓存警告否定已应用结果。

控制面 production deployment `dpl_6FSB8fZgQok6JpZUHweZQvjYKhwB` 为 Ready，稳定入口仍为 `https://invest-hub-v0-control-plane.vercel.app/x`；匿名请求继续重定向登录页，`com.investhub.x-worker` check-only 为 loaded。已认证生产 Reader 的只读验收确认日期、当日判断总结、单个博主观点顺序保持正确；历史超时 batch 显示“采集超时，未形成判断”，展开后显示未纳入来源与结算截止前未完成采集的说明，页面不存在内部排除字段。当天存在较晚窗口的博主卡按最新窗口投影，未出现可单独展示的超时卡；该卡的专用提示已由组件测试覆盖。没有手工创建采集任务、调用 Provider 或回写历史数据。

同日后续最小 Reader 发布 `dpl_4tk1xe5KcHBNeF2Dud9D4HCAD7Cv` 在每个已完成的 judgement batch 顶部增加输入覆盖说明：已纳入观点数、无新增数、未纳入数，并明确下方主题只列出直接支持或反对该主题的博主。已认证 production `/x` 在“全部日期”视图中确认该说明存在、判断区正常加载、内部排除字段未显示；未创建任务、调用 Provider 或改变任何历史 judgement。

## 本地验证结果

| 范围 | 命令 | 结果 |
| --- | --- | --- |
| 数据库生命周期 authority | V2 runner 内的 `supabase db reset`；`supabase test db` | 初始 reset 成功；32 files / 561 tests 通过，其中 judgement 026/027/028/029 直接验证真实 DB 状态转移。2026-08-02 对账 marker 加入后，merged `main` 全量 pgTAP 为 33 files / 564 tests 通过。 |
| judgement Worker 聚焦组 | V2 runner 显式运行 `test_cli.py`、`test_x_cross_blogger_judgements.py`、`test_protocol.py`、`test_worker_recovery.py` | 58/58 通过；scheduled CLI telemetry 保留安全失败布尔值且不输出细节；没有 cross-blogger synthetic state-machine 或重复 discovery。 |
| final Node 边界 | V2 runner 中去重后的实际 route/repository/page/component 聚焦组 | 8 files / 40 tests 通过：Reader runtime whitelist、admin regeneration、revision history、all/source/date URL 恢复；Worker completion API 已由前置 control-plane 组的 `api.integration.test.ts` 覆盖。 |
| 全量 Worker | `PYTHONPATH=workers/v0/src /Users/hanyuec/Desktop/Invest_hub/workers/v0/.venv/bin/python -m unittest discover -s workers/v0/tests -p 'test_*.py' -v` | 使用现有 main V0 virtualenv；161/161 通过。 |
| V2 runner | `V2_PYTHON_BIN=/Users/hanyuec/Desktop/Invest_hub/workers/v0/.venv/bin/python bash scripts/v2/run-v2-e2e.sh` | 两个本地 OpenCLI 静态/fixture 门禁、数据库 32 files / 561 tests、judgement Worker 58/58、既有 V2 collection/recovery fixture 3/3、V1.1 16/16、control-plane 聚焦组 6 files / 120 tests、去重后的 final Node 聚焦组 8 files / 40 tests 通过；0 skipped。 |
| 控制面测试与 lint | `npm test`；`npm run lint` | 42 files / 232 tests 通过；lint 通过。 |
| 默认 build | `npm run build` | **未通过（exit 1）**：Next.js 16.2.10 Turbopack 报 `Symlink [project]/node_modules is invalid, it points out of the filesystem root`。本 worktree 的既有未跟踪 `node_modules` symlink 指向主工作区依赖目录；这是 plan-required 默认命令的环境失败，不能标记为 build 通过。 |
| supplemental Webpack build | `npm run build -- --webpack` | 通过；Next.js 16.2.10 Webpack 完成 TypeScript 和 32 个页面的 production build。它只提供独立补充证据，不能替代默认 Turbopack build。 |
| 脱敏与格式 | `bash scripts/v0/redact-check.sh`；`git diff --check` | `redaction_check: pass`；diff 检查通过。 |

## 受控生产验收清单（仅准备，未授权执行）

| 项目 | 执行前必须确认/操作 | 当前状态 |
| --- | --- | --- |
| 目标 Supabase project/ref | production control-plane 已精确链接到 `invest-hub-v1-control-plane`；Supabase CLI 的 linked history 通过既有 X production terminal-failure version 与十条 judgement migration 做只读核对。未读取 Sensitive value。 | 已完成受控核对。 |
| additive migrations | 先确认远端已匹配本地历史 marker `20260731084640_x_defer_terminal_failed_sources_historical_marker.sql`，再按顺序仅应用 `20260731100000_x_defer_terminal_failed_sources.sql`、`20260801090000_x_cross_blogger_daily_judgements.sql`、`20260801100000_x_daily_judgement_hardening.sql`、`20260801120000_x_daily_judgement_worker_protocol.sql`、`20260801130000_x_daily_judgement_completion_lease_and_metadata.sql`、`20260801140000_x_daily_judgement_regeneration.sql`、`20260801150000_x_daily_judgement_batch_identity.sql`、`20260801160000_x_daily_judgement_state_security.sql`、`20260801170000_x_daily_judgement_final_authority.sql`、`20260801180000_x_daily_judgement_frozen_claim_authority.sql`。 | remote marker 已存在；其余十条未应用。 |
| rollback switch | 停止新的 judgement claiming，并回退 Reader projection 到前一已验证 control-plane release；保留 immutable batches/runs/versions，绝不删除或改写既有 X task、coverage、segment、analysis 或 checkpoint。 | 仅有步骤，未执行。 |
| X Worker | 服务名 `com.investhub.x-worker`；只在单独授权后重启或使其领取新 judgement。 | 已通过 `launchctl kickstart -k` 重启，check-only 状态为 loaded。 |
| revision 1 → 2 | 在生产中先确认已成功且有 revision 1 的 batch；管理员显式 regenerate 后，由正常 Worker claim 领取，并验证 revision 1 保留、revision 2 成为 Reader 投影。 | 未执行。 |
| Reader | 使用已认证普通用户检查 `/x` desktop 与 375px、日期顺序、单博主范围说明和无敏感字段。 | 已执行；桌面及 375px 通过，结构、筛选、登录保护与无错误覆盖层均符合预期。 |

在用户逐项明确授权前，不得执行 remote migration、Vercel deploy、`com.investhub.x-worker` 重启、真实 X/OpenCLI/Browser 读取或对真实内容调用 Codex CLI。
