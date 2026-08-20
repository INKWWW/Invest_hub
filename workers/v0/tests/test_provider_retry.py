from __future__ import annotations

import json
import unittest

from invest_hub_worker.providers.base import ProviderContext
from invest_hub_worker.providers.codex_cli import CodexCLIProvider
from invest_hub_worker.providers.mock import MockOutcome, MockProvider
from invest_hub_worker.retry import RetryPolicy


def valid_output() -> dict[str, object]:
    return {"topics": [], "media_unparsed": False, "media_source_message_ids": [], "warnings": []}


class ProviderRetryTests(unittest.TestCase):
    def test_context_limits_provider_to_approved_structuring_operations(self) -> None:
        context = ProviderContext(
            chunk_id="chunk-1",
            prompt_version="v1.1",
            prompt_text="private prompt",
            operation="v1_1_chunk",
            input_message_authors=(("message-1", "author-1", "Author One"),),
            configured_author_profiles=(("author-1", "Author One"),),
        )
        self.assertEqual(context.operation, "v1_1_chunk")
        self.assertEqual(ProviderContext(chunk_id="x-1", prompt_version="v2", prompt_text="private", operation="v2_x_chunk").operation, "v2_x_chunk")
        self.assertEqual(ProviderContext(chunk_id="x-v5", prompt_version="v5-x-cross-blogger-1", prompt_text="private", operation="v5_x_cross_blogger").operation, "v5_x_cross_blogger")
        with self.assertRaises(ValueError):
            ProviderContext(chunk_id="chunk-1", prompt_version="v1.1", prompt_text="private prompt", operation="arbitrary")

    def test_codex_provider_parses_the_v5_cross_blogger_contract(self) -> None:
        output = {
            "schema_version": "v5-x-cross-blogger",
            "ai_synthesis": {"cross_blogger_integrations": [], "ai_assessments": []},
            "security_industry_theses": [{
                "thesis_id": "security-01", "headline": "当前产业判断仍需观察。",
                "synthesis": "该判断来自输入窗口。", "scenario_branches": [], "attributed_actions": [],
                "supporting_source_ids": ["source-a"], "dissenting_source_ids": [],
                "analysis_ids": ["post-a@2"], "evidence_post_ids": ["post-a"], "uncertainties": [],
            }],
            "market_structure_theses": [], "strategy_mindset_theses": [], "uncertainties": [],
        }
        context = ProviderContext(
            chunk_id="judgement-run-1", prompt_version="v5-x-cross-blogger-1", prompt_text="private",
            operation="v5_x_cross_blogger", allowed_source_ids=frozenset({"source-a"}),
            allowed_analysis_ids=frozenset({"post-a@2"}), allowed_post_ids=frozenset({"post-a"}),
            allowed_analysis_source_ids=(("post-a@2", "source-a"),),
            allowed_analysis_evidence_post_ids=(("post-a@2", ("post-a",)),),
            frozen_source_ids=frozenset({"source-a"}), opaque_context_ids=(("batch", ("batch-1",)),),
        )
        parsed = CodexCLIProvider._parse_for_context(json.dumps(output, ensure_ascii=False), ({"source_id": "source-a"},), context)
        self.assertEqual(parsed["schema_version"], "v5-x-cross-blogger")

    def test_mock_provider_success_returns_structured_output_without_prompt(self) -> None:
        provider = MockProvider({"chunk-1": [MockOutcome.success(valid_output())]})
        response = RetryPolicy().execute(
            provider,
            ("message-1",),
            ProviderContext(chunk_id="chunk-1", prompt_version="v0", prompt_text="private prompt"),
        )
        self.assertEqual(response.status, "success")
        self.assertEqual(response.parsed_output, valid_output())
        self.assertNotIn("prompt", response.__dict__)
        self.assertNotIn("private prompt", repr(response))
        self.assertEqual(provider.calls_for("chunk-1"), 1)

    def test_timeout_then_success_retries_only_the_same_chunk(self) -> None:
        provider = MockProvider({"chunk-1": [MockOutcome.timeout(), MockOutcome.success(valid_output())]})
        response = RetryPolicy(max_attempts=3).execute(
            provider,
            ("message-1",),
            ProviderContext(chunk_id="chunk-1", prompt_version="v0", prompt_text="private prompt"),
        )
        self.assertEqual(response.status, "success")
        self.assertEqual(response.attempt, 2)
        self.assertEqual(provider.calls_for("chunk-1"), 2)

    def test_three_failures_stop_at_max_attempts(self) -> None:
        provider = MockProvider({"chunk-1": [MockOutcome.provider_failure(), MockOutcome.invalid_json(), MockOutcome.timeout()]})
        response = RetryPolicy(max_attempts=3).execute(
            provider,
            ("message-1",),
            ProviderContext(chunk_id="chunk-1", prompt_version="v0", prompt_text="private prompt"),
        )
        self.assertEqual(response.status, "timeout")
        self.assertEqual(response.attempt, 3)
        self.assertEqual(provider.calls_for("chunk-1"), 3)


if __name__ == "__main__":
    unittest.main()
