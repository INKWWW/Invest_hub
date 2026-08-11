Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准完整 ticket graph”
Blocked by: None — can start immediately after the complete ticket graph is approved

# 01 — Codex CLI 运行合同与安全事件 Spike

**What to build:** 用一条代表性投资研究和一次取消操作验证真实 Codex CLI 运行边界，形成可供网站 Agent 使用的 Provider-neutral 事件合同、生产候选 parser、安全 Research Progress 映射和脱敏 fixtures。该 Spike 同时确认免费公开来源能力及受控进程终止行为，不把 CLI 帮助文本当作运行合同。

**Blocked by:** None — can start immediately after the complete ticket graph is approved.

**Status:** ready-for-agent

- [ ] 在记录实际 CLI 版本和本地授权边界后，使用 `codex exec --json` 完成一条支持范围内的代表性投资研究；调用不写远程数据库、不推进生产状态，也不保留私有完整响应到 Git。
- [ ] 代表性 case 的输入不含答案元数据，能够通过生产候选 parser 形成最终回答、来源信息和安全进度事件；严重 schema、证据或脱敏违规必须 fail-closed。
- [ ] 实际 JSONL 事件被归纳为版本化、Provider-neutral 的生命周期、Tool/来源进度、安全摘要、终态与错误类别；前端合同不依赖 Codex 私有字段名。
- [ ] 验证公开网络、公司或监管披露的可用访问路径与来源/日期提取能力；若免费来源能力不足，明确记录 blocker，不通过任意 shell 或未经批准的数据源绕过。
- [ ] 执行一次真实取消，确认进程组在有界时间内终止、没有孤儿进程、取消后不会形成晚到成功结果。
- [ ] malformed JSONL、未知事件、截断输出、超时、Provider failure 和取消均有确定性 parser 结果，不会把不完整输出伪装成成功。
- [ ] 只从已脱敏的事件形状制作回归 fixtures；Prompt、完整模型响应、Chain-of-thought、密钥、Cookie、本地路径和私有来源正文不进入仓库。
- [ ] 输出一份安全 Spike 报告，列出已证明合同、未证明能力、失败类别和 Ticket 05/07/13 可依赖的明确边界。

## Comments

- 2026-08-11：完整 Delivery Plan 已获用户批准；本票可以在其有界、本地、非生产边界内执行代表性真实 Codex 调用，仍不得据此执行 Ticket 17 的外部状态操作。
