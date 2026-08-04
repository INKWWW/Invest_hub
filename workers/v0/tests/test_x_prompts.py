from __future__ import annotations

import unittest
from pathlib import Path


PROMPT_ROOT = Path(__file__).resolve().parents[1] / "prompts"


class XPromptContractTests(unittest.TestCase):
    def test_v3_upstream_prompts_publish_versions_and_boundaries(self) -> None:
        post = (PROMPT_ROOT / "v3_x_post_analysis.md").read_text(encoding="utf-8")
        window = (PROMPT_ROOT / "v3_x_window.md").read_text(encoding="utf-8")
        daily = (PROMPT_ROOT / "v3_x_cross_blogger.md").read_text(encoding="utf-8")

        for field in (
            '"schema_version": "v3-x-post-analysis"', "investment_relevance",
            "investment_categories", "action_intent", "action_scope", "conditions",
        ):
            self.assertIn(field, post)
        for field in (
            '"schema_version": "v3-x-window"', "security_industry_viewpoints",
            "market_structure_viewpoints", "strategy_mindset_viewpoints", "analysis_ids",
        ):
            self.assertIn(field, window)
        self.assertIn("完整 v3 单帖分析", daily)

    def test_chunk_prompt_names_every_required_analysis_field(self) -> None:
        prompt = (PROMPT_ROOT / "v2_x_chunk.md").read_text(encoding="utf-8")

        for field in (
            "schema_version", "analyses", "post_id", "blogger_viewpoint", "arguments",
            "quoted_post_viewpoint", "uncertainties", "evidence_post_ids", "post_link",
        ):
            self.assertIn(field, prompt)

    def test_window_prompt_names_every_required_segment_field(self) -> None:
        prompt = (PROMPT_ROOT / "v2_x_window.md").read_text(encoding="utf-8")

        for field in (
            "schema_version", "natural_date", "range_task_id", "occurred_from_at",
            "occurred_through_at", "window_viewpoints", "analysis_ids", "evidence_post_ids",
            "uncertainties",
        ):
            self.assertIn(field, prompt)


if __name__ == "__main__":
    unittest.main()
