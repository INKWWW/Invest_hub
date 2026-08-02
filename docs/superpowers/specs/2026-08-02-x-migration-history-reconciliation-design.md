# X 生产 Migration 历史对账设计

**状态：** 已确认设计，待同一授权范围内的最小实现。

## 问题与事实

生产 Supabase 的 migration history 已记录 `20260731084640`，但当前仓库没有同版本文件；因此 `supabase db push --linked --dry-run` 安全拒绝继续。工程记录表明该远端版本是 2026-07-31 的 X 终态失败来源隔离修复，并已只读核对 `public.enqueue_due_x_tasks` 含 `deferred_source_ids` 逻辑。仓库中的 `20260731100000_x_defer_terminal_failed_sources.sql` 是同一修复的后续规范化版本，使用 `create or replace function` 定义最终函数。

该问题的本质不是业务 schema 缺失，而是不可重放的生产历史没有在仓库 migration 目录中留下版本身份。把远端 history 标记为 reverted、用 `db pull` 生成未审阅的大型 schema diff，或重新执行未知 SQL，都会把“对账”变成对既有生产状态的猜测性修改。

## 决策

新增一个版本为 `20260731084640` 的本地历史标记 migration。它只包含说明性注释和无副作用的 `select 1`，不创建、删除或变更任何数据库对象。它的作用是让仓库能够确认这条生产历史已经存在；在空数据库中，它会先作为无副作用版本记录，再由 `20260731100000` 定义可验证的最终调度函数。

生产发布顺序固定为：确认 linked project 的 history 与正式部署状态 → 对账 migration 合入并推送 `main` → `supabase db push --linked --dry-run` 确认仅剩十条已审阅 migration → `supabase db push --linked` → 只读核对 migration history 和函数定义 → 部署同一 `main` 提交 → 受控重启 X Worker → 真实、最小化 Reader 验收。任一步失败均停止后续步骤；回退时停止新的 judgement claiming 并回退 Reader deployment，不删除 immutable judgement 或既有 X 采集数据。

## 范围

本次仅新增历史标记 migration、一个 migration-history 对账测试/验证入口，以及必要的工程记录和状态更新。测试必须证明：空本地数据库可按顺序应用标记与 `20260731100000`，调度函数仍产生 `deferred_source_ids`，以及远端 dry-run 不再因 `20260731084640` 缺失而停止。

本次不使用 `supabase migration repair`、`supabase db pull` 或手工 Dashboard SQL；不改已有 migration 文件、不改 sources、coverage、checkpoint、tasks、judgement 数据或 RLS；不引入依赖、不新增 Provider/Collector 功能，也不在对账完成前部署或重启 Worker。

## 验收标准

1. `supabase migration list --linked` 显示 `20260731084640` 在本地与远端均存在，且远端缺失的十条 judgement migration 被明确列出。
2. 本地 `supabase db reset --yes` 与相关 pgTAP 测试通过，证明历史标记对空数据库没有业务副作用、最终调度函数保留终态失败来源隔离语义。
3. 远端 dry-run 不再报告“Remote migration versions not found in local migrations directory”；实际 `db push` 仅应用 `20260731100000` 至 `20260801180000`，不执行 repair、pull 或历史版本重放。
4. 远端只读查询确认十条版本存在，并确认 `public.enqueue_due_x_tasks` 仍公开 `deferred_source_ids`；随后生产部署、Worker 与 authenticated `/x` 验收均使用同一已推送 `main` 提交。

## 替代方案与拒绝原因

- `migration repair --status reverted 20260731084640`：会使已执行生产变更脱离 history，且无法恢复未知的原始 SQL，拒绝。
- `supabase db pull`：会把整个远端 schema 漂移带入本次最小修复，范围不可控，拒绝。
- 重写或补执行推测的 20260731084640 SQL：会对已存在对象产生不可预测副作用，拒绝。
