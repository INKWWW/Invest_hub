# 管理员来源创建简化工程记录

日期：2026-07-25

## 实现范围

- 新建 Discord 来源只接收“显示名称（社区名 · 频道名）”；新建 X 博主只接收“X 账号”和“展示名称”。
- 服务端为新来源生成 `<source_type>:<UUID>` 内部键，并固定写入 Discord `discord-standard-v1` 或 X `x-standard-v2` 默认契约。浏览器不能提交、查看或覆盖这些技术值。
- 两个创建 API 均拒绝 `source_key`、`parameter_version` 及其他额外字段，只返回来源类型、展示名称和 X 的 `pending` 安全状态。
- X 账号输入会在展示名称尚未人工编辑时建议 `@账号`；人工改名后，后续账号修改不会覆盖该名称。
- “标准采集（推荐）· 系统自动维护”是说明性状态，不制造没有真实语义的版本选择；未来只有存在经验证的兼容方案时才增加用户可选项。

## 边界

本次只改变新建来源的控制面交互与服务端默认值。它不迁移数据库，不修改已有来源的内部键或参数版本，也不改变任务、coverage、checkpoint、Worker、Reader 或真实来源数据。

## 本地验证

| 范围 | 命令 | 结果 |
| --- | --- | --- |
| 服务端创建契约 | `cd apps/control-plane && npm test -- --run src/lib/source-creation.test.ts src/app/api/api.integration.test.ts` | 2 个文件、53 项通过 |
| 表单交互逻辑 | `cd apps/control-plane && npm test -- --run src/components/admin/source-create-form.test.tsx src/components/admin/x-source-form.test.tsx` | 2 个文件、5 项通过 |
| 控制面全量回归 | `cd apps/control-plane && npm test` | 30 个测试文件、131 项通过 |
| 静态质量 | `cd apps/control-plane && npm run lint && npm run build` | lint 与 production build 通过 |
| 发布前安全检查 | `bash scripts/v0/redact-check.sh && git diff --check` | `redaction_check: pass`；diff 检查通过 |

## 合并与部署

- `codex/source-create-simplification` 已 fast-forward 合并至本地 `main`，并在合并结果上再次通过 30 个前端测试文件、131 项测试。
- 已部署至既有 Vercel production 项目，部署 `dpl_Bjez5Hn1gtJWWWV4cadUabQ7mH9Y` 状态为 `Ready`；稳定别名为 `https://invest-hub-v0-control-plane.vercel.app`。
- 匿名连通性检查访问 `/admin/sources` 后到达 `200 https://invest-hub-v0-control-plane.vercel.app/login?next=%2Fadmin`，确认路由可达且仍受登录保护。管理员登录后可直接体验新建来源表单。
- 本次不需要、也没有执行 Supabase migration。
