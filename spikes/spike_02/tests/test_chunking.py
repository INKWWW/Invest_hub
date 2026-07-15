import unittest
from pathlib import Path

from spike_02.chunking import build_chunks, split_chunk
from spike_02.fixtures import load_fixture
from spike_02.model import FixtureCase, FixtureMessage


class ChunkingTests(unittest.TestCase):
    def setUp(self):
        self.case = load_fixture(
            Path("spikes/spike_02/fixtures/public_small.json")
        )

    def test_chunks_preserve_primary_order_without_loss(self):
        chunks = build_chunks(self.case, max_primary_messages=3)
        primary_ids = tuple(
            message_id
            for chunk in chunks
            for message_id in chunk.primary_message_ids
        )
        self.assertEqual(
            primary_ids,
            tuple(message.message_id for message in self.case.messages),
        )

    def test_reply_parent_outside_chunk_is_context_only(self):
        case = FixtureCase(
            case_id="reply-chain",
            scale="small",
            messages=(
                FixtureMessage(
                    "public-001", "other-001", "other", "2026-01-01T00:00:00Z", "root", "text", None
                ),
                FixtureMessage(
                    "public-002", "other-002", "other", "2026-01-01T00:01:00Z", "middle", "text", None
                ),
                FixtureMessage(
                    "public-003", "other-003", "other", "2026-01-01T00:02:00Z", "reply", "text", "public-001"
                ),
                FixtureMessage(
                    "public-004", "other-004", "other", "2026-01-01T00:03:00Z", "tail", "text", None
                ),
            ),
            claims=(),
        )
        chunks = build_chunks(case, max_primary_messages=2)
        self.assertIn("public-001", chunks[1].context_message_ids)
        self.assertNotIn("public-001", chunks[1].primary_message_ids)

    def test_split_chunk_preserves_primary_ids(self):
        chunk = build_chunks(self.case, max_primary_messages=12)[0]
        left, right = split_chunk(chunk)
        self.assertEqual(
            left.primary_message_ids + right.primary_message_ids,
            chunk.primary_message_ids,
        )
        self.assertNotEqual(left.primary_message_ids, right.primary_message_ids)


if __name__ == "__main__":
    unittest.main()
