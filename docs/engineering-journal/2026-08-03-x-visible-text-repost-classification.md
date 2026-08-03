# 2026-08-03：X 可见正文与 repost 关系修正

## 结论

Collection 可同时返回 `relationship.kind = repost` 和非空可见正文。项目 Adapter 原先在该组合下主动清空正文，Canonicalizer 与单帖 Prompt 又把所有 repost 视为不可归因，导致正文在持久化前丢失。本次将限制收窄为“仅空正文 repost 不生成博主观点”。

## 确定性验证

- 先在旧实现下运行新增 Adapter/Canonicalizer 回归，分别验证到“正文被置空”和“非空 repost 被拒绝”的预期失败。
- 最小实现只修改 Adapter 文本映射、Canonicalizer 的错误前提与公开单帖 Prompt；关系 ID、上下文状态、回执、任务范围和 Reader DTO 未改。
- 使用项目 Python 3.12 虚拟环境运行 22 项 X Adapter、Canonicalizer、窗口运行时与结构化输出测试，全部通过；`git diff --check` 通过。

## 真实输入核验

在已登录的 owner X 会话中，对用户指出的稳定帖子执行了只读 Collection 重取。稳定 ID、作者和状态链接与生产记录一致，Collection 返回的正文非空，关系仍为 `repost`；因此该修复适用于真实输入，而非仅合成 fixture。

## 生产历史记录

这条帖子已经作为空正文写入生产，且 X 分析与窗口段为不可变事实。直接绕过不可变触发器的历史重写被安全门禁拒绝，未执行任何生产数据写入。后续必须由用户明确选择：仅该稳定帖的一次性受控勘误，或先实现可审计的正式勘误 RPC/migration。两者之外不会把网站上的旧记录称为已修复。
