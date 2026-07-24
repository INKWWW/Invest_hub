from __future__ import annotations

import unittest
from pathlib import Path


PROMPT_ROOT = Path(__file__).resolve().parents[1] / "prompts"


class XPromptContractTests(unittest.TestCase):
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
