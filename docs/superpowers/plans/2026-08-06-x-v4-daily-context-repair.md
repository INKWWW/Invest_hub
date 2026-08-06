# X v4 当日判断上下文生产修复计划

**授权：** 用户于 2026-08-06 明确要求“修复上述问题”。本计划只恢复已批准的 [X 判断对象范围与阅读展示 Spec](../specs/2026-08-05-x-judgement-scope-and-reader-presentation-design.md) 中既定的 v4 正常链路，不新增产品范围或改变数据合同。

## 根因与边界

生产数据库和 Worker 已使用 `v4-x-*` 合同，但 Control Plane 的 `x-daily-judgements` repository 仍按 `v3-x-*` 解析 RPC context，导致合法 v4 context 在 Provider 调用前被拒绝为 `schema_error`。历史失败 run、采集数据和冻结证据保持不可变；修复不得直接 DML、重置 attempt 或重新采集 X。现有 manual recovery 会冻结当前全部来源，不能精确重跑一个历史 partial batch；因此补充一个仅 `service_role` 可调用的窄口径恢复 RPC，只允许 `judgement_failed + zero versions + failed run + provider input + no active run` 的原冻结 batch 新增受审计 run。

## 执行步骤

- [x] 在 repository test 中加入生产等价 v4 RPC fixture，并确认旧 parser 以 `invalid_x_daily_judgement_context` 红灯失败。
- [x] 将正常 daily judgement repository 的 context、analysis、window、completion TypeScript 合同升级为 v4，并保留独立 v3 verification replay 不变。
- [x] 将终态 `judgement_failed` 文案改为“已停止自动重试”，不再承诺不存在的自动重试。
- [x] 用 pgTAP 锁定失败 batch 恢复的状态、权限、零版本、Provider 输入、活动 run 和不可变证据门禁，再实现 `recover_failed_x_daily_judgement`。
- [x] 运行 Control Plane 聚焦/全量测试、lint、production build，运行全量 Worker 与 Supabase 回归，并执行 diff/redact gate。
- [ ] 提交并合入 `main`、推送远端、部署 Control Plane、重启同提交 Worker，确认稳定域名指向 Ready deployment。
- [ ] 通过受控恢复机制处理 2026-08-06 00:00、08:00、12:00、16:00、20:00 中实际终态失败的窗口；保留旧 run 和证据。
- [ ] 以生产数据库 v4 version、Worker telemetry 和已登录 `/x` 页面完成端到端验收，更新工程记录与 `docs/project-status.md`。

## 回滚与验收

若新部署不能读取 v4 context 或完成 v4 写回，立即停止新的 judgement 领取并回滚 Control Plane 到上一 Ready deployment；不删除任何 batch、run、version 或 evidence。完成标准是至少一个真实冻结批次经正常 repository → Worker → completion → DB 路径写入 `v4-x-cross-blogger`，且 Reader 可见、无秘密或内部 ID 泄漏。
