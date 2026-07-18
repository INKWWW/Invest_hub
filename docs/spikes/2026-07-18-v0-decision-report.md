# V0 Final Report — 基础设施与技术验证

Last updated: 2026-07-18

## Decision

**Conditional pass（确定性基础设施通过；真实页面与远程部署待补证据）**。

V0 的最小闭环已在公开 fixture、Mock Provider、本地 Supabase 和脱敏控制面边界中验证：邀请码与角色隔离、Worker 生命周期、单任务 lease、raw → Canonical → structured 证据链、checkpoint 安全推进、Provider 超时回收和管理员调试面均有可复现测试。由于本次没有可授权的真实 Discord Profile/source，也没有隔离 V0 远程部署目标，不能宣称已完成 V0 的部署端到端验收或真实页面验收。

## Acceptance matrix

| 验收项 | 结论 | Evidence / command | 限制 |
| --- | --- | --- | --- |
| 跨语言 contract 拒绝非法字段 | pass | `tests://v0/contracts`; Worker contract tests | 只验证公开 fixture |
| Supabase schema、RLS、invite single-use | pass | `db://v0/rls/001`; `supabase test db` — 44 assertions | local DB only |
| Admin/user API and task state | pass | `tests://v0/control-plane`; 28 Vitest tests | no remote deployment |
| Worker enrol/heartbeat/claim/result | pass | `tests://v0/worker`; 40 unittest tests | deterministic transport and fake clock boundaries |
| Active Adapter freshness/deadline | pass | `tests://v0/active-adapter` | no real browser page in this report |
| Mock/Codex Provider boundary | pass | `tests://v0/provider`; process-group and schema tests | no new real Codex capacity claim |
| Media evidence linkage | pass | `e2e://v0/deterministic`; exact source-ID assertions | public fixture only |
| Admin debug redaction and retry gating | pass | `tests://v0/admin`; `npm run lint`; `npm run build` | view is an operational debug surface, not reader UI |
| Deterministic recovery | pass | `e2e://v0/deterministic`; 7 tests | in-memory control plane, not deployed HTTP |
| Repository redaction | pass | `checks://v0/redaction`; `bash scripts/v0/redact-check.sh` | checks credential-shaped values, not semantic review |
| Authorized real Discord increment | conditional | `preflight://v0/real-discord` | Profile/source authorization was not supplied |
| Deployed V0 HTTP/auth/recovery | conditional | `deploy://v0/pending` | isolated Supabase/Vercel target and credentials absent |

## Implemented delivery

- Contract schemas and loaders under `contracts/v0`.
- Next.js/Supabase control plane with role-bound admin APIs, task/lease RPC integration and redacted admin pages.
- Python 3.11+ Worker with owner-only config/credential storage, recovery states, Active Adapter, Canonical mapping, checkpoint guard and local evidence.
- Mock/Codex CLI Provider boundary with read-only/ephemeral invocation, bounded process-group timeout cleanup, retry policy and strict structured/media-source validation.
- Deterministic E2E harness, real-page preflight gate, redaction check and V0 environment template.

## Known limits and V1 gate

V0 不交付普通用户正式阅读页、不接入 X、不提供多来源运营、不实现 GLM 或自动 fallback。真实 Discord 运行必须由管理员明确提供已登录专用 Profile 和有权限来源，并在仓库外保存 evidence；远程部署必须使用隔离的 V0 项目和不含真实生产数据的凭据。V1 Spec 只有在这两项 conditional 验收补齐、并重新确认 Codex c100/c5/240 秒/最多 3 次运行行为后才能开始。

## Sensitive-data statement

本报告不包含 Discord/X 正文、真实 URL、Profile 路径、Cookie、Token、邀请码、Prompt 正文、完整模型响应或本地 evidence 内容；报告中的 evidence ref 均为逻辑标识。

