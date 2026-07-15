import unittest

from spike_01.canonical import normalize_page
from spike_01.model import RawMessage, RawPage
from spike_01.validator import validate_page


def page_for(payloads):
    return RawPage(
        page_id="page-test",
        source_container_id="channel-public-001",
        cursor_before=None,
        cursor_after="cursor-next",
        messages=tuple(
            RawMessage(ordinal=index, payload=payload)
            for index, payload in enumerate(payloads)
        ),
        raw_payload_ref="fixture://validator",
    )


def payload(message_id="message-001", channel_id="channel-public-001"):
    return {
        "id": message_id,
        "author": {"id": "author-001", "name": "Analyst A"},
        "channel_id": channel_id,
        "published_at": "2026-01-01T08:00:00Z",
        "content": "public fixture",
        "content_type": "text",
        "reply_to": None,
        "quote": None,
        "attachments": [],
        "source_url": "https://discord.example/messages/" + message_id,
    }


class ValidatorTests(unittest.TestCase):
    def test_valid_message_is_checkpoint_safe(self):
        messages = normalize_page(
            page_for([payload()]),
            "test-account",
        )
        report = validate_page(
            messages,
            "channel-public-001",
            frozenset(),
        )
        self.assertEqual(report.state, "accepted")
        self.assertTrue(report.checkpoint_safe)
        self.assertEqual(report.accepted_ids, ("message-001",))

    def test_missing_author_id_is_invalid_and_not_checkpoint_safe(self):
        invalid = payload()
        invalid["author"] = {"name": "Missing ID"}
        messages = normalize_page(page_for([invalid]), "test-account")
        report = validate_page(
            messages,
            "channel-public-001",
            frozenset(),
        )
        self.assertEqual(report.state, "invalid")
        self.assertFalse(report.checkpoint_safe)
        self.assertTrue(any(issue.field == "author_id" for issue in report.issues))

    def test_channel_conflict_is_invalid(self):
        messages = normalize_page(
            page_for([payload(channel_id="channel-other")]),
            "test-account",
        )
        report = validate_page(
            messages,
            "channel-public-001",
            frozenset(),
        )
        self.assertEqual(report.state, "invalid")
        self.assertFalse(report.checkpoint_safe)

    def test_known_id_is_duplicate(self):
        messages = normalize_page(page_for([payload()]), "test-account")
        report = validate_page(
            messages,
            "channel-public-001",
            frozenset({"message-001"}),
        )
        self.assertEqual(report.state, "duplicate")
        self.assertTrue(report.checkpoint_safe)
        self.assertEqual(report.duplicate_ids, ("message-001",))

    def test_unknown_reply_is_unresolved_but_checkpoint_safe(self):
        item = payload(message_id="message-002")
        item["reply_to"] = {"id": "message-missing"}
        messages = normalize_page(page_for([item]), "test-account")
        report = validate_page(
            messages,
            "channel-public-001",
            frozenset(),
        )
        self.assertEqual(report.state, "unresolved_relation")
        self.assertTrue(report.checkpoint_safe)
        self.assertEqual(report.unresolved_ids, ("message-002",))


if __name__ == "__main__":
    unittest.main()
