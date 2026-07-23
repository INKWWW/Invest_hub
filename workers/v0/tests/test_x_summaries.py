from __future__ import annotations

import unittest

from invest_hub_worker.summaries import build_v2_x_daily_viewpoint_timeline


class XSummaryTests(unittest.TestCase):
    def test_daily_timeline_appends_new_segments_without_rewriting_prior_text(self) -> None:
        prior = [{"id": "segment-1", "occurred_from_at": "2026-07-23T01:00:00Z", "window_viewpoints": ["旧观点"]}]
        current = {"id": "segment-2", "occurred_from_at": "2026-07-23T04:00:00Z", "window_viewpoints": ["新观点"]}
        timeline = build_v2_x_daily_viewpoint_timeline(prior, current)
        self.assertEqual([item["id"] for item in timeline], ["segment-1", "segment-2"])
        self.assertEqual(timeline[0]["window_viewpoints"], ["旧观点"])
