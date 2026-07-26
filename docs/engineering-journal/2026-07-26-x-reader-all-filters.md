# 2026-07-26 X 阅读页全量筛选与管理员入口

## 范围

本次只改进已登录 X 阅读页的导航与呈现：管理员可从账户区域进入配置管理；博主和日期默认均为“全部”；结果按独立的博主 × 日期日卡片展示。未修改数据库、采集、任务、覆盖水位、checkpoint 或摘要生成。

## 实现边界

- `SessionControls` 只在现有 `admin` 角色下渲染 `/admin` 入口；普通用户的 DOM 中不含该链接，服务端 `/admin` 角色门禁保持原样。
- `XReader` 对全部数据做纯呈现筛选。它绝不把不同博主或日期的内容重新汇总，每张卡仍保留来源、自然日、状态、观点与折叠证据。
- URL 可用 `source` 和 `date` 恢复指定筛选；没有参数即为全部。Reader API 把 `all` 规范化为未筛选而非来源键或日期。
- 仅沿用 reader-safe DTO，不新增原始内容、私有引用、Cookie、Profile、Worker、Prompt 或 Provider 暴露面。

## 测试与验证

先写入并确认失败的测试，覆盖管理员入口、默认全部、多作者日卡、作者与日期的组合筛选、URL 筛选恢复，以及 Reader API 对 `all` 的规范化。初次失败原因分别为入口不存在、只渲染首个作者/日期、页面忽略 URL 和 API 将 `all` 当作非法日期。

实现后，在隔离 worktree 中完成：

```text
npm test       32 个测试文件，139 项通过
npm run lint   通过
npm run build  通过（Next.js production build）
```

合并到本地 `main` 后，脱敏检查和 `git diff --check` 均通过。已部署至 Vercel production：`dpl_FB5jLcR7tneBu58PzBEgNywj7jPS` 状态为 `Ready`，生产别名为 `https://invest-hub-v0-control-plane.vercel.app`。匿名请求 `/x` 返回登录页 `200`（最终 URL 为 `/login?next=%2Fx`），确认阅读数据仍受登录保护。
