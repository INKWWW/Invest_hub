Workflow profile: matt
Status: ready-for-agent
Approval: approved
Approved at: 2026-08-11
Approval evidence: 2026-08-11 用户在当前 Codex task 明确回复“批准该 Spec”

# 投资研究 Agent Feature Contract

## Problem Statement

Invest Hub 已经能够通过受邀账号登录，并阅读系统采集和整理的投资信息，但用户还不能在网站内围绕投资问题进行连续、可追溯的多轮研究。用户目前需要在不同工具之间手工组织问题、选择研究方法、保存历史结论和回忆此前关注的股票或行业；研究过程、证据、结论、额度消耗和失败原因也没有统一记录。现有 Reader 数据是所有用户共享的，而研究会话、个人结论、持仓相关信息和研究偏好属于个人数据，不能沿用共享 Reader 的访问边界。

用户需要的不是一个能够回答所有问题的通用聊天机器人，而是一个只服务于投资研究范围、能够选择或执行明确 Agent Skill、保留认知连续性、展示安全研究过程并在证据不足时保持克制的投资研究 Agent。首版还必须适合个人测试和少量测试身份：继续复用 Vercel、Supabase 与用户本机 Codex CLI Worker，不引入必须付费的新服务；当本机 Worker 不可用时，系统应明确停止接收研究任务，而不是制造不可兑现的排队或云端 fallback。

## Solution

在 Invest Hub 中新增独立的投资研究 Agent 工作台。登录用户可以创建自己的研究会话（Research Thread），在同一会话中围绕投资问题进行多轮对话；每个正式研究问题形成一个有界 Agent Run。系统先确定请求属于投资研究范围、暂不支持的投资范围、范围拒绝、产品帮助还是混合话题，再决定是否启动 Agent Run 和预占 Research Quota。

首版提供“智能”“大师投研”“下单前巴菲特拷问”和“持仓组合分析”四种可见选择。“智能”允许 Agent 根据问题选择一个已启用 Skill 或进行通用投资问答；用户显式选择 Skill 后，该次 Run 必须锁定所选 Skill。Runtime 对 Skill 版本、输入合同、Tool 权限、市场范围、调用上限和停止条件进行确定性准入。技术画线 Skill 与核心 Agent 并行开发，但通过独立 Feature Contract 接入，在其集成发布前不显示按钮，也不提前建设图片上传。

Vercel 继续承载页面和控制面 API，Supabase Auth、PostgreSQL 与 RLS 继续承担身份、持久化和用户隔离，用户本机 Worker 负责领取任务并调用 Codex CLI。Supabase 是 Research Thread、消息、Agent Run、Research Quota、Agent Trace、Thread Memory、Personal Long-term Memory 和持久化 Artifact 的唯一事实来源；本机文件只允许保存有期限、可删除的执行缓存和诊断材料。普通用户只能访问自己的用户研究空间，管理员可以在不冒充用户的前提下管理额度并查看、修改或删除全部用户的研究数据，所有管理员操作均被审计。

前端采用已确认的 A“纸面工作台”结构：左侧为当前用户的研究会话列表，右侧为当前会话消息与对话框，Skill 按钮位于对话框上方。运行期间显示从真实 Runtime 事件生成的可见研究过程（Research Progress），完成后可折叠查看；不展示模型原始 Chain-of-thought。回答应区分当前事实、证据、推断、分歧和缺失信息，时效性事实显示来源与日期，证据不足但仍形成有用研究时返回证据受限结果（Evidence-limited Result）。

## User Stories

1. As an authenticated Invest Hub user, I want an independent investment research Agent entry, so that I can start research without mixing it with the existing X or Discord Reader.
2. As an authenticated user, I want to create a research thread, so that related investment questions can remain in one continuous conversation.
3. As an authenticated user, I want to see only my own research threads, so that another ordinary user cannot discover my research interests or conclusions.
4. As an authenticated user, I want to reopen a previous research thread, so that I can continue from its persisted context on another browser session or device.
5. As an authenticated user, I want each research thread to receive a short automatic title, so that I can identify it in the session list.
6. As an authenticated user, I want to rename a research thread, so that its title matches the way I organize my research.
7. As an authenticated user, I want to delete a research thread after a clear confirmation, so that I can remove its messages, runs and thread artifacts.
8. As an authenticated user, I want thread deletion to explain that independent Personal Long-term Memory is managed separately, so that useful memory is not silently deleted or unexpectedly retained.
9. As an authenticated user, I want the thread list grouped by time, so that recent research is easy to locate without adding folders or search in the first version.
10. As a mobile user, I want the thread list to become a drawer, so that the conversation remains usable on a narrow screen.
11. As an authenticated user, I want to ask follow-up questions in the same research thread, so that the Agent can use relevant prior messages and Thread Memory.
12. As an authenticated user, I want a materially unrelated investment topic to remain possible in the same thread in the first version, so that an expensive topic-switching rule does not block ordinary use.
13. As an authenticated user, I want the product to distinguish a research thread from an Agent Run, so that one conversation can contain several bounded research executions.
14. As an authenticated user, I want ordinary greetings and Invest Hub product-help questions answered without starting research, so that simple navigation questions do not consume quota.
15. As an authenticated user, I want non-investment questions to receive a concise Scope Refusal, so that the Agent remains an investment product rather than a general assistant.
16. As an authenticated user, I want a request about an unsupported asset class to be identified as Unsupported Investment Scope rather than unrelated content, so that the response accurately explains the product boundary.
17. As an authenticated user, I want supported research to cover A-shares, Hong Kong stocks, U.S. stocks, ETFs, funds and listed REITs, so that the Agent matches my intended securities universe.
18. As an authenticated user, I want industry, macro, commodity, valuation, technical-analysis, investment-method, portfolio and risk questions supported when they directly serve securities research, so that the scope is useful without becoming generic finance chat.
19. As an authenticated user, I want crypto, foreign exchange, derivatives, bonds and private assets treated as unsupported in the first version, so that the Agent does not imply capabilities it has not earned.
20. As an authenticated user, I want a mixed request to receive an answer only for its investment portion and an explicit refusal for the unrelated portion, so that useful research can proceed without widening the domain.
21. As an authenticated user, I want unrelated portions excluded from research Tool inputs, persisted Trace summaries and Personal Long-term Memory, so that out-of-scope personal content is not unnecessarily retained.
22. As an authenticated user, I want to see “智能” as the default routing choice, so that I can ask a normal investment question without learning Skill internals.
23. As an authenticated user, I want to select at most one visible Skill before sending a question, so that the requested research workflow is unambiguous.
24. As an authenticated user, I want the selected Skill shown as a visible reference in the composer, so that I know which workflow will be used before submission.
25. As an authenticated user, I want a selected Skill to apply only to the next Agent Run, so that one choice does not silently become a permanent thread mode.
26. As an authenticated user, I want an explicitly selected Skill to remain locked during that Run, so that the Agent cannot silently replace my research method.
27. As an authenticated user, I want the final Run record to show the Skill actually used, so that the answer and Agent Trace are auditable.
28. As an authenticated user, I want “大师投研” to perform comprehensive listed-company research across business model, moat, management, industry, risk and valuation, so that I receive a coherent deep-research result.
29. As an authenticated user, I want “下单前巴菲特拷问” to check assumptions, contrary evidence, valuation, margin of safety, risk and decision discipline, so that I can reassess a decision immediately before placing an order.
30. As an authenticated user, I want the Agent to offer “下单前巴菲特拷问” when Auto detects a concrete investment decision or order intent, so that I can deliberately opt into the checklist.
31. As an authenticated user, I want a natural-language confirmation of that offer to select the checklist for the next Run, so that I do not have to click the button again.
32. As an authenticated user, I want the Agent not to repeat the same checklist offer after I decline it for the same security and decision, so that the conversation does not become intrusive.
33. As an authenticated user, I want the checklist offered again only for a new security, a new order decision or materially changed conditions, so that later recommendations remain relevant.
34. As an authenticated user, I want “持仓组合分析” to run only after I actively provide holdings and request portfolio-level analysis, so that a casual statement that I own one stock does not trigger a portfolio workflow.
35. As an authenticated user, I want an incompatible or incomplete explicit Skill request to ask for missing information before starting a Run, so that clarification does not consume quota.
36. As an authenticated user, I want Auto to be allowed to choose one enabled Skill or use general investment Q&A, so that not every valid question is forced into a named workflow.
37. As an authenticated user, I want only admitted, fixed-version Skills available, so that installation alone cannot expose an unreviewed workflow to website users.
38. As an authenticated user, I want the Agent to use my supplied text, primary company or regulatory disclosures, public web sources and approved quote or financial-data Tools, so that research is evidence-based.
39. As an authenticated user, I want time-sensitive facts to show their source and date, so that I can judge whether the evidence is current enough.
40. As an authenticated user, I want the answer to separate confirmed facts, source claims, Agent inference, disagreement and missing evidence, so that synthesis is not confused with raw fact.
41. As an authenticated user, I want an Evidence-limited Result when sources are insufficient, unavailable or contradictory, so that the Agent remains useful without fabricating certainty.
42. As an authenticated user, I want conditional investment judgments to identify their conditions, horizon and invalidation risks, so that they are not presented as unconditional trading instructions.
43. As an authenticated user, I want the Agent never to execute a trade, so that the final investment decision and action remain mine.
44. As an authenticated user, I want the Agent blocked from arbitrary shell access and unapproved data sources, so that research cannot escape its authorized Tool boundary.
45. As an authenticated user, I want one administrator-assigned Research Quota balance rather than a token counter, so that usage is simple to understand.
46. As an authenticated user, I want the remaining Research Quota visible in the Agent page, so that I know whether I can start another research Run.
47. As an authenticated user, I want one quota unit reserved only when a valid Agent Run formally begins, so that routing and clarification do not reduce my balance.
48. As an authenticated user, I want a usable successful answer to consume one quota unit regardless of internal model calls or Loop count, so that billing semantics remain stable.
49. As an authenticated user, I want an Evidence-limited Result to consume one quota unit, so that completed useful research is consistently accounted for.
50. As an authenticated user, I want Product Help, Scope Refusal, Unsupported Investment Scope and missing-input clarification not to consume quota, so that non-research responses are free.
51. As an authenticated user, I want cancellation and technical failure to release the quota reservation when no usable research answer is produced, so that system failures do not cost me a Run.
52. As an authenticated user, I want only one active Agent Run at a time, so that concurrent clicks cannot create duplicate cost or conflicting progress.
53. As an authenticated user, I want a repeated network submission with the same request identity to remain idempotent, so that retries do not start or charge a duplicate Run.
54. As an authenticated user, I want an Agent Run to continue on the server after I refresh or close the browser, so that a temporary disconnect does not destroy the research.
55. As an authenticated user, I want to reopen the page and see persisted Run status and completed progress, so that the browser connection is not the authority for execution.
56. As an authenticated user, I want to stop an active Run, so that I can end unwanted or overly long research.
57. As an authenticated user, I want Stop to terminate the associated Provider process and release the reservation, so that cancellation is real rather than cosmetic.
58. As an authenticated user, I want a failed Run to require an explicit new retry, so that the system does not silently spend another quota unit.
59. As an authenticated user, I want the page to show “Agent 暂时不可用” when the local Worker or Codex login is unavailable, so that I understand why new research cannot start.
60. As an authenticated user, I want historical threads to remain readable while the Worker is offline, so that temporary execution outages do not hide persisted research.
61. As an authenticated user, I want the system to reject new Runs rather than queue them indefinitely while the Worker is offline, so that no false expectation of completion is created.
62. As an authenticated user, I want Research Progress generated from real Runtime events, Tool calls, source progress and safe summaries, so that I can understand what the Agent is doing.
63. As an authenticated user, I want Research Progress expanded while a Run is active and collapsible after completion, so that progress is visible without overwhelming the final answer.
64. As an authenticated user, I want completed steps and a safe failure reason preserved after failure, so that I can understand where the Run stopped.
65. As an authenticated user, I want raw Chain-of-thought, private Prompt text, secrets and local paths excluded from the page, so that progress transparency does not leak sensitive internals.
66. As an authenticated user, I want the current thread to retain concise, traceable Thread Memory, so that long conversations remain coherent without resending the entire transcript to the model.
67. As an authenticated user, I want complete conversation history to remain readable even when model context uses a compressed summary, so that compression does not erase the record.
68. As an authenticated user, I want Personal Long-term Memory to retain my continuing stock, fund, industry and topic interests, so that future threads can reflect what I have historically cared about.
69. As an authenticated user, I want Personal Long-term Memory to retain dated, conditional Research Conclusion Memory linked to its source Run, so that later answers can preserve cognitive continuity without treating old conclusions as current facts.
70. As an authenticated user, I want Personal Long-term Memory to retain stable research and output preferences, so that future answers better match how I work.
71. As an authenticated user, I want old Research Conclusion Memory retained when a later conclusion supersedes or invalidates it, so that the history is not silently rewritten.
72. As an authenticated user, I want low-sensitivity interests and well-supported conclusions to be saved automatically after a successful Run, so that useful continuity does not require constant manual filing.
73. As an authenticated user, I want holdings, asset size and personal financial circumstances saved only after my explicit request, so that sensitive financial data is not inferred into long-term memory.
74. As an authenticated user, I want a “我的记忆” page where I can view, edit and delete my Memory, so that I control what the Agent carries across threads.
75. As an authenticated user, I want deleting a Memory entry to stop future retrieval of that entry, so that deletion has an observable product effect.
76. As an authenticated user, I want the same persisted memory available across devices, so that continuity does not depend on a folder on one computer.
77. As an authenticated user, I want my research data stored in Supabase under my ownership boundary, so that the website can reliably enforce access regardless of which Worker executes the Run.
78. As an ordinary user, I want another ordinary user denied access to my threads, messages, runs, artifacts, quota and memory even when an identifier is guessed, so that row identifiers cannot be used for cross-user access.
79. As an administrator, I want to assign or adjust a user's lifetime Research Quota balance, so that access can be controlled during personal testing.
80. As an administrator, I want to inspect every user's Research Thread, Agent Run, Memory and sanitized Agent Trace, so that I can diagnose and improve the system.
81. As an administrator, I want to modify or delete user research data within an explicit admin workspace, so that I can handle test data and user requests.
82. As an administrator, I want every administrative read, mutation and deletion of user research data audited under my real administrator identity, so that elevated access remains accountable.
83. As an administrator, I want to be prevented from impersonating a user to post messages or start Runs, so that audit history cannot misrepresent who initiated research.
84. As an administrator, I want Agent management separated from the chat sidebar, so that user conversation navigation stays simple.
85. As an operator, I want each Agent Run to have a structured Agent Trace containing ordered orchestration events, model and Tool metadata, timing, usage, errors, safe summaries and Artifact references, so that failures and quality can be investigated.
86. As an operator, I want Trace data to exclude secrets, cookies, browser credentials, hidden reasoning and duplicated private source bodies, so that observability does not become a second sensitive-data store.
87. As an operator, I want sanitized Trace records retained for at most 30 days, so that enough diagnostic history exists without unbounded database growth.
88. As an operator, I want expired reservations and abandoned Worker leases recovered deterministically, so that a crashed process cannot permanently consume quota or block the user.
89. As an operator, I want the application database to rebuild any Run without relying on a Codex session, so that Provider session loss does not destroy conversation continuity.
90. As an operator, I want local raw Provider JSONL and temporary execution files treated as owner-only disposable evidence, so that they never become user Memory or cloud-visible hidden reasoning.
91. As an operator, I want database-size and retention pressure observable, so that the product can remain within the intended Vercel and Supabase free-tier envelope during testing.
92. As a test administrator, I want to register multiple email-based Test Identities and assign separate quotas, so that authentication, ownership and isolation can be validated without claiming real external-user capacity.
93. As a test administrator, I want the real Codex CLI event contract verified with one bounded representative research case and cancellation case, so that the production adapter is based on observed events rather than help text assumptions.
94. As a test administrator, I want one real local end-to-end acceptance path from browser through database and Worker with a deterministic Provider, so that the product lifecycle is proven without model nondeterminism.

## Implementation Decisions

1. The feature is an independent investment research Agent capability. It does not redefine the existing numbered modules 2–4 and does not change the existing X or Discord Reader behavior.
2. The deployment topology remains Vercel for the Next.js control plane, Supabase for Auth/PostgreSQL/RLS, and a user-operated local Worker for long-running Agent execution and Codex CLI access. The first version must not require a new paid managed service.
3. Vercel request handlers do not own long-running Provider processes. They validate authenticated requests, perform admission and durable state transitions, and expose persisted state; the local Worker claims and executes admitted Runs.
4. Supabase is the sole authority for Research Thread, conversation messages, Agent Run, Agent Trace, Research Quota, Quota Reservation, Artifact metadata, Thread Memory, Memory Candidate, Personal Long-term Memory and administrator audit records.
5. Local Worker files are execution cache or diagnostic evidence only. They must be owner-only, bounded by a retention policy and safely disposable. No user's cross-session Memory may depend on a local directory, Codex session file or browser local storage.
6. Every user-private entity carries an immutable owner identity. RLS enforces owner-bound access for ordinary users; authentication without an ownership predicate is insufficient. Browser code never receives a service-role credential.
7. Administrator access is a separate privileged path. It permits viewing, modifying and deleting user research data and managing quota, but does not permit creating user messages, continuing a user's thread or initiating a Run as that user. Admin access and mutations create audit events containing the real administrator identity, target, action and timestamp.
8. User research data is logically isolated inside the shared Supabase project rather than placed in a database, schema or physical folder per user.
9. A Research Thread is the durable multi-turn container. User and assistant messages remain readable as conversation history; an Agent Run is created only for a question that passes admission and begins research execution.
10. Product Help, brief greeting, Scope Refusal, Unsupported Investment Scope and missing-input clarification are persisted as ordinary conversation responses when appropriate but do not create a billable Agent Run, call research Tools, write Personal Long-term Memory or reserve quota.
11. Routing uses the following product outcomes before Tool or Provider execution: supported investment research, Product Help, Scope Refusal, Unsupported Investment Scope, missing-input clarification and mixed request. Classification output is validated against this closed set.
12. Supported investment research covers A-shares, Hong Kong stocks, U.S. stocks, ETFs, funds, listed REITs and directly related company, industry, macro, commodity, valuation, technical-analysis, investment-method, portfolio and risk questions. Crypto, foreign exchange, derivatives, bonds and private assets are Unsupported Investment Scope in the first version.
13. A mixed request executes only the supported investment portion and explicitly declines the rest. A formally started investment Run consumes quota normally; unrelated content is excluded from Tool inputs, persisted Trace summaries and Personal Long-term Memory beyond the minimum routing decision needed to enforce the boundary.
14. The visible Skill options at core release are “智能”, “大师投研”, “下单前巴菲特拷问” and “持仓组合分析”. Display labels are separate from stable internal Skill identifiers.
15. One Agent Run accepts at most one Selected Skill. The selection is visible before submission, is submitted as structured input, is locked for that Run and is cleared after the Run. Runtime records the actual fixed Skill version used.
16. Auto may choose one enabled Skill or use general investment Q&A. An explicit selection cannot be silently replaced; incompatible or incomplete input returns clarification before Run creation and quota reservation.
17. `investment-research` is admitted for comprehensive listed-company research covering business model, moat, management, industry, risk and valuation. Its user-facing label is “大师投研”.
18. `investment-checklist` has no dependency on a pre-existing structured thesis. When Auto detects a concrete investment decision or order intent, it first offers “下单前巴菲特拷问”; natural-language acceptance selects it for the next Run. The workflow reviews assumptions, contrary evidence, valuation, margin of safety, risk and decision discipline and is not used as initial screening or full company research.
19. A rejected checklist offer is suppressed for the same security and decision intent. A new security, new order decision or materially changed conditions may make the offer eligible again.
20. `portfolio-review` runs only when the user actively supplies holdings and requests portfolio-level analysis of concentration, correlation, risk, opportunity cost or adjustment direction. Merely saying that one security is held does not trigger it.
21. Third-party Skills retain a pinned upstream version. Invest Hub maintains only the lightweight project Description, user-facing label and Runtime admission configuration needed for this batch; the workflows are not rewritten into heavy project wrappers. License, security, required configuration, input contract, market support, Tool allowlist, call limit, stop conditions, Eval evidence and admin trial are checked before enablement. Installation is not enablement.
22. Runtime is deterministic for authorization, state transitions, quota, concurrency, retries, cancellation, Tool permissions, Skill admission, loop cap, persistence and Trace. The model may interpret the question, choose among admitted capabilities in Auto, plan research, interpret evidence and compose the answer, but it cannot override Runtime constraints.
23. Approved research sources are user-supplied text, issuer or regulatory disclosures, public web material and separately approved quote or financial-data Tools. Arbitrary shell access and unapproved sources are prohibited. Exact external data providers remain a Delivery Plan decision subject to the approved-source contract and free-tier constraint.
24. Time-sensitive claims include source and observation or publication date. Answers distinguish confirmed facts, attributed source claims, Agent inference, disagreements, uncertainty and missing information. Unresolved media or unavailable source bodies cannot be guessed.
25. When evidence is insufficient, unavailable or contradictory but useful research has been completed, the result is an Evidence-limited Result and settles one quota unit. When no usable research answer exists because of technical failure, the Run fails and releases its reservation.
26. The Agent may express conditional judgments and action tendencies with relevant conditions, time horizon and invalidation risks, but does not execute trades or present uncertain conclusions as unconditional buy or sell instructions.
27. Research Quota is an administrator-assigned lifetime balance, not a monthly allowance, token budget, Tool-call count or Research Thread count. The page shows the user's remaining available balance.
28. Formal Run admission atomically verifies authenticated ownership, Worker availability, sufficient quota, absence of another active Run and request idempotency, then creates the Run and one Quota Reservation. Concurrent admissions for the same user cannot create more than one active Run or double-reserve quota.
29. A usable success or Evidence-limited Result commits exactly one reservation. Scope Refusal, Product Help, Unsupported Investment Scope, clarification, user cancellation and technical failure release or avoid reservation. Reservation commit and release are idempotent and recorded in an auditable ledger.
30. One active Agent Run per user is enforced in the database authority rather than only in the browser. An expired Worker lease or abandoned reservation has a deterministic recovery path that does not silently start an additional model attempt.
31. A Run is a server-side recoverable task whose status does not depend on the browser connection. Persisted Run state and Research Progress are readable after refresh or reconnect. Historical threads remain readable when the local Worker is offline.
32. Worker heartbeat and capability freshness determine Agent availability. When the Worker, Codex CLI or required login is unavailable, the UI shows “Agent 暂时不可用”; the system does not create, reserve or indefinitely queue a new Run and does not invoke a cloud Provider fallback.
33. Stop is a durable cancellation request. The Worker observes it, terminates the associated Provider process group, stops further Tool or model work, records the terminal state and releases the reservation. A cancelled Run cannot later commit a success. The page reflects that cancellation may take a bounded interval to settle.
34. The first version has no answer branching, edit-and-rerun, one-click Regenerate or automatic retry that can spend another quota unit. After failure, a user explicitly submits a new Run.
35. Provider sessions are disposable execution optimizations. The next Run reconstructs necessary context from persisted messages, Thread Memory, relevant Personal Long-term Memory and Artifact references; it does not require `codex exec resume` to preserve product continuity.
36. The Provider adapter translates provider-specific events into a versioned, provider-neutral Runtime event contract. Frontend Research Progress depends only on the neutral contract, not raw Codex JSONL field names.
37. Research Progress is built only from real Runtime state, Tool calls, source progress, safe stage commentary and any Provider-supported Reasoning Summary that passes sanitization. It is expanded while running, collapsible after completion and retains completed steps plus a safe failure reason.
38. Raw Chain-of-thought, private Prompt text, secrets, cookies, browser credentials, service-role credentials, raw local paths and unrestricted Provider JSONL are not stored in cloud Trace or shown to users. Help text proving that `codex exec --json` exists is not accepted as proof of its event schema or cancellation behavior.
39. Agent Trace records ordered orchestration events, event type, safe input/output summary, selected Skill and version, Tool and model metadata, timing, usage, errors, stop reason and Artifact references. Trace is for diagnosis and evaluation, not a duplicate conversation or hidden-reasoning store.
40. Sanitized Trace data that does not duplicate chat bodies is retained for no more than 30 days and then automatically removed. Durable answers, messages, Memory and user-visible Artifact metadata follow their own user-controlled lifecycle.
41. Thread Memory consists of recent relevant dialogue, a rolling traceable summary, current research state and necessary evidence references. Compression changes model context, not the readable conversation record, and every summary remains attributable to the originating thread messages or Runs.
42. Personal Long-term Memory contains only Interest Memory, Research Conclusion Memory and Preference Memory in the first version. It is not a full chat copy, Skill registry, shared source library or model parameter store.
43. A completed Run may create Memory Candidates. Low-sensitivity interests and conclusions with time, conditions and Run or Artifact provenance may be admitted automatically. Holdings, asset size and personal financial circumstances require explicit user instruction before admission.
44. Research Conclusion Memory is versioned. A later conclusion can supersede or invalidate an earlier conclusion through an explicit relationship; it cannot silently overwrite the historical record or be presented later as an undated current fact.
45. The account menu exposes a minimal “我的记忆” page where the user can list, edit and delete Personal Long-term Memory. Deleted or inactive entries are excluded from future retrieval. The first version uses ordinary PostgreSQL retrieval and does not require a Vector Database or embedding service.
46. Deleting a Research Thread removes that user's visible messages, Runs and thread Artifacts after confirmation but does not silently delete separately admitted Personal Long-term Memory. The UI directs the user to Memory management for that separate action.
47. The Agent page follows the selected A prototype: independent top-level entry, two-column desktop layout, left time-grouped thread list, right multi-turn conversation, bottom composer and a lightweight Skill row above the composer. It reuses Invest Hub visual tokens and interaction language rather than copying ChatGPT or Codex styling.
48. The thread list supports automatic title, rename and delete. Mobile collapses it into a drawer. The first version does not add thread search, folders, favorites, branches or management controls to the chat sidebar.
49. Agent management is an independent area within the existing administrator workspace. It provides quota assignment and authorized inspection or management of Research Threads, Runs, Memory and Trace without exposing those controls in the ordinary user's sidebar.
50. Core input is text only. Durable storage design does not pre-create generic upload or image contracts for a Skill that has not yet been delivered.
51. Capacity design targets the existing Vercel and Supabase free tiers: text and structured records are stored compactly; raw Provider JSONL and redundant source bodies are excluded from Supabase; database size and retention pressure are observable. Free-tier targeting is a constraint, not a guarantee that external platform limits will never change or be exceeded.
52. Existing invitation registration and login are reused. First acceptance uses multiple administrator-controlled Test Identities with separate email accounts and quotas; this proves isolation behavior but does not claim external-user demand, Provider concurrency or production SLA.

## Testing Decisions

1. Tests assert externally observable contracts—authorization outcome, persisted lifecycle state, quota balance, isolation, displayed progress, answer shape and cancellation result—rather than internal function calls, component structure, Prompt wording or raw Provider event fields.
2. The primary seam is one real local end-to-end path: an authenticated browser uses the Agent page and Next control plane against local Supabase; a real Worker state machine claims the Run and uses a deterministic scripted Provider adapter; the result, progress, Trace summary, quota settlement and Memory effects are read back through the product. This is the highest seam and the main release evidence.
3. The primary seam covers at least: successful Auto research; explicit Skill locking; missing-input clarification without reservation; Product Help; Scope Refusal; Unsupported Investment Scope; mixed-topic filtering; Evidence-limited Result; Worker offline admission rejection; browser refresh and reconnect; user cancellation; explicit retry; duplicate submission idempotency; user-to-user isolation; administrator visibility without impersonation; and Memory create, supersede, edit and delete behavior.
4. The primary seam uses at least two ordinary Test Identities and one administrator. It proves that one ordinary user cannot access another user's Thread, message, Run, quota, Artifact, Trace or Memory by listing or guessed identifiers, while the administrator can use only the audited admin path.
5. Prior art for the primary seam is the repository's deterministic Worker E2E harness and authenticated Reader acceptance, but the new seam must use the actual local HTTP and Supabase boundaries instead of an in-memory control-plane imitation for the lifecycle being claimed.
6. The first specialist seam is pgTAP/RPC testing for database authority. It validates owner-bound RLS, admin policies, immutable ownership, one-active-Run enforcement, atomic reservation, commit/release idempotency, simultaneous admissions, duplicate request identity, cancellation-versus-completion races, expired lease recovery, abandoned reservation recovery and administrator audit writes.
7. Database concurrency tests use real concurrent transactions where the contract concerns races. A sequential state imitation is not accepted as proof that duplicate quota or active Runs are impossible.
8. Prior art for the database seam is the existing Supabase pgTAP coverage for RLS, task claim leases, persistence receipts, idempotent completion and failure recovery. Agent tests extend that authority rather than reimplementing it in a Python-only state model.
9. The second specialist seam is a bounded real Codex CLI Spike. It executes one representative supported investment case with `codex exec --json`, captures the actual event stream through the production candidate parser, and validates the mapping to provider-neutral Runtime events and user-safe Research Progress.
10. The Codex Spike also performs one real cancellation case and verifies bounded process-group termination, no late success commit, safe diagnostics and reservation release. It records the observed CLI version and sanitised event categories without publishing raw private prompts, complete responses, local paths or hidden reasoning.
11. The representative Codex case is proven before a bulk Eval set is created. Its model input excludes expected-answer metadata; its generated output passes the real production parser; semantic requirements are checked; severe schema, evidence and sanitization violations fail closed; and the retained report contains only safe evidence.
12. Real Codex output is not part of the ordinary deterministic regression suite. Once the Spike establishes the adapter contract, fixtures derived only from sanitised event shapes exercise success, malformed JSONL, unknown event, truncation, timeout, cancellation and provider-failure paths reproducibly.
13. Page and API tests continue using the existing Vitest style for focused presentation, routing, authorization and payload validation, while pure Runtime and Worker state transitions use focused deterministic tests. These tests support the three accepted seams but do not replace their external lifecycle evidence.
14. Skill Evals verify Description routing, explicit-selection priority, input requirements, allowed Tool set, stop conditions and required answer coverage. Checklist recommendation suppression and portfolio-review non-trigger cases are included as negative examples.
15. Scope Evals include supported questions, unsupported investment assets, unrelated questions, Product Help, greetings and mixed requests. Severe domain escapes fail closed before any research Tool, Provider execution, quota reservation or long-term Memory write.
16. Memory tests verify provenance, sensitive-data consent, supersession, deletion effects, cross-thread recall and no cross-user retrieval. They do not treat a complete transcript copy as proof of useful Memory.
17. Trace and Research Progress tests use allowlisted structured fields and adversarial payloads containing secrets, local paths, raw source bodies and instruction-like text. Unsafe fields are rejected or redacted deterministically before persistence or display.
18. Free-tier capacity verification measures the persisted size of a representative Thread, Run, Trace and Memory set, confirms 30-day Trace cleanup behavior and demonstrates that raw JSONL is not stored in Supabase. It produces an operational estimate rather than a promise of indefinite free usage.
19. Production deployment, remote migration, real external-user onboarding and state-changing acceptance remain separate Release Authorization activities. Passing local tests does not authorize or prove those activities.

## Out of Scope

- X original posts and Discord-derived summaries are not Agent sources in this feature. No X/Discord retrieval Tool, orchestration, citation contract or Eval is built, and the existing collection and Reader behavior remains unchanged.
- The self-developed technical chart Skill is not part of this Feature Contract. It continues in parallel and later receives a separate integration Feature Contract and ticket graph. Until that integration release, “技术画线分析” is hidden.
- Core Agent input does not support K-line screenshots, generic images, PDFs, Word documents, spreadsheets, CSV files, financial-report screenshots or other uploads. No speculative upload schema or storage path is created.
- The later technical chart integration will require a user-uploaded K-line screenshot and will not fetch data from Futu, accept only a symbol or company name, retrieve OHLCV, build a source candlestick chart or prescribe the Skill's internal drawing workflow under this Contract.
- Crypto, foreign exchange, derivatives trading, bonds and private assets are not researched in the first version.
- The Agent is not a general assistant, automated adviser, stock picker with guaranteed outcomes or transaction-execution system. It does not place, route or simulate brokerage orders.
- User-specific X/Discord sources, shared-source retrieval, Reader personalization and per-user collection configuration are not added.
- Cloud Provider fallback, Vercel-hosted long-running model execution, multi-Worker scaling, high-availability operation and external-user throughput or SLA are not included.
- A paid LLM API, paid Vector Database, embedding service, additional paid database or new paid infrastructure is not required by the first version.
- Monthly or periodic quota reset, token accounting, model-call billing, quota purchasing and payment integration are not included.
- Multiple simultaneous Runs for one user, background infinite queues while the Worker is offline and automatic retries that can create new charges are not included.
- Answer branching, edit-and-rerun, one-click Regenerate, session forking, conversation search, folders, favorites and shared threads are not included.
- Automatic enforcement that a materially new investment topic must create a new Research Thread is deferred as a TODO because its interaction and implementation cost is not yet justified.
- A physical database, schema or local folder per user is not created. Logical ownership and RLS inside the existing Supabase project are the isolation model.
- Raw Chain-of-thought, unrestricted Codex JSONL, private Prompt bodies, credentials and local diagnostic paths are not exposed as Research Progress or stored in Supabase.
- Platform-native audit-log products, automatic backups and uptime guarantees unavailable on the free plans are not silently assumed. Any future need for them requires a separate cost and release decision.
- This approved Feature Contract does not by itself authorize implementation tickets, application code, database migrations, Provider execution, remote writes, deployment or production acceptance.

## Further Notes

- The complete Feature Contract was explicitly approved by the user on 2026-08-11. Its approval freezes the product and acceptance contract; `Status: ready-for-agent` remains a routing state, not the source of authorization.
- The complete 17-ticket graph was explicitly approved by the user on 2026-08-11 and is now the Delivery Plan. The current implementation frontier is Ticket 01 and Ticket 02; Ticket 17 still requires separate Release Authorization before any external-state operation.
- The A “纸面工作台” throwaway prototype is the interaction reference for hierarchy and visual direction, not implementation code or a pixel-perfect acceptance artifact.
- The local CLI observed during Discovery is `codex-cli 0.144.3`, whose help exposes `codex exec --json`, `codex exec resume` and image input. Only the bounded real Spike may establish the event, cancellation and sanitization contract used by this feature.
- Free-tier limits and terms are external and may change. This Contract requires a design that fits the current personal testing model and does not require a paid service, while keeping capacity observable and preserving an explicit future migration path.
- The technical chart Skill may be developed in parallel with this feature. Its delivery does not mutate this approved Contract; integration starts only after its own Feature Contract and Delivery Plan are approved.

## Comments

- 2026-08-11：用户审阅完整 Spec 后明确回复“批准该 Spec”。Feature Contract 获批；下一门禁为 `to-tickets` 生成完整 ticket graph，并由用户单独审批 Delivery Plan。
- 2026-08-11：用户审阅 17 张 tickets 及 blocking edges 后明确回复“批准完整 ticket graph”。Delivery Plan 获批；Ticket 01 与 Ticket 02 成为当前 implementation frontier。
