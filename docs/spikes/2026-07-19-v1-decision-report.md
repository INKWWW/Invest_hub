# V1 Final Report: Discord 正式可用 MVP

日期：2026-07-19（2026-07-21 更新）
结论：**Pass — V1 Discord 正式可用 MVP。**

## 判定原则

V1 的本质不是“页面能构建”，而是受邀用户能够在隔离环境中安全读取真实生成内容，同时每个来源的失败、证据与 checkpoint 都可追溯。缺少真实双来源和部署验收时，不能把本地通过外推为正式可用。

## 验收矩阵

| # | 验收项 | 结论 | 脱敏证据与限制 |
| --- | --- | --- | --- |
| 1 | 管理员/普通用户在正式登录网页读取相同内容 | pass | 受邀普通用户已在独立正常会话完成注册、登录与真实 `/discord` 阅读；两个来源、日期、batch 与历史版本均可用。邀请码与账号未记录。 |
| 2 | 桌面与手机阅读流程 | pass | 正式普通用户桌面会话（宽度高于 `1280px`）和用户确认的 `375px` 手机会话通过来源/日期切换、batch 展开与无横向溢出；公开 fixture 的精确 `1280px`/`375px` 布局检查仍通过。 |
| 3 | 普通用户不能读取管理/敏感数据 | pass | 真实 `/admin` 访问安全重定向；未认证 reader API 为 `401`。API 授权测试、RLS pgTAP 和 reader allowlist 继续通过，响应不含 local raw ref、Worker 或密钥字段。浏览器扩展对一条直接管理 API 导航的客户端拦截未被误记为服务端授权结果。 |
| 4 | 管理两个来源与规则覆盖 | pass | 规则快照、来源绑定、管理 API/UI 和公开双来源 fixture 均通过。 |
| 5 | 两来源真实授权增量与独立 checkpoint | pass | 两个真实授权来源完成两轮 `incremental`、`max_pages=1` 验收；共 4 个任务均在首次 attempt 成功。第一轮新增 30 条 Canonical，第二轮新增 19 条，Worker 重复计数均为 0，数据库重复 Canonical 行为 0；每轮两个 checkpoint 均只在成功后前移。 |
| 6 | 有界 history 与离线恢复 | pass | 两个真实 `max_pages=1` history 任务通过；history scope 为 1–25 页，定时 E2E 验证四窗口有界补采与幂等。 |
| 7 | 单来源失败不前移 checkpoint、不阻断其他来源 | pass | 受控 A 映射移除产生 `retryable_failed/unauthorized`，零内容写入且 checkpoint 不前移；完整配置下 B 独立成功。A 随后通过管理员 Retry 恢复成功，保留 6 次 retry 与 1 次 succeeded 事件。诊断发现同 hash 重采集的本地 evidence 引用变化会被误判冲突，已由 `20260720165534` 修复并以 pgTAP 与真实恢复验证。 |
| 8 | 批次与日累计摘要可追溯且版本化 | pass | 迁移、摘要 receipt、pgTAP 和 Worker 摘要测试通过。 |
| 9 | 事实/观点/归纳/不确定性/媒体边界 | pass | 两来源最近成功任务各随机抽取至少一条 topic，共 `2` 个来源级样本；输入引用、目标作者规则、表达边界与未解析媒体覆盖均通过，严重错误归因与媒体臆测均为 `0`。 |
| 10 | 多来源、权限、恢复、阅读测试 | pass | pgTAP 115、控制面 54、Worker 62、V1 E2E 3 个测试均通过。 |
| 11 | 敏感资料不进入 Git、日志或页面 | pass | 脱敏检查、DTO allowlist、production runtime error 审阅及 owner-only evidence 权限复核通过；`106` 个文件为 `0600`，`51` 个目录为 `0700`，日志摘要不含真实正文或凭据。 |
| 12 | Final Report 记录实际结论和限制 | pass | 本报告逐项标注 pass/conditional，未把缺失真实证据写成通过。 |

## 已验证的交付物

- 迁移 `003`–`006` 覆盖多来源、规则、摘要、收据和定时窗口幂等。
- 本地 Worker 使用 Active Adapter 与 owner-only 多来源配置；没有引入 Discord REST、自身 Token 自动化、第二浏览器框架或自动 Provider fallback。
- 正式阅读页 `/discord` 面向已认证用户，管理员仍进入 `/admin`；阅读 UI 与管理诊断隔离。
- 阅读体验已发布到既有生产项目；普通用户真实阅读、桌面/手机响应式流程和 production 日志独立审阅已完成。未认证 reader API 为 `401`，真实正文没有写入仓库或日志。
- `scripts/v1/run-e2e.sh` 明确分离 deterministic 与 real-discord。real 模式同时要求授权标志、多来源私有配置、Prompt、OpenCLI contract、受保护 evidence 目录和一次性 Worker 凭据。
- 真实双来源增量验收已完成两轮：两轮均为每来源 `incremental/max_pages=1`；四个任务全在首次 attempt 成功，第一轮新增 30 条、第二轮新增 19 条 Canonical，数据库未发现重复 Canonical 行。其后的受控失败隔离与 A 正式恢复也已通过：同 hash 的 9 条重采集消息不会重复持久化，只有 1 条新消息写入。来源标识、URL、正文、Prompt 与本机 evidence 均未进入仓库。

## MVP 运行边界与下一门槛

第 1–11 项均已通过，因此本报告确认 **V1 Discord 正式可用 MVP**。该结论不构成生产 SLA，也不涵盖 X、媒体/OCR/外部正文解析、独立用户来源、自动 fallback 或长期无人值守稳定性。任何后续范围均须先完成独立 Spec 与 implementation plan。

本报告对应的实现已于 2026-07-21 合并至 `main` 并推送至 GitHub `origin/main`（发布核对 commit：`c493256`）。后续新对话应将本报告和 Project Status 作为 V1 已完成的事实记录；开始后续范围前，仍须经过新的 Spec 与 Plan 门禁。

2026-07-21 的产品审阅进一步收敛了阅读页面：batch 默认展开，前台不再展示原始消息/evidence 模块；底层证据关系与安全边界保持不变。
