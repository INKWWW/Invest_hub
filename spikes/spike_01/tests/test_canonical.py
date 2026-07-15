import json
import unittest
from pathlib import Path

from spike_01.canonical import normalize_page
from spike_01.model import RawMessage, RawPage


def raw_page_from_payload(payload):
    return RawPage(
        page_id=payload["page_id"],
        source_container_id=payload["source_container_id"],
        cursor_before=payload["cursor_before"],
        cursor_after=payload["cursor_after"],
        messages=tuple(
            RawMessage(ordinal=index, payload=message)
            for index, message in enumerate(payload["messages"])
        ),
        raw_payload_ref=payload["raw_payload_ref"],
    )


class CanonicalTests(unittest.TestCase):
    def test_normalize_page_preserves_identity_and_evidence(self):
        payload = json.loads(
            Path("spikes/spike_01/fixtures/basic_page.json").read_text()
        )
        message = normalize_page(
            raw_page_from_payload(payload),
            "test-account",
        )[0]
        self.assertEqual(message.external_item_id, "message-001")
        self.assertEqual(message.author_id, "author-001")
        self.assertEqual(message.author_name, "Analyst A")
        self.assertEqual(message.source_container_id, "channel-public-001")
        self.assertEqual(message.published_at, "2026-01-01T08:00:00Z")
        self.assertEqual(message.content_text, "人工构造的公开测试消息，ticker ABC。")
        self.assertEqual(
            message.source_url,
            "https://discord.example/messages/message-001",
        )
        self.assertEqual(message.raw_payload_ref, "fixture://basic_page.json")

    def test_normalize_page_preserves_reply_quote_and_attachment(self):
        payload = {
            "page_id": "page-002",
            "source_container_id": "channel-public-001",
            "cursor_before": "cursor-001",
            "cursor_after": "cursor-002",
            "raw_payload_ref": "fixture://relations",
            "messages": [
                {
                    "id": "message-002",
                    "author": {"id": "author-002", "name": "Analyst B"},
                    "channel_id": "channel-public-001",
                    "published_at": "2026-01-01T08:01:00Z",
                    "content": "reply",
                    "content_type": "text",
                    "reply_to": {"id": "message-001"},
                    "quote": {
                        "id": "message-001",
                        "content": "quoted",
                        "resolved": True,
                    },
                    "attachments": [
                        {
                            "name": "report.pdf",
                            "content_type": "application/pdf",
                            "url": "https://discord.example/report.pdf",
                        }
                    ],
                    "source_url": "https://discord.example/messages/message-002",
                }
            ],
        }
        message = normalize_page(
            raw_page_from_payload(payload),
            "test-account",
        )[0]
        self.assertEqual(message.parent_item_id, "message-001")
        self.assertEqual(message.quoted_item.external_item_id, "message-001")
        self.assertTrue(message.quoted_item.resolved)
        self.assertEqual(message.attachments[0].name, "report.pdf")
        self.assertEqual(
            message.attachments[0].content_type,
            "application/pdf",
        )


if __name__ == "__main__":
    unittest.main()
