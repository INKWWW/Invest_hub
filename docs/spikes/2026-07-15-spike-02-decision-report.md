# Spike-02 免费 LLM 容量与质量决策报告

## 报告状态

- 日期：2026-07-15
- 结论：**未验证（unverified）**
- 执行内容：本地确定性 harness、Mock 规模运行和 GLM 运行前置检查
- 真实 GLM 请求：0 次
- 本报告不批准 V0/V1 生产实现，也不批准 Codex CLI fallback

## 1. 范围与安全边界

本次执行只使用人工构造公开 fixture 和本地临时 evidence 目录。没有读取或提交 API key、真实 fixture、Prompt 正文、完整 GLM 响应、私有 URL 或历史数据。

Mock 轨完全离线。GLM 轨要求通过以下运行时环境变量提供配置：

- `SPIKE02_GLM_API_KEY`；
- `SPIKE02_GLM_ENDPOINT`；
- `SPIKE02_GLM_MODEL`。

当前运行环境未提供上述变量，因此没有猜测 endpoint、model 或密钥，也没有使用其他 Provider 替代 GLM。

## 2. 确定性验证结果

Spike-02 确定性测试：

- 27/27 通过；
- 覆盖 fixture 校验、chunk 保序、回复上下文、Schema、Mock 失败注入、局部重试、截断拆分、evidence 安全写入、质量评估和 CLI。

Mock 规模运行：

| 输入 | chunk size | 请求次数 | 最终成功率 | JSON 解析率 |
| --- | ---: | ---: | ---: | ---: |
| 小批次 12 条 | 3 | 4 | 100% | 100% |
| 约 500 条合成 fixture | 25 | 20 | 100% | 100% |
| 1000 条合成 fixture | 25 | 40 | 100% | 100% |
| 1000 条合成 fixture | 100 | 10 | 100% | 100% |

这些结果只证明本地 harness 的确定性流程和规模输入可以运行，不代表 GLM 的容量、延迟或摘要质量。

## 3. GLM 轨结果

GLM 真实轨未执行。因缺少运行时配置，以下指标均没有真实观测值：

- 首次请求成功率；
- 重试后最终成功率；
- JSON 合法率；
- P50/P95 响应时间；
- 输入/输出 token 使用量；
- 超时、限流、截断和真实 Provider 错误；
- 事实有据率和指定用户归因准确率。

因此不能根据 Mock 结果推断 GLM 通过，也不能推断 GLM 不通过。

## 4. 当前结论

结论为 **未验证**：

1. Spike-02 harness 的本地确定性边界已验证；
2. Mock 的失败恢复和规模输入路径已验证；
3. 真实 GLM 容量、质量和 P95 尚未验证；
4. 不能进入“GLM 通过”或“有条件通过”的生产设计结论。

## 5. 下一阶段门槛

在受保护的本地环境提供 GLM 运行配置后，需要重新执行：

1. 小批次带人工标注 fixture；
2. 约 500 条输入；
3. 1000 条以上输入；
4. 至少两个候选 chunk size；
5. 质量人工复核和脱敏 evidence 汇总。

重新运行必须继续使用本 Spike 的安全 evidence 目录和不自动 fallback Codex CLI 的约束。完成真实 GLM 轨后，才能根据 Spec 中的门槛更新本报告结论。
