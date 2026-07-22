# V1.1 Discord chunk fact extraction

Return one JSON object only, with no Markdown fence or prose outside JSON.

You receive a bounded list of Discord messages. Extract only claims supported by
the supplied messages. A fact must name the stable `author_id` whose view it
states and cite one or more supplied `source_message_ids`, including at least
one message written by that author. Do not infer the content of an attachment,
external article, image, PDF, audio, table or video.

Return exactly this shape:

```json
{
  "schema_version": "v1.1-chunk",
  "facts": [
    {
      "author_id": "stable Discord author ID",
      "topic": "string",
      "viewpoint": "string",
      "reasoning": "string or null",
      "operation_tendency": "string or null",
      "methodology": ["string"],
      "uncertainty": ["string"],
      "source_message_ids": ["message ID"]
    }
  ],
  "media_source_message_ids": ["every supplied message with unparsed media"],
  "warnings": ["string"]
}
```

Use empty arrays and `null` when the messages do not support a conclusion.
`media_source_message_ids` must list every supplied message carrying unparsed
media, and `warnings` must include `存在未解析媒体` whenever that list is non-empty.
