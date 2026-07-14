# Spike-01 OpenCLI Discord 增量采集决策报告

## 报告状态

- 日期：2026-07-15
- 执行分支：spike-01-implementation
- Python：3.12.13
- 真实网页数据：已在用户专用 Profile 中只读验证
- OpenCLI：1.8.6；daemon 与 Browser Bridge extension 1.0.22 已连接

## 1. 执行范围

本次完成了本地确定性 harness、Canonical Schema、Validator、本地证据存储、checkpoint Emulator、Fake Connector、增量 Runner 和 OpenCLI 命令边界单元测试。

没有连接项目云端，没有安装生产依赖，没有保存 Cookie、Token、频道 URL 或真实消息正文。真实验证只使用了已绑定的专用 Chrome Profile 和 OpenCLI Browser Bridge。

## 2. 确定性验证轨

最终测试命令：

    PYTHONPATH=spikes /opt/homebrew/bin/python3.12 -m unittest discover -s spikes/spike_01/tests -v

结果：

- 测试总数：21
- 通过：21
- 失败：0
- 确定性 harness：通过

已验证：

- Canonical Schema 身份、作者、频道、时间、正文、原始链接；
- 回复、引用和附件元数据映射；
- 缺失作者 ID和频道冲突被标记 invalid；
- 未知回复/引用目标保留 unresolved_relation；
- raw、Canonical 和 ValidationReport 本地持久化；
- checkpoint round-trip 和原子提交；
- checkpoint 未提交时旧值保持不变；
- 二次运行使用已保存 checkpoint，不新增消息；
- 重置 checkpoint 重放时记录 duplicate，但不重复写入；
- 中断后从最后成功页面恢复；
- invalid 页面保留原始数据且不推进 checkpoint；
- 单来源失败不阻断另一来源；
- OpenCLI 非零退出、非 JSON、版本不一致和 cursor 参数边界。

确定性门槛：

- fixture 原始数据保存完整率：100%；
- 正常运行重复写入率：0%；
- checkpoint 越过未成功数据：0 次；
- 恢复后的 Canonical ID 集合与一次性运行一致。

## 3. 真实网页轨

真实网页轨已开始并完成了 OpenCLI Browser Bridge 和单页字段验证：

- `opencli doctor -v`：daemon、extension 和 connectivity 均通过；
- 已绑定一个 Discord 专用 Profile，登录态有效，能够访问用户可见的私有投研频道；
- OpenCLI 网络形状显示 Discord 消息接口返回 10、20 和 30 条 JSON 消息页；
- 一页 30 条真实消息中，消息 ID、频道 ID、时间、正文、作者 ID/显示名均完整；
- 同一页实际出现回复/引用字段和附件元数据；
- Discord 的 `around=<message_id>` 深链接可以通过 OpenCLI 触发历史页加载。

尚未完成的项目：

- 1000 条以上连续真实消息采集；
- 真实两轮 runner 执行和 checkpoint 幂等；
- 将 OpenCLI Browser 的 network/page envelope 映射为本 harness 需要的 RawPage contract。

通用 `browser scroll` 未能驱动 Discord 当前的虚拟滚动容器；通过 OpenCLI 深链接可以触发 `around` 分页，但这仍不是可直接供 runner 使用的稳定命令契约。没有用 Playwright/CDP 或其他采集器替代 OpenCLI。

## 4. OpenCLI-first 判定

结论：部分验证，不能进入 V0 的 OpenCLI 正式决策。

已验证的是 OpenCLI Browser Bridge 能复用登录态、访问 Discord、观察真实消息接口并获得硬字段。尚未验证的是“可供 Invest Hub runner 稳定调用的自动化采集契约”。

当前技术阻断点：

1. `opencli list -f json` 当前未发现 Discord 专用 adapter；
2. 当前 Browser surface 使用 `browser <session> ...` 和结构化 envelope，不直接输出计划中所需的 `RawPage {page_id, messages, cursor_after}`；
3. 直接在浏览器地址栏打开 Discord API 会得到 401，说明消息请求依赖网页会话内部的认证上下文，不能用匿名 URL 或裸 HTTP 替代；
4. 已批准 runner 的 `profile_path + cursor -> RawPage JSON` contract 尚未从真实 OpenCLI 命令中捕获，不能凭空填写；
5. 因此 1000 条连续采集和两轮 checkpoint 幂等仍未验证。

## 5. 进入后续阶段的建议

- 可以保留当前确定性 harness 作为后续真实网页验证的基础；
- 当前不能声称 Spike-01 通过，但也不能再归类为“OpenCLI 缺失”；
- 下一步应先为 Spike-01 设计一个仅本地、仅只读的 OpenCLI Browser capture/adapter contract，明确 session、分页、原始 payload 和敏感信息边界；
- 该 contract 验证后，再执行 1000 条真实消息、两轮 runner 和 checkpoint 幂等；
- V0 的正式采集接口和数据模型必须吸收真实网页轨结果；
- 当前不启动 V0 或 V1 的生产实现。
