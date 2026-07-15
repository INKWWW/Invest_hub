import tempfile
import unittest
from pathlib import Path

from spike_01.checkpoint import JsonCheckpointStore
from spike_01.evidence import LocalEvidenceStore
from spike_01.model import (
    CanonicalMessage,
    Checkpoint,
    RawMessage,
    RawPage,
    ValidationReport,
)


class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.raw_page = RawPage(
            page_id="page-001",
            source_container_id="channel-a",
            cursor_before=None,
            cursor_after="cursor-001",
            messages=(RawMessage(0, {"id": "message-001"}),),
            raw_payload_ref="fixture://page-001",
        )
        self.message = CanonicalMessage(
            source_type="discord",
            source_account_id="account-a",
            source_container_id="channel-a",
            external_item_id="message-001",
            author_id="author-001",
            author_name="Analyst A",
            published_at="2026-01-01T08:00:00Z",
            content_text="fixture",
            content_type="text",
            parent_item_id=None,
            quoted_item=None,
            attachments=(),
            source_url="https://discord.example/message-001",
            raw_payload_ref="fixture://page-001",
            collected_at="2026-01-01T08:01:00Z",
        )
        self.report = ValidationReport(
            state="accepted",
            issues=(),
            accepted_ids=("message-001",),
            duplicate_ids=(),
            unresolved_ids=(),
            checkpoint_safe=True,
        )

    def test_checkpoint_initially_empty_and_round_trips(self):
        with tempfile.TemporaryDirectory() as directory:
            store = JsonCheckpointStore(Path(directory))
            self.assertIsNone(store.load("channel-a"))
            checkpoint = Checkpoint("channel-a", "cursor-001", "message-001")
            store.commit(checkpoint)
            self.assertEqual(store.load("channel-a"), checkpoint)

    def test_uncommitted_checkpoint_does_not_change_existing_value(self):
        with tempfile.TemporaryDirectory() as directory:
            store = JsonCheckpointStore(Path(directory))
            first = Checkpoint("channel-a", "cursor-001", "message-001")
            store.commit(first)
            second = Checkpoint("channel-a", "cursor-002", "message-002")
            self.assertEqual(store.load("channel-a"), first)
            self.assertNotEqual(store.load("channel-a"), second)

    def test_evidence_store_persists_raw_canonical_and_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            store = LocalEvidenceStore(Path(directory))
            store.persist_raw(self.raw_page)
            store.persist_canonical((self.message,))
            store.persist_validation(self.report)
            self.assertTrue(store.has_message("message-001"))
            self.assertEqual(store.message_count(), 1)
            self.assertTrue((Path(directory) / "raw" / "page-001.json").exists())
            self.assertTrue(
                (Path(directory) / "canonical" / "messages.jsonl").exists()
            )
            self.assertTrue(
                (Path(directory) / "validation" / "reports.jsonl").exists()
            )


if __name__ == "__main__":
    unittest.main()
