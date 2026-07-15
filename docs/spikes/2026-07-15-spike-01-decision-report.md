# Spike-01 OpenCLI Discord 增量采集决策报告

## 报告状态

- 日期：2026-07-15
- 执行分支：`spike-01-implementation`
- 执行内容：本地确定性 harness、OpenCLI Browser Bridge 真实网页轨、bounded soak、1000+ 条真实采集和第二轮恢复验证
- OpenCLI：1.8.6；daemon 和 Browser Bridge extension 连接正常
- 真实数据：只写入用户本地受保护目录，没有进入 Git

本报告不批准 V0/V1 生产实现，只记录 Spike-01 的技术验证结果和后续设计输入。

## 1. 范围与安全边界

本次验证只使用用户本人已登录且有权限访问的 Discord 页面，采集过程只读，不发送消息、不修改频道内容、不访问其他网站。

没有安装生产依赖，没有初始化应用框架，没有使用 Playwright/CDP、Agent-Reach 或人工导出替代真实采集。人工操作只用于登录、重新打开页面和诊断网络观测，不向 evidence 注入消息数据。

真实 URL、Profile 路径、Cookie、Token、消息正文和完整附件链接未写入仓库。

## 2. 确定性验证轨

最终命令：

    PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_01/tests -v

结果：

- 测试总数：32
- 通过：32
- 失败：0
- 公开 fixture 完整率：100%
- fixture 重复写入率：0%
- checkpoint 越过未成功数据：0 次

覆盖内容包括：

- Canonical Schema 身份、作者、频道、时间、正文、回复、引用和附件元数据；
- 缺失作者、频道冲突、未知关系和重复消息的明确状态；
- raw、Canonical、ValidationReport 和 checkpoint 持久化；
- checkpoint 后置推进、中断恢复、失败隔离和重放去重；
- OpenCLI 非零退出、非 JSON、版本不一致、超时和 cursor 参数边界；
- 每页遥测、安全 match state 和 network 重试行为。

## 3. bounded soak

使用与正式运行相同的 OpenCLI contract、Profile、频道和证据结构完成限界采集：

- 14 页；
- 202 条原始消息；
- 194 条 accepted；
- 8 条 unresolved relation；
- 0 invalid、0 duplicate；
- 14 页均为 `matched_new`；
- checkpoint 成功后置推进。

页面耗时遥测可计算，单页耗时中位数约 6.9 秒，最大约 15.3 秒；network 尝试次数中位数为 1，最大为 9。单页硬截止仍为 90 秒。

## 4. 真实网页轨结果

第一轮真实采集通过 checkpoint-resume 累计达到目标以上：

- 按第一轮最终 checkpoint 边界：1392 条唯一 Canonical 消息；
- 必填字段缺失：0；
- Canonical ID 重复：0；
- 频道标识冲突：0；
- invalid：0；
- unresolved relation：存在，但保留原始关系信息并未阻止安全 checkpoint；
- network missing：出现过 6 次，均停止当前页并保留旧 checkpoint，随后通过恢复继续；
- 逐页遥测：共 113 条记录，其中 107 条 `matched_new`、6 条 `missing`；
- 页面耗时观测：中位数约 6.8 秒，最大约 16.2 秒；network 尝试次数最大为 20。

第二轮使用同一频道、Profile、contract 和 evidence，且使用新的 run ID，从第一轮末尾 checkpoint 继续：

- 8 页；
- 112 条原始消息；
- 110 条 accepted；
- 2 条 unresolved relation；
- 0 duplicate；
- 0 invalid；
- 状态：success。

两轮 evidence 合计 1504 条唯一 Canonical 消息。第二轮没有重复写入已采集 ID。

## 5. 实现修正与关键发现

真实运行暴露并修正了三个 harness 问题：

1. 当前页面可能是 Discord 消息深链，分页前必须规范化为频道根路由，避免生成嵌套 message 路径。
2. Discord 消息请求的 OpenCLI `key` 不包含 query 参数；陈旧响应判断必须使用 `request key + request URL`，不能只使用 key。
3. network 无响应时，必须进行一次带新 cache-buster 的有限重新打开，再继续有界等待；仍失败则返回 `missing` 并保留 checkpoint。

这些修正都由失败测试先锁定，再实现并通过完整测试。

## 6. OpenCLI-first 判定

结论：Spike-01 验证通过，但生产采用条件为“带恢复和可观测性地采用”，不是无条件宣称单次网页运行稳定。

已证明：

- OpenCLI Browser Bridge 能复用登录态并读取用户可见 Discord 内容；
- collector 实际采集超过 1000 条消息，未使用人工导出替代；
- 消息 ID、作者 ID、频道 ID、时间、正文和附件/关系字段可以进入 Canonical Schema；
- network freshness、失败分类、checkpoint 后置推进和恢复行为可验证；
- 第二轮真实运行没有重复写入。

仍需在后续正式 Spec/plan 中明确：

- network buffer 空窗是正常可恢复事件，不能静默忽略；
- 生产任务必须保留逐页 telemetry、失败窗口和恢复记录；
- 单次运行不应以“未出现错误”作为唯一成功标准，应以 checkpoint 和证据完整性判断；
- 登录态、Profile 生命周期和 OpenCLI 版本必须作为环境前置条件管理。

## 7. 后续建议

- 可以进入下一阶段的 V0 采集设计，但先把本 Spike 的恢复、freshness、90 秒硬截止和 evidence 约束写入 V0 specification；
- V0 implementation plan 不应直接复制 Spike harness，也不应把 Browser Bridge 的具体命令当作永久公共接口；
- 在 V0 实现前，继续保留 OpenCLI contract 版本校验和真实网页回归验收；
- 当前不引入 Desktop 客户端、Agent-Reach、Playwright/CDP 或第二套完整采集框架。

## 8. 最终自检

- 真实消息由 collector 实际获取，人工导出未计入 1000 条验收；
- 真实 evidence 未进入 Git；
- 公开 fixture、测试和 Spike harness 不含 Cookie、Token、Profile 文件或真实正文；
- 本次没有生成生产应用代码、框架脚手架或生产依赖；
- 32/32 确定性测试通过；
- 本报告只作为 Spike-01 决策记录，不等同于 V0/V1 生产批准。
