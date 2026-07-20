from __future__ import annotations

import unittest

from invest_hub_worker.canonical import CanonicalMessage
from invest_hub_worker.summaries import SummaryError, build_batch_summaries


def message(message_id: str, occurred_at: str, *, media: bool = False) -> CanonicalMessage:
    return CanonicalMessage(
        source_id="source-1",
        external_message_id=message_id,
        author_id="author-1",
        author_name="Author",
        occurred_at=occurred_at,
        content="fixture",
        reply_to_message_id=None,
        quote=None,
        attachments=({"name": "unparsed.pdf"},) if media else (),
    )


class SummaryTests(unittest.TestCase):
    def test_groups_same_day_chunks_and_preserves_target_topic_channel_scope_and_media_warning(self) -> None:
        summaries = build_batch_summaries(
            [message("message-1", "2099-01-01T00:00:00Z", media=True), message("message-2", "2099-01-01T01:00:00Z")],
            [
                {
                    "chunk_key": "chunk-1",
                    "input_message_ids": ["message-1"],
                    "output": {"topics": [{"author_scope": "target"}], "warnings": ["附件未解析"]},
                },
                {
                    "chunk_key": "chunk-2",
                    "input_message_ids": ["message-2"],
                    "output": {"topics": [{"author_scope": "channel"}], "warnings": []},
                },
            ],
        )

        self.assertEqual(len(summaries), 1)
        self.assertEqual(summaries[0]["natural_date"], "2099-01-01")
        self.assertEqual(summaries[0]["structured_run_keys"], ["chunk-1", "chunk-2"])
        self.assertEqual([topic["author_scope"] for topic in summaries[0]["output"]["topics"]], ["target", "channel"])
        self.assertEqual(summaries[0]["coverage"]["unparsed_media_message_ids"], ["message-1"])

    def test_splits_cross_day_messages_and_reuses_the_backing_chunk_key(self) -> None:
        summaries = build_batch_summaries(
            [message("message-1", "2099-01-01T23:59:00Z"), message("message-2", "2099-01-02T00:01:00Z")],
            [{
                "chunk_key": "chunk-cross-day",
                "input_message_ids": ["message-1", "message-2"],
                "output": {"topics": [], "warnings": []},
            }],
        )

        self.assertEqual([summary["natural_date"] for summary in summaries], ["2099-01-01", "2099-01-02"])
        self.assertEqual([summary["structured_run_keys"] for summary in summaries], [["chunk-cross-day"], ["chunk-cross-day"]])

    def test_rejects_duplicate_or_uncovered_messages_and_an_empty_effective_input(self) -> None:
        with self.assertRaises(SummaryError):
            build_batch_summaries(
                [message("message-1", "2099-01-01T00:00:00Z"), message("message-1", "2099-01-01T00:00:00Z")],
                [{"chunk_key": "chunk-1", "input_message_ids": ["message-1"], "output": {"topics": [], "warnings": []}}],
            )
        with self.assertRaises(SummaryError):
            build_batch_summaries(
                [message("message-1", "2099-01-01T00:00:00Z")],
                [{"chunk_key": "chunk-1", "input_message_ids": [], "output": {"topics": [], "warnings": []}}],
            )
        with self.assertRaises(SummaryError):
            build_batch_summaries([], [])


if __name__ == "__main__":
    unittest.main()
