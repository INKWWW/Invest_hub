# X 租约过期窗口自动跳过 Scope Amendment

## 状态

- 状态：已批准的最小增量
- 日期：2026-08-17
- 依据：用户授权“按照方案方向进行，保持敏捷、简洁，不要过度设计复杂机制”
- 关联：`docs/superpowers/specs/2026-08-16-x-late-arrival-reader-projection-design.md`、`docs/superpowers/plans/2026-08-16-x-failed-window-skip.md`

## 必要变更

现有 `claim_next_task_v2_base` 在 X window 租约过期时会无限创建新的 attempt，导致单 Worker 被单一来源长期占用。对已经有两次 attempt 且再次租约过期的 X window，claim 前自动将当前 attempt 记为 `failed/lease_expired`，复用已有 `advance_x_failed_window_unchecked` 写入 gap 并推进该来源水位；随后同一次 claim 继续领取其他来源任务。

## 不变边界

- 第一次租约过期仍允许一次重试；X 总 attempt 不超过 2。
- 失败 task、attempt、task event 和 gap 都保留为事实；不伪造成功、不删除历史。
- gap 与 coverage advance 继续使用现有同事务 transition，`last_completed_task_id` 不变。
- 不修改 Worker 采集协议、Reader DTO、日报、Provider、真实采集、生产 migration 或部署。
- 不新增 Worker、监控服务、熔断器、恢复队列或后台按钮。

## 验收

隔离本地数据库中，来源 A 的两次租约过期必须生成两个 attempt、一个 gap 并推进 A 水位；同一次后续 claim 必须能领取来源 B 的 attempt 1。已有 explicit failure skip、Worker、Control Plane 和 Supabase 回归继续通过。
