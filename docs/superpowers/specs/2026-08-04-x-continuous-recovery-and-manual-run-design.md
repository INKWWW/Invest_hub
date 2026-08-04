# X 连续恢复与手动完整运行设计

## 目标

让每个已启用、已解析的 X 来源以连续水位为唯一进度事实：来源新增、Worker 离线恢复或普通可重试中断后，系统自动按连续四小时窗口追赶；管理员可创建一次“补采并重新生成 X 总结”的受审计运行。两条路径必须复用同一任务、证据、租约和每日判断合同，不建立第二套采集器或直接修改历史结果。

## 已确认根因

`ensure_due_x_collection_batches` 在创建 batch 时，会把覆盖水位早于该 batch cutoff 的来源冻结为 `source_behind_cutoff`。它只为水位恰好落在当前 cutoff 前一窗口的来源创建 batch-bound task。scheduled Worker 已经调用 `enqueue_due_x_tasks`，后者也能为每个来源创建其下一个连续窗口；但它遇到终态 window 时会永久 defer 该来源。此前的 replacement recovery 仅能由管理员逐个创建，因此一旦新增或任一来源发生终态失败，后续 batch 会持续显示排除，直到人工逐来源处理。

终态失败不能被无条件自动重试：它必须保留原失败审计并停止该来源，直到管理员发起一次受到水位、活动任务和 replacement 唯一性约束的 recovery。`opencli_contract` 也必须先修正合同，不能由队列掩盖。

## 决策

### 连续追赶

每次 scheduled Worker tick 先调用既有 `enqueue_due_x_tasks`，再创建和结算每日 batch。该入口每个来源只创建水位之后的下一个完整四小时 scheduled window，并且已有活跃任务、相同 range 或终态失败时不会重复创建。因此成功任务会自然前移水位，下一 tick 再创建下一个窗口，直至追平当前 cutoff；新加入并完成 coverage 初始化的来源同样自动进入这条路径。

终态失败仍不阻塞其他来源、不无限重试，也不伪造完整覆盖。scheduler 对每个尚未有 replacement 的精确水位阻塞终态 task，只创建一次 system replacement recovery；replacement 再次终态失败时停止该来源并保留两次失败审计。管理员手动完整运行复用同一规则；若 replacement 后仍失败，则该 run 失败，不继续创建第三次任务。

### 手动完整运行

新增 `x_manual_recovery_runs`，一条记录代表管理员对固定 cutoff 的一次请求，包含请求人、创建时间、状态、目标 cutoff、生成的 batch 和安全失败代码。点击按钮时，服务端固定 `target_cutoff_at` 为最近一个已经结束的上海四小时截止点，冻结当时所有已启用、已解析的 X 来源。重复点击同一目标范围只返回现有活动 run。

scheduled Worker 每 tick 推进活动手动 run：为其冻结来源持续补齐连续窗口，并仅对精确水位阻塞的终态任务创建一次 existing replacement。所有来源达到 target cutoff 后，控制面创建一个新的 immutable `x_collection_batch`，`scheduled_window_key` 使用 `manual:<run id>` 的独立身份；source rows 只引用每个来源恰好结束于 target cutoff 的真实任务和其已持久化 segment/no-new receipt。随后复用现有 settlement、daily judgement claim、Provider 和 completion 流程生成新的 v3 总结。旧 scheduled batch、旧失败 task 和旧 judgement version 均不被改写。

若任何冻结来源无法继续（未初始化、禁用/解析状态改变、或 replacement 后仍终态失败），run 标记 `failed` 并展示安全原因；它不输出一份假装完整的总结。Mac 关闭时 run 保持 queued/collecting；launchd Worker 在用户登录后继续。Codex 客户端关闭不影响 Worker。

### 管理员界面

在 `/admin` 概览增加一个小型 X 恢复卡片：按钮文字为“补采并重新生成 X 总结”。它只向管理员可见，点击后禁用并显示“已排队”或当前 run 的进度；不会暴露帖子、URL、异常原文、内部 Worker 凭据或 task ID。普通用户和未认证请求返回现有统一拒绝语义。

## 非范围

- 不自动重试任意终态失败，不删除、改写或回填旧 failed task/attempt/batch/version。
- 不改变单来源“立即更新”或历史回补入口的既有语义。
- 不让 Vercel 或浏览器直接访问 X、Chrome Profile 或本机凭据。
- 不为离线 Mac 新增云端采集器；离线请求只持久化排队状态。

## 验收标准

1. pgTAP 证明 scheduled tick 会逐窗口追赶落后来源，且不会为活跃/终态阻塞来源重复建 task；其他来源仍照常运行。
2. pgTAP 证明手动 run 仅管理员可创建、同一 cutoff 幂等、冻结来源与 cutoff、只接受连续 replacement、失败不产出 batch/version，成功时生成独立 immutable manual batch。
3. Worker 回归证明每个 tick 的顺序为“连续追赶 → scheduled batch/settlement → 手动 run 推进 → daily judgement”，并且既有 task claim/lease 行为不变。
4. 控制面 route、repository 与组件测试证明管理员可创建并观察 run；非管理员、无效 body 和重复点击安全失败或复用。
5. 生产验收在不暴露真实内容的条件下：现有落后来源获得连续任务，创建一条管理员手动 run，Worker 处理完成后 `/x` 出现新的完整 manual summary；若 AIInvestHK 合同仍失败，其 run 明确失败且其余来源不受阻塞。
