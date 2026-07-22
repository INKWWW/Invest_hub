# V1.1 Discord daily author and topic synthesis

Return one JSON object only, with no Markdown fence or prose outside JSON.

You receive verified fact units, a safe message identity catalog, and the
configured author profiles for one Shanghai natural date. Do not use any raw
message text beyond the supplied fact units. Do not create an author card for
an author absent from the configured profiles. Every author card and every
named viewpoint must cite only the supplied message IDs that belong to that
named author. Do not turn methodology into individual stock trading
instructions. State missing evidence and unparsed media as uncertainty.

Return exactly this shape:

```json
{
  "schema_version": "v1.1",
  "natural_date": "YYYY-MM-DD",
  "as_of": "ISO-8601 instant",
  "author_cards": [
    {
      "author_id": "stable Discord author ID",
      "author_display": "observed display name",
      "core_logic": {
        "market_trend": "string or null",
        "stock_judgments": [
          {
            "subject": "ticker, company, or null",
            "judgment": "string",
            "reasoning": "string or null",
            "source_message_ids": ["message ID"]
          }
        ]
      },
      "operation_tendency": {"market": "string or null", "stocks": "string or null"},
      "methodology": ["string"],
      "uncertainty": ["string"],
      "source_message_ids": ["message ID"]
    }
  ],
  "topic_discussions": [
    {
      "title": "string",
      "summary": "string",
      "viewpoints": [
        {
          "author_id": "stable Discord author ID",
          "author_display": "observed display name",
          "viewpoint": "string",
          "reasoning": "string or null",
          "operation_tendency": "string or null",
          "source_message_ids": ["message ID"]
        }
      ],
      "uncertainty": ["string"],
      "source_message_ids": ["message ID"]
    }
  ],
  "warnings": ["string"]
}
```

Use empty arrays and `null` when evidence is absent. If any supplied message
has unparsed media, include `存在未解析媒体` in `warnings` and preserve the
uncertainty instead of inferring the missing content.
