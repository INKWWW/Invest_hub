# V2 X 来源身份解析与激活设计补充

> 状态：**待用户审阅**
>
> 日期：2026-07-24
>
> 关联：[V2 X Spec](2026-07-22-v2-x-information-collection-and-reader-design.md)、[V2 Implementation Plan](../plans/2026-07-22-v2-x-information-collection-and-reader.md)、[本地 Collection 受控采用 Plan](../plans/2026-07-24-v2-local-opencli-collection-adoption.md)

## 1. 问题与目标

V2 现有控制面可登记指定 X 博主，但新来源固定为 `pending`；而窗口任务只接受已 `resolved` 的来源。当前没有从已登录网页读取的身份事实安全地将来源激活，因此真实持久化 E2E 无法在不绕过审计与身份校验的情况下开始。

本补充只解决一个问题：让管理员登记的一个 X 来源，在本机受控 OpenCLI 已证明其规范化身份与登记账号相同后，安全转为 `resolved`。它不采集帖子、不创建采集任务、不调用 Codex CLI、不初始化或推进 coverage，也不改变 Discord 路径。

## 2. 决策

采用本机 Worker 解析、受限控制面确认的双边流程：

1. 管理员创建 X 来源，控制面只记录请求账号，状态保持 `pending`。
2. 已注册且获该来源授权的本机 Worker 使用专用本地 OpenCLI runtime 执行只读 `twitter profile <requested_handle>`。
3. Worker 仅提取规范化账号身份，要求其与请求账号（去 `@`、小写）精确相同；不一致、空值、歧义、调用失败或不符合合同均失败。
4. Worker 使用设备凭据调用专用身份确认端点；端点再次验证该 Worker 已被管理员明确绑定到来源、参数版本、来源仍为 `pending`、尚无 X 活动任务且 coverage 尚未初始化，然后以原子操作写入 `account_id` 并将状态置为 `resolved`。
5. 控制面只返回脱敏状态、来源 ID、解析状态和参数版本。它不返回 profile JSON、账号 URL、Cookie、浏览器路径、帖子或模型内容。

`account_id` 在当前 Collection 合同中定义为规范化的 `author` handle；这不是猜测的显示名，也不是依赖不稳定网页显示的昵称。后续每条帖子仍由 X runtime 验证其 `author_id` 必须等于任务快照的该值。

## 3. 排除的方案

- 管理员直接输入或手工修改 `account_id`：没有网页身份事实，且绕开 Worker 与审计边界。
- 将请求账号直接当作已验证身份：无法发现输入错误、账号改名或 OpenCLI 返回身份不一致。
- 在远程控制面调用 OpenCLI：远程服务不能、也不得访问用户本机的 X 登录态。
- 把解析伪装成首个 `x_sync`：`x_sync` 的创建本身要求来源已解析，形成循环依赖。

## 4. 数据与接口边界

新增一个仅供已认证 Worker 调用的 X 身份确认路径，以及对应的最小数据库函数/迁移。请求必须包含：来源 ID、参数版本和经本地验证的规范化账号；不携带原始 profile、帖子、URL、命令行或浏览器信息。

服务端原子拒绝以下情况：设备凭据无效或已撤销、来源不存在/非 X、Worker 未被该来源明确绑定、参数版本不一致、存在未完成 X 任务、覆盖水位已初始化，或账号不是规范化非空字符串。对仍为 `pending` 的来源，上述检查全部通过后才允许首次解析；对已 `resolved` 的来源，仅当账号与参数版本精确相同才返回不写入的幂等成功，绝不覆盖身份。

成功后，来源可初始化 coverage 并由现有手动更新入口创建单个固定 `end_at` 的 `x_sync`。失败不写入身份、不创建任务、不移动水位。重复相同请求即使发生在后续 coverage 已初始化之后，也只会以身份与参数版本完全相同为条件返回既有 `resolved` 状态，且不得改写任何字段。

## 5. 本地执行入口

增加一次性、显式授权的本地 identity runner。它要求：

- 专用 `.runtime/v2/opencli-collection/current/bin/opencli-v2-collection`；
- Git 忽略且 owner-only 的 Worker 配置、设备凭据和证据目录；
- `V2_REAL_X_ACK=authorized` 与单独的 `--approve-identity-resolution`；
- 配置中恰好一个待解析的 X 来源。

该 runner 不调用 `run-once`，不领取任务、不写 X 原始数据、不调用 Codex CLI、不创建 scheduler/launchd/cron。控制台只打印解析结果枚举和脱敏计数；本地 evidence 也只保留时间、合同版本和成功/失败类别。

## 6. 失败、恢复与变更处理

- 任何 profile 合同或身份不匹配：保留 `pending`，管理员可修正请求账号后重新运行。
- 已 `resolved` 的来源：除完全相同的幂等确认外拒绝覆盖；账号改名或需替换身份时，必须先停用来源并通过新的管理员流程处理，不能静默重写历史身份。
- 已初始化 coverage 或已有活动任务：拒绝首次解析或不一致的解析变更，防止任务快照与来源身份分裂；相同身份的纯幂等确认不写入数据库。
- 部署或迁移失败：不启用 X 来源、不创建 X 任务；回滚为停用 X 来源与未完成 `x_sync`，不删除已完成事实或版本。

## 7. 验收标准

确定性测试必须覆盖：精确身份匹配成功、大小写/`@` 规范化、空/不匹配身份拒绝、无授权 Worker 拒绝、参数版本不一致拒绝、已初始化 coverage/活动任务拒绝、幂等重试，以及普通用户与未认证调用均不能访问该端点。

真实验证只在远程 migration 和隔离控制面部署完成、且用户再次批准后执行一次：对一名指定博主进行 identity resolution，核对控制面只显示安全状态，再初始化一个覆盖边界并排队一个固定窗口。真实帖子、账号、URL、Cookie、Profile、Prompt、模型输出和完整响应均不得进入 Git 或工程日志。

## 8. 后续顺序与授权边界

本补充获得用户审阅和实现 Plan 批准后，才允许编写补丁。补丁完成并通过本地回归后，仍必须分别确认：推送 `main`、对指定隔离 Supabase 项目应用 migration、部署指定 Vercel 控制面、执行一次身份解析、创建单个任务和执行真实持久化 E2E。任何一项授权都不自动扩大为定时采集、持续运行或正式发布批准。
