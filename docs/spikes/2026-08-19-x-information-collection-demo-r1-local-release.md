# X 信息采集最小 Demo R1：本地发布准备包

> 本文是 Ticket 06R 的唯一交付文件。它只描述从已验证 integration commit 到未来真实 Demo 的受控准备、授权和验收边界；本文编写与本地门禁期间不执行真实来源、Provider、远程数据库、部署、Worker 或 launchd 操作。

## 1. Gap audit 与执行结论

本轮 gap audit 对照 Ticket 06R 的六项 deliverables：local release manifest、手动 cutoff 运行说明、additive migration dry-run 与版本回读、控制面及本机入口 cutover/rollback、独立 Release Authorization 请求模板、真实 Demo 最小验收矩阵与 Final Report 模板。六项内容均可由本文件覆盖，不拆分新文档；Ticket 06R 不新增应用代码、migration、测试、脚本、README 或治理文件。

当前只形成 local release preparation。没有独立 Release Authorization 时，下面所有真实运行命令都只是“未来授权后的模板”，不得在本 Ticket 中执行。任何一次真实 Demo 都必须重新确认版本、入口、来源快照、身份就绪、迁移状态和授权范围；不能因为本地 synthetic 证据通过而自动进入生产。

## 2. Local release manifest

| 项目 | 固定事实或候选绑定 | 本地状态 | 未来才允许的动作 |
| --- | --- | --- | --- |
| 起始基线 | integration commit `9d9a60951fe6414a35a94474725b0844e39aa767` | 本 Ticket 必须从此 commit 开始 | 只在此基线上产生本地文档 candidate |
| Ticket 05R 候选 | `fade7e72ccd6bbf3e5347e0c6d7b69e189ac749d`，已集成至上述 integration commit | 已有候选，不能替换为旧 worktree 或脏主 checkout 内容 | 真实运行只能使用同一集成链 |
| 代表性本地证据 | focused `044`：22/22；Supabase：49 files/837；Worker：208/208；diff/redact：PASS | 作为 05R 输入证据记录，不在本 Ticket 重跑应用测试 | 如授权真实 Demo，仍须单独形成真实 Final Report |
| 未变更的复用证据 | Control Plane、Reader、lint、build 复用 unchanged base `bb1b619` 的已验证证据 | Ticket 06R 不改代码，因此不把复用证据写成新一轮代码验证 | 若候选发生任何代码变更，必须重新验证受影响范围 |
| 数据库合同 | 候选中已有 `20260818100000_x_demo_ticket_01_fixed_window.sql` 与 `20260818120000_x_demo_ticket_02r_sequential_runner.sql` | Ticket 06R 不新增 migration；远程是否已应用必须未来只读核对 | 只可按独立授权做 dry-run、获批 additive apply 和版本回读 |
| 本机入口 | `run-x-fixed-window-sequential`，显式 `--cutoff`，单进程、冻结来源、顺序执行 | 只保留手动入口设计，不安装或修改 launchd | 旧入口暂停且确认无活动后，才可按授权运行一次 |
| Reader 结果 | 单博主三类观点、折叠证据、跨博主判断、覆盖状态 | 真实内容未在本地发布包中复制 | 只记录脱敏状态计数和页面结构结果 |
| 本 Ticket 产物 | `docs/spikes/2026-08-19-x-information-collection-demo-r1-local-release.md` | 允许新增的唯一文件 | 仅精确提交该文件 |

`044` 的一来源 synthetic fixture，以及 Feature Contract 中用于代表性闭环的四来源 fixture，只是验证样本。它们不是产品数量上限；未来真实运行必须冻结全部已启用且已就绪来源，无论来源数量是 1、4 还是其他数量。发布证据只保留来源数量和状态计数，不保留来源身份、帖子、链接或内部标识。

本 manifest 的版本绑定是硬条件：数据库合同、控制面候选、本机 Worker 代码、Reader 投影和运行说明必须来自同一候选链。只看到某个 deployment 为 Ready、某个进程存在或某个 migration 已存在，都不能单独证明完整 Demo 可用。

## 3. 手动 cutoff 运行说明

### 3.1 运行合同

管理员未来明确选择一个上海时间 cutoff，格式为 `YYYY-MM-DDTHH:MM:SS+08:00`。只接受固定窗口的截止点 `00:00、08:00、12:00、16:00、20:00`；窗口边界仍是 `start < occurred_at <= end`。本入口不会自动选择下一个窗口，也不会因为电脑离线而追补多个窗口。

启动阶段必须先检查全部已启用 X 来源。每个来源都必须有启用的 profile、已完成的 identity resolution 和非空 account identity。只要任一已启用来源未就绪，服务端以 `x_demo_sources_not_ready` 拒绝，并且在创建 run、batch、task 或 judgement 前整体停止；管理员完成既有身份准备后，可以用同一 cutoff 重新尝试。不能把“未就绪”解释为 no-new，也不能只运行已经就绪的子集。

所有已启用且已就绪来源在启动时写入不可变冻结快照，来源按稳定顺序逐个处理。运行中新增、禁用或修改来源只影响下一轮；本轮不消费旧 backlog、不领取其他窗口任务、不调用通用连续调度器、不并发处理来源。产品不设置来源数量配额。

### 3.2 未来授权后的命令模板

以下命令只是模板，当前 Ticket 不得执行。尖括号内容必须由授权人根据当次环境填写，不能写入 Git，也不能在报告中回显。`V2_REAL_X_ACK=authorized` 是真实 X 运行的显式授权开关；没有独立 Release Authorization 时必须保持未设置，不能用命令模板反向推定授权已经存在。

```bash
# Future-only template; do not run during Ticket 06R.
V2_REAL_X_ACK=authorized \
PYTHONPATH=workers/v0/src <PYTHON_BIN> -m invest_hub_worker.cli \
  run-x-fixed-window-sequential \
  --config <GIT_IGNORED_X_CONFIG> \
  --credential <GIT_IGNORED_WORKER_CREDENTIAL> \
  --opencli-contract <GIT_IGNORED_OPENCLI_CONTRACT> \
  --prompt-path <GIT_IGNORED_APPROVED_PROMPT> \
  --evidence-dir <OWNER_ONLY_EVIDENCE_DIR> \
  --cutoff <EXACT_SHANGHAI_CUTOFF> \
  --opencli-executable <CONTROLLED_OPENCLI_EXECUTABLE> \
  --worker-name <UNIQUE_WORKER_NAME>
```

命令执行前的人工顺序如下：先确认新旧入口互斥并确认旧入口没有活动任务；再确认候选版本绑定、远程 migration history 和控制面 Ready 状态；再确认所有已启用来源已经就绪；最后只填入一个明确 cutoff 并执行一次前台顺序 runner。命令输出不得原样复制到报告，报告只摘录脱敏的 cutoff、来源数量、状态计数、终态和 Reader 结果。

每个来源执行 Ticket 01 的精确窗口任务，并只处理该任务返回的 task identity。OpenCLI、逐帖 Codex、单博主窗口聚合和跨博主判断均沿用最多两次尝试，即首次失败后最多重试一次；第二次失败进入明确终态，不得无限重试。来源失败或超时标记为 excluded/failed 后继续下一个来源；已持久化的其他来源结果保留。

结算语义必须保持以下区分：有可用观点且全部纳入为 `complete`；有可用观点但存在未纳入来源为 `partial`；全部已检查且没有新增为 `no_new`；没有可用输入、判断失败或无法完成的运行必须为明确 `failed`，不得伪造 no-new 或空的成功判断。跨博主判断失败不删除已成功的单博主观点；同一 cutoff 的重复启动只能返回已有活动或终态身份，不创建并发 runner 或重复来源任务。

### 3.3 每一步的停止条件

| 步骤 | 通过条件 | 任一失败时的动作 |
| --- | --- | --- |
| 版本与入口确认 | 所有组件来自同一候选，旧入口已暂停且无活动任务 | 停止；不启动新 runner |
| 来源就绪检查 | 全部已启用来源均为 enabled、profile enabled、resolved 且有 account identity | 停止；不得创建 run/batch/task/judgement |
| cutoff 校验 | cutoff 是过去的上海固定窗口边界，且本次授权只列出一个 cutoff | 停止；不自动改选或补跑其他窗口 |
| run 启动与冻结 | 服务端返回一个 run identity 和完整来源快照 | 停止；若已产生记录，只保留事实并记录安全摘要，不手工修正 |
| 来源任务创建与绑定 | 每个来源只使用本 cutoff 返回的精确 task，绑定成功后才执行 | 停止当前来源并按合同记为失败；不得领取旧 task |
| 顺序执行 | 当前来源完成或进入终态后才进入下一个来源 | 停止后续；已持久化结果保留，未完成来源不写成功 |
| 结算与判断 | 覆盖分母等于冻结来源集合，状态符合 `complete/partial/no_new/failed` | 停止；不生成伪判断，不改写旧批次或版本 |
| Reader 回读 | 普通用户权限、桌面和 375px 结果可读且状态与结算一致 | 停止发布结论；保留数据事实，回切入口或 deployment |

## 4. Additive migration dry-run 与版本回读

### 4.1 只允许的合同

Ticket 06R 不生成新 migration。未来如获独立授权，只能审阅候选中已有的两个 R1 migration 版本：`20260818100000_x_demo_ticket_01_fixed_window.sql` 和 `20260818120000_x_demo_ticket_02r_sequential_runner.sql`。它们的目标是增加固定窗口任务、顺序 runner、冻结来源、绑定/结算/判断所需的 additive 合同；不得删除、重置或重写历史任务、水位、批次、版本、coverage、审计事实或 RLS 边界。

### 4.2 未来授权后的 dry-run 模板

下面的命令仅用于未来授权后的目标环境核对，当前不执行。dry-run 发现未审阅版本、远端 history 与本地不一致、destructive SQL、非预期对象变化或候选版本不一致时，立即停止，不使用 `migration repair`、`db pull`、手工 Dashboard SQL 或推测性 DML。

```bash
# Future-only, read-only history and dry-run templates; do not run now.
supabase migration list --linked
supabase db push --linked --dry-run
```

dry-run 通过后，Release Authorization 必须逐项列出允许应用的 migration。只有授权明确包含时才可执行以下 apply 模板；它不是本 Ticket 的执行命令：

```bash
# Future-only apply template; requires a separate Release Authorization.
supabase db push --linked
```

### 4.3 版本与关键合同回读

apply 后立即停止其他步骤，先回读 migration history，确认只出现授权版本且顺序与候选一致；再以既有只读管理员检查或受控 contract probe 核对固定窗口 RPC、顺序 runner RPC、任务绑定、结算、judgement claim 和 scoped terminalization 合同存在且版本一致。回读只记录版本号、合同名称、状态和计数，不记录数据库标识、来源身份、原始内容或凭据。

版本回读必须至少确认：两条 R1 migration 的远端状态；控制面所调用的 RPC 与候选代码一致；旧表和历史事实仍可读；没有任何历史行被 update/delete；新旧入口的能力边界仍互斥。任何一项不满足都停止 cutover。migration 成功不能代替控制面、Worker、Reader 和真实 Demo 验收。

## 5. 控制面与本机入口 cutover / rollback

### 5.1 Cutover 清单

| 顺序 | 操作与证据 | 停止条件 |
| --- | --- | --- |
| 1 | 记录目标候选、两条 migration、控制面候选、本机 Worker 候选和一个 cutoff | 版本或范围有歧义即停止 |
| 2 | 暂停旧连续/自动入口，确认没有活动旧 task 或 runner；不改写旧终态 | 旧入口仍可领取目标窗口，或无法证明无活动，即停止 |
| 3 | 完成 migration dry-run、按授权 apply，并回读 history 与关键合同 | 出现额外 pending、历史漂移、破坏性变化或回读不一致，即停止 |
| 4 | 部署同一候选控制面，等待 Ready 并确认入口指向该候选 | deployment 非 Ready、入口仍指向旧/未知版本，即停止 |
| 5 | 确认本机 Worker 代码和控制面候选一致；不在本 Ticket 安装、reload 或修改 launchd | 版本不一致即停止 |
| 6 | 人工确认登录态有效，执行一个明确 cutoff 的顺序 runner | 认证、来源就绪、cutoff 或新旧互斥任一失败，即停止 |
| 7 | 回读来源覆盖、单博主观点、跨博主判断和 Reader；形成 Final Report | 状态计数与 Reader 不一致，或出现未脱敏内容，即停止后回退 |

“旧入口”包括既有连续/自动 Worker 入口和任何已配置的常驻 launchd；“新入口”仅指本节的手动 `run-x-fixed-window-sequential`。两者不得同时领取目标窗口。Ticket 06R 不执行正式 launchd 变更，也不把进程存在、deployment Ready 或入口可打开当作完整验收。

### 5.2 Rollback 边界

回退优先选择停止新入口和回切已验证的前一 Ready 控制面 deployment；不删除新写入的 run、batch、task、观点、judgement、版本或审计记录。如果 migration 已应用，使用 additive forward fix 修复后续合同，不回滚历史版本，不直接改 schema history，不用 DML 伪造旧状态。若新 runner 已开始但只完成部分来源，停止后保留已确认持久化结果，未完成来源保持未纳入或失败，不把中断写成成功。

每一步的回退停止条件是：无法确认前一 deployment Ready、旧入口仍有活动领取者、migration 合同不兼容、存在未知版本、历史状态发生改写、或 Reader 看到与数据库结算不一致的内容。此时同时停止新旧入口的目标窗口领取，保留安全摘要，等待人工决定；不得继续重试、清理、回刷或删除审计事实。

## 6. 独立 Release Authorization 请求模板

以下模板必须由独立授权人填写和明确批准；“本地 Ticket 06R 已完成”不等于模板中的任何一项已经获批。

```text
Release Authorization: X 信息采集最小 Demo R1

申请人：<姓名>
授权人：<姓名>
授权时间：<时间与时区>
目标候选：<从 integration commit 9d9a609... 派生的完整 commit>
目标环境：<明确环境，不写凭据或私有 URL>
允许的 migration：<明确列出版本；没有列出的版本不得应用>
目标 cutoff：<一个明确的上海时间 cutoff>
来源范围：本次启动时全部已启用且已就绪来源；预计数量 <N>
允许的外部动作：
  [ ] linked migration history 只读核对与 dry-run
  [ ] 仅应用上面列出的 additive migration
  [ ] 部署同一候选控制面并确认 Ready
  [ ] 暂停旧入口并启用一次手动顺序 runner
  [ ] 使用已登录且人工确认的 X 页面完成一次真实 Demo
  [ ] 普通用户 Reader 桌面与 375px 只读验收
  [ ] 其他：<逐项写明>
明确不授权：未列出的 migration、历史回写、DML 修复、push/PR、其他部署、常驻 Worker/launchd 变更、自动五窗口、网页补采、额外 cutoff、容量压测和其他 Provider 调用。
停止条件：版本不一致、旧入口不互斥、任一来源未就绪、dry-run 非 additive、部署非 Ready、任一步状态不一致、出现敏感输出或 Reader 验收失败。
回退方案：停止新 runner；按第 5.2 节回切前一 Ready deployment；保留所有不可变事实；不删除、不重置、不伪造成功。
证据范围：只提交脱敏版本、cutoff、来源数量、状态计数、Reader 结果和失败分类；不提交原始帖子、来源身份、私有 URL、Cookie/Token/Profile、Prompt、完整 Provider 输出、异常栈或敏感本机路径。
批准声明：我已确认以上范围、一个 cutoff、停止条件和回退边界，并单独授权所勾选的外部动作。
授权人签名/记录：<证据>
```

## 7. 真实 Demo 最小验收矩阵

真实 Demo 只验证一个明确 cutoff，不验证五窗口自动化、历史补采或生产级恢复。四来源矩阵和一来源 `044` fixture 都是代表性证据，不是产品数量上限。

| # | 验收项 | 最小通过证据 | 失败处理 |
| --- | --- | --- | --- |
| 1 | 版本绑定 | migration、控制面、Worker、Reader 来自同一候选；关键合同回读一致 | 停止，不启动 runner |
| 2 | 来源就绪与冻结 | 全部已启用来源均就绪；冻结快照数量等于启用数量；运行中配置变化不影响本轮 | 停止，且不得产生 run/batch/task/judgement |
| 3 | cutoff 精确性 | 一个上海固定 cutoff，任务范围满足 `start < occurred_at <= end` | 停止，不自动改选窗口 |
| 4 | 顺序与隔离 | 所有冻结来源按稳定顺序尝试；只领取本 cutoff 精确 task，不消费旧 backlog | 停止后续来源，保留已持久化事实 |
| 5 | 重试与终态 | 每个外部步骤最多首次加一次重试；第二次失败进入终态，不能第三次调用或再次 claim | 记录安全失败分类，停止当前路径 |
| 6 | 局部失败隔离 | 一个来源失败不阻断后续来源；覆盖状态准确区分 included、no-new、excluded/failed | 不把缺口写成 no-new 或成功 |
| 7 | 结算与判断 | `complete/partial/no_new/failed` 与可用输入一致；无输入或判断失败不生成伪判断 | 停止 Reader 发布性结论 |
| 8 | Reader 内容 | 单博主三类观点、折叠证据、跨博主判断和未纳入状态可读，事实与观点边界保持 | 回切入口或 deployment，不改写数据 |
| 9 | 权限与响应式 | 普通用户不能访问管理员控制；桌面与 375px Reader 均无横向溢出或错误覆盖层 | 停止验收，不扩大修复范围 |
| 10 | 脱敏与审计 | 日志和页面只暴露允许的状态摘要；历史任务、水位、批次、版本和审计事实未被改写 | 立即停止并保留安全摘要 |
| 11 | 入口互斥与回退 | 旧入口未领取目标窗口，新入口单进程；失败时可按第 5.2 节停止和回切 | 不继续运行或重试 |

## 8. Final Report 模板

```text
Final Report: X 信息采集最小 Demo R1

结论：PASS / STOPPED / BLOCKED
候选版本：<完整 commit>
数据库迁移：<仅记录已授权且回读到的版本>
控制面与本机入口：<候选绑定、旧入口互斥结果>
目标 cutoff：<上海时间>
冻结来源数量：<N；不写来源身份>
状态计数：included=<n>；no-new=<n>；excluded/failed=<n>
运行终态：complete / partial / no_new / failed
判断终态：succeeded / not_created / failed
Reader 结果：<单博主、跨博主、覆盖状态、桌面/375px 的脱敏结论>
重试与停止：<实际发生的最多一次重试、停止点和失败分类>
版本回读：<history 与关键合同是否一致>
数据不变性：<旧任务、水位、批次、版本、审计事实未改写的证据>
已知限制：手动显式 cutoff；无自动五窗口；无网页补采；无全流程两小时强杀；无并发 runner；无生产级恢复/监督；不代表生产 SLA。
未执行的禁止项：<push/PR、未授权 remote migration、部署、正式 Worker/launchd 变更、额外 Provider 调用、历史回写、敏感数据复制等>
停止或回退记录：<如有，记录第几步、原因、前一 Ready deployment/入口状态>
证据附件：<仅脱敏 manifest、状态计数、截图/页面结构摘要；不附原始内容>
授权记录：<Release Authorization 证据>
报告人/时间：<值>
```

## 9. 已知限制与禁止项

本 R1 只支持手动显式 cutoff。它没有自动五窗口、网页补采、任意日期回填、连续水位补追、全流程两小时强杀、跨阶段强制取消、并发 runner、生产级 lease 恢复、Supervisor、健康探针、Bark、长期监控或无人值守 SLA。总耗时随冻结来源数量和内容量变化；单步骤有限超时与一次重试不等于生产级恢复能力。

在本 Ticket 和未获独立 Release Authorization 前，禁止 Git push/PR、remote migration apply、生产写入、Vercel 或其他部署、正式 Worker/launchd 安装或 reload、真实 X/OpenCLI/Codex/Provider 调用、生产页面验收、历史任务/水位/批次/版本/审计事实改写、直接 DML 修复、删除失败记录、伪造成功、复制真实来源或原始 Provider 输出。任何未来授权也只覆盖授权文本明确列出的最小动作；未列出的动作仍禁止。
