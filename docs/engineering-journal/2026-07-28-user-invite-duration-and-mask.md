# 普通用户邀请码时长与掩码列表工程记录

日期：2026-07-28

## 实现范围

- 普通用户邀请码改为 8 位 ASCII 字母数字，并在每个码中强制包含大写字母、小写字母和数字；字符类别不固定位置。
- 管理员每次创建时填写 1–168 小时，默认 24 小时；服务端以同一创建基准写入 `created_at` 与 `expires_at`。
- 新记录只保存 HMAC 验证值、`Ab••••7Q` 形式的 `code_mask` 和 `validity_hours`；完整码只在创建响应中显示一次。
- `/admin` 普通用户邀请码卡片下方显示最近 20 条普通用户记录，并按服务端过期时间每秒更新有效、已过期、已使用状态。
- Worker 邀请码继续使用现有长随机 SHA-256 路径和既有 Worker 表单时长，不进入普通用户列表。
- 兑换失败按来源 HMAC 限制为 5 次失败/15 分钟；数据库不保存原始 IP，失败响应统一为 `invalid_invite`。

## 数据库与控制面验证

| 范围 | 命令 | 结果 |
| --- | --- | --- |
| 新增 pgTAP | `SUPABASE_DISABLE_TELEMETRY=1 supabase test db supabase/tests/021_user_invite_duration_and_mask.sql` | 1 个文件、18 条断言通过 |
| 数据库全量 | `SUPABASE_DISABLE_TELEMETRY=1 supabase db reset --yes && SUPABASE_DISABLE_TELEMETRY=1 supabase test db` | 24 个文件、315 条断言通过 |
| 控制面全量 | `cd apps/control-plane && npm test` | 37 个测试文件、165 条通过 |
| 静态质量 | `cd apps/control-plane && npm run lint && npm run build` | lint 与 Next.js production build 通过 |
| 发布前安全检查 | `bash scripts/v0/redact-check.sh && git diff --check` | `redaction_check: pass`；diff 检查通过 |

## 敏感数据边界

测试与工程记录不包含真实邀请码、账号、IP、pepper、Cookie、浏览器 Profile、私有来源或完整响应。`INVITE_CODE_PEPPER` 只存在于 server-only 环境契约；`.env.example` 仅保留空值名称。

## 网页验收状态

本地网页验收已完成：管理员在 `/admin` 每次填写 `2` 小时并创建成功；页面仅在创建成功状态中显示一次完整码，列表显示 `Hh••••wN` 形式掩码、`2 小时` 和实时倒计时；等待约 1 秒后倒计时递减；刷新页面后完整码消失，掩码、时长和倒计时仍从数据库加载。验收使用本地临时管理员账号和本地 Supabase，未写入 Git 或工程记录。

目标 Vercel 项目当前不在本次 CLI 身份的可见项目列表中，且生产 `pull` 会尝试下载敏感环境变量，因此未绕过权限继续操作生产配置。待获得目标 Vercel 项目访问权并配置独立 `INVITE_CODE_PEPPER` 后，才能执行受保护生产页面验收；本次结果不宣称已完成生产部署。
