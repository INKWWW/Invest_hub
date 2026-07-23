from __future__ import annotations

import json
import unittest

from invest_hub_worker.structured import SchemaError, parse_v2_x_chunk_output, parse_v2_x_window_output


class XStructuredOutputTests(unittest.TestCase):
    def test_chunk_keeps_quote_viewpoint_separate_and_confines_evidence_to_one_post(self) -> None:
        output = parse_v2_x_chunk_output(json.dumps({
            "schema_version": "v2-x-chunk",
            "analyses": [{
                "post_id": "post-1", "blogger_viewpoint": "作者补充看法", "arguments": ["可见论据"],
                "quoted_post_viewpoint": "被引用帖观点", "uncertainties": [],
                "evidence_post_ids": ["post-1", "quoted-1"], "post_link": "https://x.com/a/status/1",
            }],
        }), {"post-1"}, {"quoted-1"})
        self.assertEqual(output["analyses"][0]["quoted_post_viewpoint"], "被引用帖观点")

    def test_chunk_rejects_unknown_or_cross_post_evidence_and_missing_analysis(self) -> None:
        base = {
            "schema_version": "v2-x-chunk",
            "analyses": [{"post_id": "post-1", "blogger_viewpoint": "观点", "arguments": [], "quoted_post_viewpoint": None, "uncertainties": [], "evidence_post_ids": ["post-2"], "post_link": "https://x.com/a/status/1"}],
        }
        with self.assertRaisesRegex(SchemaError, "evidence"):
            parse_v2_x_chunk_output(json.dumps(base), {"post-1"}, set())
        with self.assertRaisesRegex(SchemaError, "exactly one"):
            parse_v2_x_chunk_output(json.dumps({"schema_version": "v2-x-chunk", "analyses": []}), {"post-1"}, set())

    def test_chunk_does_not_allow_another_post_bundle_context(self) -> None:
        payload = {
            "schema_version": "v2-x-chunk",
            "analyses": [
                {"post_id": "post-1", "blogger_viewpoint": "观点一", "arguments": [], "quoted_post_viewpoint": None, "uncertainties": [], "evidence_post_ids": ["post-1", "quote-2"], "post_link": "https://x.com/a/status/1"},
                {"post_id": "post-2", "blogger_viewpoint": "观点二", "arguments": [], "quoted_post_viewpoint": None, "uncertainties": [], "evidence_post_ids": ["post-2", "quote-2"], "post_link": "https://x.com/a/status/2"},
            ],
        }
        with self.assertRaisesRegex(SchemaError, "evidence"):
            parse_v2_x_chunk_output(json.dumps(payload), {"post-1", "post-2"}, {
                "post-1": {"quote-1"},
                "post-2": {"quote-2"},
            })

    def test_window_accepts_only_persisted_analysis_ids(self) -> None:
        output = parse_v2_x_window_output(json.dumps({
            "schema_version": "v2-x-window", "natural_date": "2026-07-23", "range_task_id": "task-1",
            "occurred_from_at": "2026-07-23T00:00:00Z", "occurred_through_at": "2026-07-23T08:00:00Z",
            "window_viewpoints": ["窗口观点"], "analysis_ids": ["analysis-1"], "evidence_post_ids": ["post-1"], "uncertainties": [],
        }), {"analysis-1"})
        self.assertEqual(output["natural_date"], "2026-07-23")
        invalid = {**output, "analysis_ids": ["unknown"]}
        with self.assertRaisesRegex(SchemaError, "analysis"):
            parse_v2_x_window_output(json.dumps(invalid), {"analysis-1"})
