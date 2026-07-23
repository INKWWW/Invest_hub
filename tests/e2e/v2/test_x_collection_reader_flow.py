from __future__ import annotations

import json
import unittest
from datetime import timedelta

from fixtures import V2FixtureControl, XPost, collect_pages, cutoffs_after, instant, text


class XCollectionReaderFlowTests(unittest.TestCase):
    def test_five_cutoffs_and_more_than_five_pages_are_bounded_by_time_not_page_count(self) -> None:
        start, now = instant("2026-07-22T16:00:00Z"), instant("2026-07-23T12:00:00Z")
        self.assertEqual([text(value) for value in cutoffs_after(start, now)], ["2026-07-23T00:00:00Z", "2026-07-23T04:00:00Z", "2026-07-23T08:00:00Z", "2026-07-23T12:00:00Z"])
        end = instant("2026-07-23T08:00:00Z")
        pages = tuple((XPost(f"p-{index}", end - timedelta(minutes=index + 1), "original"),) for index in range(7)) + ((XPost("old", start - timedelta(minutes=31), "original"),),)
        complete, ids = collect_pages(pages, start_at=start, end_at=end)
        self.assertTrue(complete); self.assertEqual(len(ids), 7)

    def test_safe_reader_keeps_segments_append_only_and_excludes_raw_body(self) -> None:
        control = V2FixtureControl(); control.configure("x-a", "2026-07-23T00:00:00+08:00")
        first, second, *_ = control.schedule("x-a", "2026-07-23T16:00:00+08:00")
        control.complete(first["id"], post_ids=("original", "quote", "reply", "repost"), viewpoints=("首段观点",), natural_date="2026-07-23")
        control.complete(second["id"], post_ids=("later",), viewpoints=("后续变化",), natural_date="2026-07-23")
        reader = control.reader("x-a", "2026-07-23", "reader")
        self.assertEqual(reader["currentDailyTimeline"]["windowSegments"][0]["viewpoints"], ("首段观点",))
        self.assertEqual(len(reader["currentDailyTimeline"]["windowSegments"]), 2)
        serialized = json.dumps(reader)
        for forbidden in ("content", "local_raw_ref", "worker", "prompt", "provider", "canonical"):
            self.assertNotIn(forbidden, serialized)
        with self.assertRaises(PermissionError): control.reader("x-a", "2026-07-23", "ordinary")
