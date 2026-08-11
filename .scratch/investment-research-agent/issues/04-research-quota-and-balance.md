Workflow profile: matt
Status: done
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: None — Ticket 02 integrated at defea96cae3dc98f285cd07a248f8678449836b2

# 04 — Research Quota 管理与用户余额

**What to build:** 让管理员为 Test Identity 分配或调整终身 Research Quota，并让用户在 Agent 页面看到可用余额；建立后续 Run 可原子调用的 reservation、commit 和 release 权威，而不引入周期额度或 token 计费。

**Blocked by:** 02 — 私有 Research Thread 聊天骨架.

**Status:** done

- [x] 每个用户具有可审计的终身 Research Quota 余额；不存在月度重置、token 额度、Tool 调用计费或 Thread 数量计费。
- [x] 管理员可以在独立 Agent 管理区域分配或调整余额，普通用户只能读取自己的可用余额。
- [x] 用户 Agent 页面持续显示可用余额，并明确区分 available、reserved 和已结算用量，避免前端自行计算权威余额。
- [x] 数据库提供原子 reservation、commit 和 release 语义；相同请求重复提交不会重复预占、结算或释放。
- [x] 余额不足时拒绝 reservation；并发事务不能产生负余额或超过可用额度的多个有效 reservation。
- [x] 管理员额度变更记录真实管理员身份、目标用户、前后值、原因和时间，且普通用户不能伪造审计事件。
- [x] 所有 quota、ledger 和 reservation 数据按 owner/RLS 与管理员边界保护，service-role 凭据不进入浏览器。
- [x] pgTAP/RPC、API 和页面测试证明额度管理与原子语义；尚未与 Agent Run 绑定的 reservation 不被描述为已完成研究。

## Comments

- 2026-08-11：已完成本地实现与验证。Supabase 全量 pgTAP 44 files/728 tests、Control Plane 全量 Vitest 51 files/266 tests、Ticket 04 API/page tests 13/13 通过；本地 advisor 未发现 Ticket 04 新增表的警告。未执行远程 migration、部署或生产验收。真实多会话并发压测与 Agent Run admission 由后续 Ticket 05/16 负责，本 Ticket 的 RPC 已以数据库锁和幂等约束提供调用边界。
