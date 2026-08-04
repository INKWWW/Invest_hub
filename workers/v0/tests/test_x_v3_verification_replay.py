from __future__ import annotations

import unittest

from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
import invest_hub_worker.runtime as runtime


def frozen_context() -> dict[str, object]:
    return {
        "replay_id": "replay-1", "attempt": 1,
        "sources": [
            {"source_id": "source-a", "display_name": "A", "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z", "posts": [{
                "post_id": "post-a", "content": "公开 fixture 内容 A", "occurred_at": "2099-01-01T01:00:00Z", "post_url": "https://x.com/a/status/post-a", "post_type": "original",
                "quoted_post_id": None, "reply_to_post_id": None, "reposted_post_id": None, "context_status": "complete", "attachments": [],
            }]},
            {"source_id": "source-b", "display_name": "B", "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z", "posts": [{
                "post_id": "post-b", "content": "公开 fixture 内容 B", "occurred_at": "2099-01-01T02:00:00Z", "post_url": "https://x.com/b/status/post-b", "post_type": "original",
                "quoted_post_id": None, "reply_to_post_id": None, "reposted_post_id": None, "context_status": "complete", "attachments": [],
            }]},
        ],
    }


class RecordingProvider:
    def __init__(self) -> None:
        self.operations: list[str] = []

    def complete(self, _input: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
        self.operations.append(context.operation)
        if context.operation == "v3_x_post_analysis":
            post_id = next(iter(context.input_message_ids))
            output = {"schema_version": "v3-x-post-analysis", "analyses": [{
                "post_id": post_id, "investment_relevance": "investment_related", "investment_categories": ["security_industry"],
                "blogger_viewpoint": "公开观点", "action_intent": "watch", "action_scope": "公开 fixture 标的", "conditions": [], "arguments": [],
                "quoted_post_viewpoint": None, "uncertainties": [], "evidence_post_ids": [post_id], "post_link": f"https://x.com/fixture/status/{post_id}",
            }]}
        elif context.operation == "v3_x_window":
            analysis_ids = sorted(context.input_message_ids)
            evidence = sorted({post for _analysis, posts in context.allowed_analysis_evidence_post_ids for post in posts})
            output = {"schema_version": "v3-x-window", "natural_date": "2099-01-01", "range_task_id": "replay-1", "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z", "security_industry_viewpoints": [], "market_structure_viewpoints": [], "strategy_mindset_viewpoints": [], "analysis_ids": analysis_ids, "evidence_post_ids": evidence, "uncertainties": []}
        elif context.operation == "v3_x_cross_blogger":
            analysis_ids = sorted(context.allowed_analysis_ids)
            evidence = sorted(context.allowed_post_ids)
            output = {"schema_version": "v3-x-cross-blogger", "security_industry_viewpoints": [{
                "statement": "两个公开来源均提示继续观察。", "action_intent": "watch", "action_scope": "公开 fixture 标的", "conditions": [],
                "supporting_source_ids": ["source-a", "source-b"], "dissenting_source_ids": [], "analysis_ids": analysis_ids, "evidence_post_ids": evidence, "uncertainties": [],
            }], "market_structure_viewpoints": [], "strategy_mindset_viewpoints": [], "uncertainties": []}
        else:
            raise AssertionError(f"unexpected operation {context.operation}")
        return ProviderResponse(status="success", provider="codex_cli", model_reported="fixture-model", prompt_version=context.prompt_version, elapsed_ms=1, attempt=context.attempt, raw_ref=None, parsed_output_ref=None, parsed_output=output)


class XVerificationReplayRuntimeTests(unittest.TestCase):
    def test_replay_runs_only_the_frozen_v3_chain_in_order(self) -> None:
        runtime_type = getattr(runtime, "XVerificationReplayRuntime", None)
        self.assertIsNotNone(runtime_type, "verification replay runtime must be public")
        provider = RecordingProvider()

        completion = runtime_type(provider=provider, prompt_template="private supplement").execute(  # type: ignore[misc]
            {"replay_id": "replay-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z"}, frozen_context(),
        )

        self.assertEqual(provider.operations, ["v3_x_post_analysis", "v3_x_post_analysis", "v3_x_window", "v3_x_window", "v3_x_cross_blogger"])
        self.assertEqual(completion["replay_id"], "replay-1")
        self.assertEqual([source["source_id"] for source in completion["sources"]], ["source-a", "source-b"])
        self.assertEqual(completion["daily"]["schema_version"], "v3-x-cross-blogger")

    def test_schema_error_does_not_attempt_daily_judgement(self) -> None:
        class InvalidPostProvider(RecordingProvider):
            def complete(self, input_chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
                if context.operation == "v3_x_post_analysis":
                    self.operations.append(context.operation)
                    return ProviderResponse(status="success", provider="codex_cli", model_reported=None, prompt_version=context.prompt_version, elapsed_ms=1, attempt=1, raw_ref=None, parsed_output_ref=None, parsed_output={"schema_version": "wrong", "analyses": []})
                return super().complete(input_chunk, context)

        runtime_type = getattr(runtime, "XVerificationReplayRuntime", None)
        provider = InvalidPostProvider()
        with self.assertRaisesRegex(runtime.RuntimeExecutionError, "post analysis"):
            runtime_type(provider=provider, prompt_template="private supplement").execute(  # type: ignore[misc]
                {"replay_id": "replay-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z"}, frozen_context(),
            )
        self.assertEqual(provider.operations, ["v3_x_post_analysis"])
