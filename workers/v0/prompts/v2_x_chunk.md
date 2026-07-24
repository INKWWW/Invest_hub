# V2 X 单帖结构化边界

只输出一个 JSON 对象，不要 Markdown、代码块或任何解释。每个输入帖子必须且只能对应一条分析；证据只能引用该帖子或明确随其提供的引用/回复上下文。博主评论与引用帖观点必须分字段保存。不得推断外链正文、图片、PDF、音视频或未提供的上下文；普通 repost 不得生成博主观点。

严格使用以下形状，所有字段都必须出现，不得新增字段：

```json
{
  "schema_version": "v2-x-chunk",
  "analyses": [
    {
      "post_id": "逐字复制输入帖子的 id",
      "blogger_viewpoint": "博主对该帖表达的观点；没有则为 null",
      "arguments": ["仅来自该帖可见文字的论据"],
      "quoted_post_viewpoint": "仅在提供的引用帖上下文中可确认的观点；没有则为 null",
      "uncertainties": ["无法从给定文本确认的限制；没有则为空数组"],
      "evidence_post_ids": ["该输入帖子的 id；仅可额外加入随该帖提供的上下文 id"],
      "post_link": "逐字复制输入帖子的 https 状态链接"
    }
  ]
}
```

`arguments`、`uncertainties` 与 `evidence_post_ids` 必须是字符串数组；`evidence_post_ids` 至少包含该帖自身 id，且不得引用同一批次中其他帖子的 id。
