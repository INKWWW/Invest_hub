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

    def test_v4_upstream_prompts_publish_scope_status_and_no_placeholder_scope(self) -> None:
        post = (PROMPT_ROOT / "v4_x_post_analysis.md").read_text(encoding="utf-8")
        window = (PROMPT_ROOT / "v4_x_window.md").read_text(encoding="utf-8")
        daily = (PROMPT_ROOT / "v4_x_cross_blogger.md").read_text(encoding="utf-8")

        for prompt, version in ((post, "v4-x-post-analysis"), (window, "v4-x-window"), (daily, "v4-x-cross-blogger")):
            self.assertIn(f'"schema_version": "{version}"', prompt)
            self.assertIn("action_scope_status", prompt)
            self.assertIn("unspecified", prompt)
            self.assertIn("绝不能", prompt)

    def test_v4_cross_blogger_prompt_requires_neutral_action_wording(self) -> None:
        daily = (PROMPT_ROOT / "v4_x_cross_blogger.md").read_text(encoding="utf-8")

        for forbidden_wording in ("建议买入", "应该卖出", "必须加仓", "立即减仓"):
            self.assertIn(forbidden_wording, daily)
        self.assertIn("操作倾向为", daily)
        self.assertIn("不得原样复制", daily)

    def test_v5_cross_blogger_prompt_publishes_the_production_contract(self) -> None:
        daily = (PROMPT_ROOT / "v5_x_cross_blogger.md").read_text(encoding="utf-8")
        for phrase in (
            '"schema_version": "v5-x-cross-blogger"', "complete thesis",
            "scenario_branches", "attributed_actions", "cross_blogger_integrations",
            "ai_assessments", "不获取外部信息", "不构成交易建议", "单博主",
            "至少两位独立博主", "覆盖限制", "只输出一个合法 JSON 对象",
        ):
            self.assertIn(phrase, daily)
        self.assertNotIn('"none"', daily)
        self.assertNotIn("not_applicable", daily)
        self.assertIn("未明确标的", daily)

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
