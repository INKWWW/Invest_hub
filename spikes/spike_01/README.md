# Spike-01 本地运行说明

本目录是一次性技术验证 harness，不是生产应用代码。

## 运行时

使用 Python 3.11 或更高版本的标准库运行，不安装生产依赖。当前验证环境使用：

    /opt/homebrew/bin/python3.12

## 安全边界

- 真实网页测试只使用用户本人控制的专用 Chrome Profile。
- 采集过程只读，不发送消息、不修改频道内容。
- 不复制或导出 Cookie、Token、密码或 Chrome Profile。
- 真实频道 URL、Profile 路径、真实正文和真实附件链接只通过本地环境变量或私有目录传递。
- 真实证据写入 /private/tmp/invest-hub-spike-01-evidence/，不得写入 Git。
- OpenCLI 不可用时，只记录环境前置条件失败，不切换到 Playwright/CDP。

## 前置检查

    PYTHONPATH=spikes /opt/homebrew/bin/python3.12 -c 'from spike_01.preflight import check_opencli; print(check_opencli("opencli"))'

## 测试

    PYTHONPATH=spikes /opt/homebrew/bin/python3.12 -m unittest discover -s spikes/spike_01/tests -v

## 当前执行结果

确定性 harness 已通过 32 个测试。真实网页轨通过 bounded soak，并通过 checkpoint-resume 累计采集 1392 条第一轮唯一 Canonical 消息；第二轮从末尾 checkpoint 继续采集 112 条，duplicate 为 0。真实 evidence 只保存在本地受保护目录，脱敏决策报告位于 docs/spikes/2026-07-15-spike-01-decision-report.md。

本结果支持进入 V0 采集设计，但不等同于 V0/V1 生产实现批准。生产设计必须保留 network freshness、有限重开、90 秒单页硬截止、checkpoint 后置推进、失败恢复和逐页 telemetry。
