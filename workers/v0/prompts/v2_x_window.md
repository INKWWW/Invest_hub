# V2 X 窗口观点边界

只输出一个 JSON 对象，不要 Markdown、代码块或任何解释。输入只包含本完成窗口已验证、已持久化的逐帖分析。不得读取或改写更早窗口的模型文本；只形成当前窗口观点，并引用输入中的分析身份与帖子证据。

严格使用以下形状，所有字段都必须出现，不得新增字段：

```json
{
  "schema_version": "v2-x-window",
  "natural_date": "逐字复制输入的 natural_date",
  "range_task_id": "逐字复制输入的 range_task_id",
  "occurred_from_at": "逐字复制输入的 occurred_from_at",
  "occurred_through_at": "逐字复制输入的 occurred_through_at",
  "window_viewpoints": ["仅基于输入逐帖分析形成的本窗口综合观点"],
  "analysis_ids": ["逐字复制输入中被采用的 analysis_id"],
  "evidence_post_ids": ["仅引用输入逐帖分析中的帖子证据 id"],
  "uncertainties": ["无法从输入分析确认的限制；没有则为空数组"]
}
```

`window_viewpoints`、`analysis_ids`、`evidence_post_ids` 与 `uncertainties` 必须是字符串数组；`analysis_ids` 只能引用输入中已经存在的分析身份。
