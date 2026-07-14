# Spike-01 OpenCLI Discord 增量采集决策报告

## 报告状态

- 日期：2026-07-15
- 执行分支：spike-01-implementation
- Python：3.12.13
- 真实网页数据：未读取
- OpenCLI 状态：本机未发现可执行文件

## 1. 执行范围

本次完成了本地确定性 harness、Canonical Schema、Validator、本地证据存储、checkpoint Emulator、Fake Connector、增量 Runner 和 OpenCLI 命令边界单元测试。

没有连接云端，没有安装生产依赖，没有访问用户 Discord Profile，没有保存 Cookie、Token、频道 URL 或真实消息。

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

真实网页轨未执行，原因是当前环境中不存在 opencli 可执行文件：

    command -v opencli
    # no executable found

因此以下项目均为未验证：

- 专用 Chrome Profile 登录态复用；
- Discord 频道访问；
- 1000 条以上真实消息采集；
- Discord 实际作者 ID、消息 ID、回复、引用和附件输出；
- Discord 分页或虚拟滚动连续性；
- 真实网页二次运行幂等。

没有用 Playwright/CDP 或其他采集器替代 OpenCLI。

## 4. OpenCLI-first 判定

结论：未验证，不能进入 V0 的 OpenCLI 正式决策。

该结论不是 OpenCLI 能力不通过，也不是通过。当前阻断条件是外部环境前置条件缺失：

1. 安装或提供可执行的 OpenCLI；
2. 锁定具体版本；
3. 获取 Discord Web 的实际命令和机器可解析输出契约；
4. 在用户专用 Chrome Profile 中重新执行真实网页轨；
5. 重新验证 1000 条消息、硬性字段和二次运行。

## 5. 进入后续阶段的建议

- 可以保留当前确定性 harness 作为后续真实网页验证的基础；
- 在 OpenCLI 可用前，不应声称 Spike-01 通过；
- OpenCLI 真实轨通过后，再决定是否需要私有 Adapter；
- V0 的正式采集接口和数据模型必须吸收真实网页轨结果；
- 当前不启动 V0 或 V1 的生产实现。
