# 管理员来源配置工作台与 X 博主安全移除工程记录

日期：2026-07-25

## 本地实现范围

- `/admin/sources` 由八列表格改为独立的 `Discord 配置` 与 `X 配置` 工作区；URL 的 `type` 参数保留当前分区，档案卡只呈现展示名称、启停、生命周期、Worker 显示名和最近完成时间。
- 来源详情仅在管理员展开时显示相应类型的配置表单。Discord 继续使用来源资料、采集范围、规则和作者配置；X 使用博主资料、覆盖水位、更新/回填和危险操作。
- 新增 `remove_x_source` 原子 RPC：空 X 来源会物理删除；任一已有任务、覆盖或事实的来源会停用并归档；`queued`、`leased`、`running`、`retryable_failed` 任务均阻断该操作。
- 归档来源及 X profile 均停用，但不删除原始/Canonical 事实、观点段、任务、coverage 或证据关系。来源行锁与现有 X 任务创建路径串行化，避免归档与新任务创建竞态。
- 新增管理员 `DELETE /api/admin/x/sources/:sourceId`。它要求精确输入展示名称，只返回动作和展示名称；普通用户、格式错误、确认不匹配和活动任务均被明确拒绝。

## 本地验证

| 范围 | 命令 | 结果 |
| --- | --- | --- |
| 数据库生命周期 | `SUPABASE_DISABLE_TELEMETRY=1 supabase db reset && SUPABASE_DISABLE_TELEMETRY=1 supabase test db` | 21 个 pgTAP 文件、282 项通过 |
| 控制面 | `cd apps/control-plane && npm test` | 27 个测试文件、121 项通过 |
| 静态质量 | `npm run lint && npm run build` | lint 与 production build 通过 |
| 发布前安全检查 | `bash scripts/v0/redact-check.sh && git diff --check` | `redaction_check: pass`；diff 检查通过 |

桌面和 375px 样式由来源档案卡、单列详情与可滚动标签条覆盖；页面不再将配置表单嵌入表格单元格。键盘可切换来源类型，所有操作控件保持可见焦点和至少 44px 高度。

## 未执行的外部动作

本记录只覆盖本地数据库与前端验证。没有应用远程 migration、部署控制面、读取或写入真实来源数据，也没有对真实 X 博主执行删除或归档。上述任一动作都需要在合并后由管理员另行明确授权，并按实施计划中的绑定、脱敏与 Git 检查执行。
