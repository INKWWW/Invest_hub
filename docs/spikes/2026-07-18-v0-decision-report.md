# V0 最终报告——基础设施与技术验证

最后更新：2026-07-19

## 决策

**有条件通过（确定性基础设施通过；真实页面与远程部署待补证据）**。

V0 的最小闭环已在公开测试样例、Mock 提供方、本地 Supabase 和脱敏控制面边界中验证：邀请码与角色隔离、Worker 生命周期、单任务租约、原始数据 → 规范数据 → 结构化输出的证据链、检查点安全推进、提供方超时回收和管理员调试面均有可复现测试。2026-07-19 又完成隔离 Supabase 迁移、Vercel Preview 部署、Worker 远程持久化收据和管理端操作入口；但没有可授权的真实 Discord 专用浏览器配置档和来源，且 Vercel SSO 阻断无会话 HTTP 探针，因此不能宣称已完成真实页面或已部署应用端到端验收。

## 验收矩阵

| 验收项 | 结论 | 证据 / 命令 | 限制 |
| --- | --- | --- | --- |
| 跨语言契约拒绝非法字段 | 通过 | `tests://v0/contracts`；Worker 契约测试 | 只验证公开测试样例 |
| Supabase 数据结构、RLS、邀请码单次使用 | 通过 | `db://v0/rls/001-002`；`supabase test db`——55 条断言 | 远程仅确认迁移版本，不含真实数据 |
| 管理员/普通用户 API 与任务状态 | 通过 | `tests://v0/control-plane`；30 个 Vitest 测试 | 应用级远程 HTTP 尚待登录会话验证 |
| Worker 注册/心跳/领取/持久化/结果 | 通过 | `tests://v0/worker`；44 个单元测试 | 仅覆盖确定性传输与模拟时钟边界 |
| Active Adapter 新鲜度/截止时间 | 通过 | `tests://v0/active-adapter` | 本报告未包含真实浏览器页面 |
| Mock/Codex 提供方边界 | 通过 | `tests://v0/provider`；进程组与数据结构测试 | 未新增真实 Codex 容量结论 |
| 媒体证据关联 | 通过 | `e2e://v0/deterministic`；精确来源 ID 断言 | 仅使用公开测试样例 |
| 管理员调试脱敏与重试门禁 | 通过 | `tests://v0/admin`；`npm run lint`；`npm run build` | 这是运维调试界面，不是普通用户阅读界面 |
| 确定性恢复 | 通过 | `e2e://v0/deterministic`；7 个测试 | 使用内存控制面，未验证已部署 HTTP |
| 仓库脱敏 | 通过 | `checks://v0/redaction`；`bash scripts/v0/redact-check.sh` | 检查凭据形态值，不替代语义审查 |
| 已授权真实 Discord 增量 | 有条件 | `preflight://v0/real-discord` | 尚未提供浏览器配置档/来源授权 |
| 隔离 Supabase 迁移与 Vercel Preview 构建 | 通过 | `deploy://v0/preview-ready`；远程迁移 `001/002`、Preview Ready | Vercel SSO 阻断无会话应用 HTTP 探针 |
| 已部署 V0 HTTP/认证/恢复 | 有条件 | `deploy://v0/https-sso-gated` | 需在已登录 Vercel 会话中执行应用级验收 |

## 已交付内容

- `contracts/v0` 下的契约数据结构与加载器。
- 基于 Next.js/Supabase 的控制面，包含按角色约束的管理员 API、任务/租约 RPC 集成和脱敏管理员页面。
- Python 3.11+ Worker，包含仅所有者可访问的配置/凭据存储、恢复状态、Active Adapter、Canonical 映射、检查点守卫和本地证据。
- Mock/Codex CLI 提供方边界，包含只读/临时调用、有界进程组超时清理、重试策略，以及严格的结构化输出/媒体来源校验。
- 确定性端到端测试框架、真实页面预检门禁、脱敏检查和 V0 环境模板。
- 隔离远程持久化协议：Worker 先提交原始保留引用、规范消息、结构化输出和证据关联；数据库核验持久化收据后才允许结果推进 checkpoint。
- 最小管理员操作入口：创建逻辑来源和手动同步任务，不收集 Discord URL、Profile、Prompt 或正文。

## 已知限制与 V1 门禁

V0 不交付普通用户正式阅读页、不接入 X、不提供多来源运营、不实现 GLM 或自动回退。真实 Discord 运行必须由管理员明确提供已登录专用浏览器配置档和有权限来源，并在仓库外保存证据；远程部署必须使用隔离的 V0 项目和不含真实生产数据的凭据。只有在这两项有条件验收补齐、并重新确认 Codex c100/c5/240 秒/最多 3 次运行行为后，才能开始 V1 规格文档。

## 敏感数据声明

本报告不包含 Discord/X 正文、真实 URL、浏览器配置档路径、Cookie、Token、邀请码、提示词正文、完整模型响应或本地证据内容；报告中的证据引用均为逻辑标识。
