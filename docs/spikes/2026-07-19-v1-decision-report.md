# V1 Final Report: Discord 正式可用 MVP

日期：2026-07-19（2026-07-20 更新）
结论：**Conditional — 确定性实现、隔离部署和真实双来源有界 history 通过，尚未达到“Discord 正式可用 MVP”发布门槛。**

## 判定原则

V1 的本质不是“页面能构建”，而是受邀用户能够在隔离环境中安全读取真实生成内容，同时每个来源的失败、证据与 checkpoint 都可追溯。缺少真实双来源和部署验收时，不能把本地通过外推为正式可用。

## 验收矩阵

| # | 验收项 | 结论 | 脱敏证据与限制 |
| --- | --- | --- | --- |
| 1 | 管理员/普通用户在正式登录网页读取相同内容 | conditional | 管理员已在正式网页登录，`/discord`、安全 reader API 和公开双来源 fixture 已通过；尚未以普通用户完成真实内容阅读。 |
| 2 | 桌面与手机阅读流程 | conditional | 响应式频道/日期选择和单列样式已构建；人工公开 fixture 在 `1280px` 与 `375px` 通过来源/日期切换、无横向溢出与 batch/evidence 展开检查；尚未以普通用户在正式环境阅读真实内容。 |
| 3 | 普通用户不能读取管理/敏感数据 | pass | API 授权测试、RLS pgTAP 和 reader allowlist 通过；响应不含 local raw ref、Worker 或密钥字段。 |
| 4 | 管理两个来源与规则覆盖 | pass | 规则快照、来源绑定、管理 API/UI 和公开双来源 fixture 均通过。 |
| 5 | 两来源真实授权增量与独立 checkpoint | conditional | 两个真实授权来源各完成一次 `history`、`max_pages=1` 任务，且均持久化成功；仍缺真实增量、第二次无重复和独立 checkpoint 推进证据。 |
| 6 | 有界 history 与离线恢复 | pass | 两个真实 `max_pages=1` history 任务通过；history scope 为 1–25 页，定时 E2E 验证四窗口有界补采与幂等。 |
| 7 | 单来源失败不前移 checkpoint、不阻断其他来源 | conditional | 真实运行保留了一个 `retryable_failed` 后重试成功，另一个来源已独立成功；但该失败记录为 `unknown`，尚未完成一项预设、可操作分类的真实隔离验收。 |
| 8 | 批次与日累计摘要可追溯且版本化 | pass | 迁移、摘要 receipt、pgTAP 和 Worker 摘要测试通过。 |
| 9 | 事实/观点/归纳/不确定性/媒体边界 | conditional | 公开 fixture 与既有 schema 约束通过；V1 尚无真实运行的人工质量证据。 |
| 10 | 多来源、权限、恢复、阅读测试 | pass | pgTAP 114、控制面 53、Worker 60、V1 E2E 3 个测试均通过。 |
| 11 | 敏感资料不进入 Git、日志或页面 | conditional | 仓库脱敏检查、DTO allowlist、受保护配置和本地 evidence 权限复核通过；本次生产发布只做无内容 `200`/`401` 探针，仍缺一次面向部署日志的独立审阅。 |
| 12 | Final Report 记录实际结论和限制 | pass | 本报告逐项标注 pass/conditional，未把缺失真实证据写成通过。 |

## 已验证的交付物

- 迁移 `003`–`006` 覆盖多来源、规则、摘要、收据和定时窗口幂等。
- 本地 Worker 使用 Active Adapter 与 owner-only 多来源配置；没有引入 Discord REST、自身 Token 自动化、第二浏览器框架或自动 Provider fallback。
- 正式阅读页 `/discord` 面向已认证用户，管理员仍进入 `/admin`；阅读 UI 与管理诊断隔离。
- 阅读体验已发布到既有生产项目；发布前全量数据库、控制面、Worker 与 V1 E2E 回归通过，生产探针仅确认首页 `200` 与未认证 reader API `401`，未读取真实 reader 内容。
- `scripts/v1/run-e2e.sh` 明确分离 deterministic 与 real-discord。real 模式同时要求授权标志、多来源私有配置、Prompt、OpenCLI contract、受保护 evidence 目录和一次性 Worker 凭据。

## 阻断项与下一门槛

1. 让两个真实来源各完成一次增量、再完成一次无重复的增量，并核验各自 checkpoint 只在成功后推进。
2. 在一个来源上进行受控的、可操作分类的失败，同时确认另一个来源不受阻断；真实 evidence 继续只保存在仓库外受保护目录。
3. 以普通用户完成正式阅读流程，并完成基于真实内容的桌面与手机端视觉验收。
4. 对至少一次真实输出进行人工质量抽检，并独立审阅部署日志。第 1–11 项全部通过前，项目状态必须保持“条件验收”，不得称为正式可用或生产 SLA。
