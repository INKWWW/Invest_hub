# V0 收口与远程验收实施计划

> **执行方式：** 用户于 2026-07-19 明确授权在当前工作区直接执行；每个任务遵循测试先行、独立验证与独立提交。

**目标：** 将已部署的 V0 Preview 从“确定性验证有条件通过”补齐为可执行的本地 Worker、云端持久化、管理员操作入口和远程 HTTP 验收闭环；真实 Discord 运行仍须在显式授权后单独执行。

**架构：** Vercel Preview 继续只承载 Next.js 控制面和 Supabase 访问。专用本地 Worker 读取仓库外、权限为 0600 的配置、OpenCLI Browser Bridge 合同、Prompt、凭据和证据目录；它通过版本化 HTTPS 协议完成注册、领取、持久化、结果回报和恢复。真实 Discord 的 URL、Profile、Cookie、原始内容、完整 Prompt 与模型完整响应均不进入 Git、Vercel、数据库调试面或任务 payload。

**技术栈：** Next.js 16、Supabase Postgres/RLS、Python 3.11+ 标准库 Worker、OpenCLI Browser Bridge、Codex CLI、Vitest、Python `unittest`、Supabase pgTAP、Vercel Preview。

## 全局约束

- 只使用已创建的 `invest-hub-v0` Supabase 项目和 Vercel Preview；不把现有 Production 部署作为 V0 验收目标。
- 所有新增行为先写会失败的测试，再写最小实现；每个任务完成后执行对应测试。
- `SUPABASE_SERVICE_ROLE_KEY` 永远不使用 `NEXT_PUBLIC_` 前缀，不写入仓库、日志或脚本参数。
- Worker 的真实运行必须显式要求 `V0_REAL_DISCORD_ACK=authorized`；未授权、未配置或预检失败必须拒绝运行。
- 真实 Discord 只使用用户正常可见、已授权的频道和专用浏览器配置档；不自动化普通用户 Token，不解析媒体内容。
- checkpoint 仅在原始元数据、Canonical、结构化输出和证据关联均成功持久化且控制面确认结果后推进。
- 真实页面证据只保留在仓库外受保护目录；工程日志与决策报告只写脱敏状态、计数和逻辑证据引用。

---

### Task 1：修正远程配置契约与部署防泄漏边界

**文件：**

- 修改：`apps/control-plane/.env.example`
- 修改：`apps/control-plane/.gitignore`
- 修改：`apps/control-plane/src/lib/db/supabase-server.ts`
- 测试：`apps/control-plane/src/lib/db/supabase-server.test.ts`
- 修改：`workers/v0/README.md`

**接口：**

- 控制面仅接受 `NEXT_PUBLIC_SUPABASE_URL`、`NEXT_PUBLIC_SUPABASE_ANON_KEY` 和服务端 `SUPABASE_SERVICE_ROLE_KEY`。
- `.vercel/`、所有 `.env*`、本地 Worker 凭据和本地证据目录保持不被 Git 跟踪。

- [x] 写测试，证明部署模板变量与运行时契约一致。
- [x] 运行测试，确认当前实现因环境模板漂移失败。
- [x] 以最小改动统一模板、运行时名称与忽略规则。
- [x] 运行控制面 lint、相关 Vitest 测试和 `git diff --check`。
- [x] 提交：`fix: align v0 deployment environment contracts`。

### Task 2：建立 Worker 持久化协议与原子 checkpoint 前置条件

**文件：**

- 新建：`contracts/v0/worker-persistence.schema.json`
- 新建：`supabase/migrations/002_v0_worker_persistence.sql`
- 新建：`supabase/tests/002_v0_worker_persistence.sql`
- 新建：`apps/control-plane/src/app/api/worker/tasks/[taskId]/persist/route.ts`
- 新建：`apps/control-plane/src/lib/db/repositories/worker-persistence.ts`
- 修改：`apps/control-plane/src/lib/contracts.ts`
- 修改：`apps/control-plane/src/lib/db/types.ts`
- 修改：`apps/control-plane/src/app/api/api.integration.test.ts`

**接口：**

- `POST /api/worker/tasks/{taskId}/persist` 只接受已认证、持有未过期 lease 的 Worker。
- 请求只携带原始消息的哈希和本地引用、Canonical 数据、结构化输出和消息 ID 证据关联；不得携带 Profile、Cookie、Prompt 或模型完整响应。
- 数据库函数验证 `task_id`、`attempt`、`worker_id`、来源和 lease，并以幂等方式写入 raw 元数据、Canonical、structured run 和 evidence ref；响应返回服务器生成的 `structured_run_ids`。

- [x] 写 API 与 pgTAP 失败测试：未认证、错 lease、来源不匹配、伪造持久化标记与重复持久化。
- [x] 运行测试，确认新路由/函数不存在而按预期失败。
- [x] 添加 schema、迁移、数据库函数、repository 和路由；保持结果回报前的持久化确认。
- [x] 运行 Supabase reset、pgTAP、控制面 API 测试和 lint。
- [x] 提交：`feat: persist v0 worker executions before results`。

### Task 3：实现受授权的本地 Worker 运行器

**文件：**

- 新建：`workers/v0/src/invest_hub_worker/runtime.py`
- 新建：`workers/v0/src/invest_hub_worker/opencli_bridge.py`
- 新建：`workers/v0/src/invest_hub_worker/persistence.py`
- 修改：`workers/v0/src/invest_hub_worker/protocol.py`
- 修改：`workers/v0/src/invest_hub_worker/worker.py`
- 修改：`scripts/v0/run-e2e.sh`
- 新建：`workers/v0/tests/test_runtime.py`
- 新建：`workers/v0/tests/test_opencli_bridge.py`
- 新建：`workers/v0/tests/test_persistence.py`

**接口：**

- 运行器从 `--config`、`--opencli-contract`、`--prompt-path`、`--evidence-dir` 和受保护的 Worker enrolment code 文件读取本地信息；这些路径与内容不出现在 stdout。
- 真实模式固定为 Codex CLI 与 `100/5/240/3` 参数；没有 `V0_REAL_DISCORD_ACK=authorized` 必须退出。
- `WorkerProtocol.persist_execution(payload)` 调用持久化路由；`Worker.run_once()` 在成功时回报结果，在失败时回报符合 `task-failure` 的分类。
- OpenCLI Browser Bridge 复用 Spike-01 已验证的只读网络读取语义，并适配到 V0 Active Adapter 的响应边界。

- [x] 写运行器与协议失败/顺序测试，并确认新增模块尚不存在时失败。
- [x] 实现最小运行器、桥接适配和持久化调用；真实模式只在显式授权后可达。
- [x] 运行 Worker 单元测试、确定性 E2E 和 redaction 检查。
- [x] 提交：`feat: add authorized v0 discord worker runtime`。

### Task 4：补齐管理员操作入口与远程 HTTP 验收工具

**文件：**

- 修改：`apps/control-plane/src/app/admin/sources/page.tsx`
- 修改：`apps/control-plane/src/app/admin/tasks/page.tsx`
- 新建：`apps/control-plane/src/components/admin/CreateSourceForm.tsx`
- 新建：`apps/control-plane/src/components/admin/CreateTaskForm.tsx`
- 新建：`apps/control-plane/src/components/admin/create-controls.test.tsx`
- 新建：`tests/e2e/v0/http_client.py`
- 新建：`tests/e2e/v0/test_deployed_http_flow.py`
- 修改：`scripts/v0/run-e2e.sh`

**接口：**

- 管理员可通过受保护界面创建逻辑 Discord 来源和 `discord_sync` 任务；页面不收集频道 URL、Profile 或 Prompt。
- 部署后测试只读取本地受保护的 V0 管理员账号、Worker invite 和控制面 URL；它验证真实 HTTPS 注册、心跳、来源创建、任务领取、Mock 结果持久化、普通用户管理员阻断和 lease/checkpoint 恢复。

- [x] 实现最小管理员表单；不收集频道 URL、Profile 或 Prompt。
- [x] 在本地控制面运行全部 lint、测试与生产构建。
- [x] 部署后仅对 Vercel 预览执行核心工作节点应用级 HTTP 验收：合成注册 → 心跳 → 领取 → 持久化 → 回报结果通过；Vercel 受保护部署通道抵达应用，未使用或记录真实 Discord 内容。
- [x] 补测远程普通用户管理员阻断和租约/检查点恢复：临时普通用户被管理员接口拒绝；第一租约过期后由第二工作节点以第 2 次尝试重新领取，并继承预置检查点；全部合成对象已删除。
- [x] 提交：`feat: add v0 admin source and task entry forms`。

### Task 5：部署收口、真实运行门禁与文档更新

**文件：**

- 修改：`docs/engineering-journal/2026-07-18-v0.md`
- 修改：`docs/spikes/2026-07-18-v0-decision-report.md`
- 修改：`docs/project-status.md`
- 修改：`README.md`
- 修改：`docs/README.md`

**接口：**

- 仅在 Preview 已部署新代码且远程 HTTP E2E 通过后，记录部署验证。
- 真实 Discord 命令必须先通过预检，并需要用户提供仓库外的专用配置档、授权来源、OpenCLI 合同、Prompt 和一次性 Worker 邀请码；缺任一项时保持有条件通过。

- [x] 部署 Preview，检查部署日志不含密钥、Profile、Prompt 或正文。
- [x] 运行全部可执行的确定性测试、redaction 检查和 diff 检查；远程核心 HTTP E2E 已通过，部署期契约文件路径缺陷已修复并新增同源一致性测试。
- [ ] 在显式授权条件满足后运行一次真实 Discord 增量；本次没有授权来源配置，保持门禁状态。
- [x] 根据实际证据更新工程日志、决策报告和项目状态；保持“有条件通过”。
- [ ] 提交：`docs: record v0 closure validation`。
