# V1 Final Report: Discord 正式可用 MVP

日期：2026-07-19
结论：**Conditional — 确定性实现通过，尚未达到“Discord 正式可用 MVP”发布门槛。**

## 判定原则

V1 的本质不是“页面能构建”，而是受邀用户能够在隔离环境中安全读取真实生成内容，同时每个来源的失败、证据与 checkpoint 都可追溯。缺少真实双来源和部署验收时，不能把本地通过外推为正式可用。

## 验收矩阵

| # | 验收项 | 结论 | 脱敏证据与限制 |
| --- | --- | --- | --- |
| 1 | 管理员/普通用户在正式登录网页读取相同内容 | conditional | `/discord`、安全 reader API 和公开双来源 fixture 已通过；未在部署环境以真实账号完成阅读。 |
| 2 | 桌面与手机阅读流程 | conditional | 响应式频道/日期选择和单列样式已构建、组件逻辑测试通过；未做远程浏览器视觉验收。 |
| 3 | 普通用户不能读取管理/敏感数据 | pass | API 授权测试、RLS pgTAP 和 reader allowlist 通过；响应不含 local raw ref、Worker 或密钥字段。 |
| 4 | 管理两个来源与规则覆盖 | pass | 规则快照、来源绑定、管理 API/UI 和公开双来源 fixture 均通过。 |
| 5 | 两来源真实授权增量与独立 checkpoint | conditional | 公开 fixture 验证了双来源与独立 checkpoint；尚无真实 V1 双来源运行。 |
| 6 | 有界 history 与离线恢复 | pass | history scope 为 1–25 页；定时 E2E 验证了四窗口有界补采与幂等。 |
| 7 | 单来源失败不前移 checkpoint、不阻断其他来源 | pass | Provider 失败/来源 B 成功的 V1 E2E 通过，Worker 回归通过。 |
| 8 | 批次与日累计摘要可追溯且版本化 | pass | 迁移、摘要 receipt、pgTAP 和 Worker 摘要测试通过。 |
| 9 | 事实/观点/归纳/不确定性/媒体边界 | conditional | 公开 fixture 与既有 schema 约束通过；V1 尚无真实运行的人工质量证据。 |
| 10 | 多来源、权限、恢复、阅读测试 | pass | pgTAP 114、控制面 49、Worker 59、V1 E2E 3 个测试均通过。 |
| 11 | 敏感资料不进入 Git、日志或页面 | conditional | 仓库脱敏检查和 DTO allowlist 通过；尚未产生 V1 部署或真实运行日志供核验。 |
| 12 | Final Report 记录实际结论和限制 | pass | 本报告逐项标注 pass/conditional，未把缺失真实证据写成通过。 |

## 已验证的交付物

- 迁移 `003`–`006` 覆盖多来源、规则、摘要、收据和定时窗口幂等。
- 本地 Worker 使用 Active Adapter 与 owner-only 多来源配置；没有引入 Discord REST、自身 Token 自动化、第二浏览器框架或自动 Provider fallback。
- 正式阅读页 `/discord` 面向已认证用户，管理员仍进入 `/admin`；阅读 UI 与管理诊断隔离。
- `scripts/v1/run-e2e.sh` 明确分离 deterministic 与 real-discord。real 模式同时要求授权标志、多来源私有配置、Prompt、OpenCLI contract、受保护 evidence 目录和一次性 Worker 凭据。

## 阻断项与下一门槛

1. 提供明确的专用 V1 Supabase/Vercel 目标及所需部署凭据，完成迁移、部署与远程合成双来源验收。
2. 用户对至少两个正常可见 Discord 来源给予一次明确真实运行授权，并准备 owner-only 本地配置、Prompt、evidence 目录和 Worker 凭据。
3. 在正式网页完成双来源增量、一个有限 history、一个来源失败且另一来源继续成功的验收；真实 evidence 仅保存仓库外受保护目录。
4. 将上述脱敏计数和结论补入本报告。第 1–11 项全部通过前，项目状态必须保持“条件验收”，不得称为正式可用或生产 SLA。
