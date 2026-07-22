from __future__ import annotations

import json
import unittest
from datetime import timedelta

from fixtures import (
    FixtureMessage,
    FixturePage,
    V11FixtureControlPlane,
    collect_window_pages,
    instant,
    instant_text,
)


class WindowedDiscordFlowTests(unittest.TestCase):
    def test_four_shanghai_windows_are_ordered_and_idempotent(self) -> None:
        control = V11FixtureControlPlane()
        control.configure_source(
            "source-a",
            worker_id="worker-a",
            coverage_through_at="2026-07-20T12:50:00Z",  # 20:50 Shanghai
        )

        first = control.schedule_due("worker-a", now="2026-07-21T12:50:00Z")
        duplicate = control.schedule_due("worker-a", now="2026-07-21T12:50:00Z")

        self.assertEqual([instant_text(task["end_at"]) for task in first], [
            "2026-07-20T16:00:00Z",  # Shanghai 00:00
            "2026-07-21T00:00:00Z",  # Shanghai 08:00
            "2026-07-21T08:00:00Z",  # Shanghai 16:00
            "2026-07-21T12:50:00Z",  # Shanghai 20:50
        ])
        self.assertEqual([task["id"] for task in duplicate], [task["id"] for task in first])
        self.assertTrue(all(task["idempotent"] for task in duplicate))
        self.assertTrue(all(task["collection_scope"] == {"mode": "window"} for task in first))

    def test_unbounded_incremental_pages_resume_without_duplicate_messages(self) -> None:
        start_at = instant("2026-07-21T15:20:00Z")
        end_at = instant("2026-07-21T17:01:00Z")
        pages = tuple(
            FixturePage(
                cursor=f"cursor-{index}",
                next_cursor=None if index == 100 else f"cursor-{index + 1}",
                messages=(FixtureMessage(
                    external_id=f"message-{index}",
                    occurred_at=end_at - timedelta(minutes=index + 1),
                    author_id="author-1",
                    content="public fixture message",
                ),),
            )
            for index in range(101)
        )
        pages = pages[:51] + (FixturePage(
            cursor="cursor-51",
            next_cursor="cursor-52",
            messages=(
                FixtureMessage("message-50", end_at - timedelta(minutes=51), "author-1", "overlapping prior page"),
                FixtureMessage("message-51", end_at - timedelta(minutes=52), "author-1", "public fixture message"),
            ),
        ),) + pages[52:]
        without_boundary = collect_window_pages(pages[:100], start_at=start_at, end_at=end_at)
        first = collect_window_pages(
            pages,
            start_at=start_at,
            end_at=end_at,
            interrupt_after_pages=51,
        )
        resumed = collect_window_pages(
            pages,
            start_at=start_at,
            end_at=end_at,
            resume_cursor=first.next_cursor,
            persisted_message_ids=first.message_ids,
        )

        self.assertFalse(without_boundary.complete)
        self.assertEqual(without_boundary.next_cursor, "cursor-100")
        self.assertFalse(first.complete)
        self.assertEqual(first.page_count, 51)
        self.assertTrue(resumed.complete)
        self.assertEqual(resumed.page_count, 50)
        all_message_ids = first.message_ids + resumed.message_ids
        self.assertEqual(len(all_message_ids), 100)  # page 101 proves the lower boundary; it is not in-range
        self.assertEqual(len(set(all_message_ids)), 100)
        self.assertNotIn("message-100", all_message_ids)

    def test_missed_windows_stay_ordered_and_one_source_failure_does_not_skip_another(self) -> None:
        control = V11FixtureControlPlane()
        for source_key in ("source-a", "source-b"):
            control.configure_source(
                source_key,
                worker_id="worker-a",
                coverage_through_at="2026-07-19T12:50:00Z",
            )

        tasks = control.schedule_due("worker-a", now="2026-07-20T12:50:00Z")
        source_a = [task for task in tasks if task["source_key"] == "source-a"]
        source_b = [task for task in tasks if task["source_key"] == "source-b"]
        control.mark_failed(source_a[0]["id"])
        for task in source_b:
            control.complete(task["id"])

        self.assertEqual(len(source_a), 4)
        self.assertEqual([task["end_at"] for task in source_a], sorted(task["end_at"] for task in source_a))
        self.assertEqual(control.tasks[source_a[0]["id"]]["status"], "retryable_failed")
        self.assertEqual(instant_text(control.sources["source-a"]["coverage_through_at"]), "2026-07-19T12:50:00Z")
        self.assertEqual(instant_text(control.sources["source-b"]["coverage_through_at"]), "2026-07-20T12:50:00Z")

    def test_delayed_collection_respects_end_boundary_and_manual_refresh_deduplicates(self) -> None:
        control = V11FixtureControlPlane()
        control.configure_source(
            "source-a",
            worker_id="worker-a",
            coverage_through_at="2026-07-21T15:20:00Z",
            author_profiles=({"author_id": "author-1", "author_display": "公开作者"},),
        )
        task = control.manual_refresh("source-a", actor_id="admin-1", now="2026-07-21T17:01:00Z")
        duplicate = control.manual_refresh("source-a", actor_id="admin-1", now="2026-07-21T17:02:00Z")
        self.assertEqual(task["id"], duplicate["id"])
        self.assertTrue(duplicate["idempotent"])
        self.assertEqual(instant_text(duplicate["end_at"]), "2026-07-21T17:01:00Z")

        page = FixturePage(
            cursor="cursor-1",
            next_cursor=None,
            messages=(
                FixtureMessage("late", instant("2026-07-21T17:02:00Z"), "author-1", "must not enter"),
                FixtureMessage("at-end", instant("2026-07-21T17:01:00Z"), "author-1", "included"),
                FixtureMessage("inside", instant("2026-07-21T16:59:00Z"), "author-1", "included"),
                FixtureMessage("at-start", instant("2026-07-21T15:20:00Z"), "author-1", "must not enter"),
            ),
        )
        captured = collect_window_pages(
            (page,),
            start_at=task["start_at"],
            end_at=task["end_at"],
        )
        control.complete(task["id"])

        self.assertEqual(captured.message_ids, ("at-end", "inside"))
        self.assertEqual(instant_text(control.sources["source-a"]["coverage_through_at"]), "2026-07-21T17:01:00Z")
        self.assertEqual(len(control.reader_as_user("user-1")), 1)

    def test_reader_has_configured_author_cards_topics_media_warning_and_no_raw_debug(self) -> None:
        control = V11FixtureControlPlane()
        control.configure_source(
            "source-a",
            worker_id="worker-a",
            coverage_through_at="2026-07-21T15:20:00Z",
            author_profiles=(
                {"author_id": "private-author-a", "author_display": "作者甲"},
                {"author_id": "private-author-b", "author_display": "作者乙"},
            ),
        )
        task = control.manual_refresh("source-a", actor_id="admin-1", now="2026-07-21T17:01:00Z")
        control.complete(task["id"])
        reader_day = control.reader_as_user("user-1")[0]
        presentation = reader_day["dailySummary"]["presentation"]
        serialized = json.dumps(reader_day, ensure_ascii=False)

        self.assertEqual([card["authorName"] for card in presentation["authorCards"]], ["作者甲", "作者乙"])
        self.assertTrue(all(set(card) == {"authorName", "coreLogic", "operationTendency", "strategy", "uncertainty"} for card in presentation["authorCards"]))
        self.assertEqual(len(presentation["topicDiscussions"][0]["viewpoints"]), 2)
        self.assertIn("未解析媒体", presentation["warnings"][0])
        # This public projection is the compact contract used for the 375px handheld reader review.
        for forbidden in ("private-author", "external_message_id", "local_raw_ref", "raw_messages", "canonical_messages", "worker", "prompt", "cursor", "content", "Evidence-backed messages", "证据消息"):
            self.assertNotIn(forbidden, serialized)
        with self.assertRaises(PermissionError):
            control.manual_refresh("source-a", actor_id="user-1", now="2026-07-21T17:02:00Z")


if __name__ == "__main__":
    unittest.main()
