from __future__ import annotations

import json
import unittest

from invest_hub_worker import structured
from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
from invest_hub_worker import runtime
from invest_hub_worker.worker import Worker


def valid_output() -> dict[str, object]:
    return {
        "schema_version": "v2-x-cross-blogger",
        "stock_viewpoints": [{
            "statement": "部分博主认为估值仍需观察，另一位博主持保留意见。",
            "supporting_source_ids": ["source-a", "source-b"],
            "dissenting_source_ids": ["source-c"],
            "analysis_ids": ["post-a@1", "post-b@1", "post-c@1"],
            "evidence_post_ids": ["post-a", "post-b", "post-c"],
            "uncertainties": ["仅覆盖当前日内新增观点"],
        }],
        "market_industry_viewpoints": [],
        "uncertainties": ["一位未纳入比较的博主本窗口没有新增信息"],
    }


class XCrossBloggerJudgementSchemaTests(unittest.TestCase):
    def parse(self, output: dict[str, object]) -> dict[str, object]:
        parser = getattr(structured, "parse_v2_x_cross_blogger_output", None)
        self.assertIsNotNone(parser, "cross-blogger parser must be public")
        return parser(  # type: ignore[misc,no-any-return]
            json.dumps(output, ensure_ascii=False),
            allowed_source_ids={"source-a", "source-b", "source-c"},
            allowed_analysis_ids={"post-a@1", "post-b@1", "post-c@1"},
            allowed_post_ids={"post-a", "post-b", "post-c"},
            analysis_source_ids={"post-a@1": "source-a", "post-b@1": "source-b", "post-c@1": "source-c"},
            analysis_evidence_post_ids={"post-a@1": {"post-a"}, "post-b@1": {"post-b"}, "post-c@1": {"post-c"}},
            frozen_source_ids={"source-a", "source-b", "source-c", "source-d"},
        )

    def test_accepts_agreement_disagreement_and_omitted_no_new_information_source(self) -> None:
        parsed = self.parse(valid_output())

        item = parsed["stock_viewpoints"][0]
        self.assertEqual(item["supporting_source_ids"], ["source-a", "source-b"])
        self.assertEqual(item["dissenting_source_ids"], ["source-c"])
        self.assertEqual(parsed["uncertainties"], ["一位未纳入比较的博主本窗口没有新增信息"])

    def test_rejects_unknown_source_and_excluded_source(self) -> None:
        unknown = valid_output()
        unknown["stock_viewpoints"][0]["supporting_source_ids"] = ["source-a", "source-other"]
        with self.assertRaisesRegex(structured.SchemaError, "unknown source"):
            self.parse(unknown)

        excluded = valid_output()
        excluded["stock_viewpoints"][0]["supporting_source_ids"] = ["source-a", "source-d"]
        with self.assertRaisesRegex(structured.SchemaError, "unknown source"):
            self.parse(excluded)

    def test_rejects_unpersisted_or_duplicate_evidence_references(self) -> None:
        unknown_analysis = valid_output()
        unknown_analysis["stock_viewpoints"][0]["analysis_ids"] = ["post-a@1", "unknown@1"]
        with self.assertRaisesRegex(structured.SchemaError, "unknown analysis"):
            self.parse(unknown_analysis)

        unknown_post = valid_output()
        unknown_post["stock_viewpoints"][0]["evidence_post_ids"] = ["post-a", "unknown-post"]
        with self.assertRaisesRegex(structured.SchemaError, "unknown evidence post"):
            self.parse(unknown_post)

        duplicate = valid_output()
        duplicate["stock_viewpoints"][0]["evidence_post_ids"] = ["post-a", "post-a"]
        with self.assertRaisesRegex(structured.SchemaError, "duplicate evidence"):
            self.parse(duplicate)

    def test_rejects_cross_source_analysis_and_evidence_splicing(self) -> None:
        spliced = valid_output()
        spliced["stock_viewpoints"][0]["supporting_source_ids"] = ["source-a"]
        spliced["stock_viewpoints"][0]["dissenting_source_ids"] = []
        spliced["stock_viewpoints"][0]["analysis_ids"] = ["post-c@1"]
        spliced["stock_viewpoints"][0]["evidence_post_ids"] = ["post-c"]

        with self.assertRaisesRegex(structured.SchemaError, "source ownership"):
            self.parse(spliced)

    def test_requires_the_exact_evidence_union_for_referenced_analyses(self) -> None:
        incomplete = valid_output()
        incomplete["stock_viewpoints"][0]["evidence_post_ids"] = ["post-a", "post-b"]

        with self.assertRaisesRegex(structured.SchemaError, "exactly match"):
            self.parse(incomplete)

    def test_rejects_opaque_analysis_ids_in_natural_language_fields(self) -> None:
        statement = valid_output()
        statement["stock_viewpoints"][0]["statement"] = "post-a@1 表示估值仍需观察。"
        with self.assertRaisesRegex(structured.SchemaError, "opaque analysis ID"):
            self.parse(statement)

        item_uncertainty = valid_output()
        item_uncertainty["stock_viewpoints"][0]["uncertainties"] = ["post-b@1 的上下文不足"]
        with self.assertRaisesRegex(structured.SchemaError, "opaque analysis ID"):
            self.parse(item_uncertainty)

        global_uncertainty = valid_output()
        global_uncertainty["uncertainties"] = ["post-c@1 的上下文不足"]
        with self.assertRaisesRegex(structured.SchemaError, "opaque analysis ID"):
            self.parse(global_uncertainty)

    def test_rejects_opaque_source_and_evidence_ids_in_natural_language_fields(self) -> None:
        source_token = valid_output()
        source_token["stock_viewpoints"][0]["statement"] = "source-a 表示估值仍需观察。"
        with self.assertRaisesRegex(structured.SchemaError, "opaque source ID"):
            self.parse(source_token)

        excluded_source_token = valid_output()
        excluded_source_token["uncertainties"] = ["source-d 本窗口没有新增信息"]
        with self.assertRaisesRegex(structured.SchemaError, "opaque source ID"):
            self.parse(excluded_source_token)

        item_evidence_token = valid_output()
        item_evidence_token["stock_viewpoints"][0]["uncertainties"] = ["post-b 的上下文不足"]
        with self.assertRaisesRegex(structured.SchemaError, "opaque evidence ID"):
            self.parse(item_evidence_token)

        global_evidence_token = valid_output()
        global_evidence_token["uncertainties"] = ["post-c 的上下文不足"]
        with self.assertRaisesRegex(structured.SchemaError, "opaque evidence ID"):
            self.parse(global_evidence_token)

        source_case_variant = valid_output()
        source_case_variant["stock_viewpoints"][0]["statement"] = "SOURCE-A 表示估值仍需观察。"
        with self.assertRaisesRegex(structured.SchemaError, "opaque source ID"):
            self.parse(source_case_variant)

        analysis_case_variant = valid_output()
        analysis_case_variant["uncertainties"] = ["POST-A@1 的上下文不足"]
        with self.assertRaisesRegex(structured.SchemaError, "opaque analysis ID"):
            self.parse(analysis_case_variant)

        evidence_case_variant = valid_output()
        evidence_case_variant["stock_viewpoints"][0]["uncertainties"] = ["POST-B 的上下文不足"]
        with self.assertRaisesRegex(structured.SchemaError, "opaque evidence ID"):
            self.parse(evidence_case_variant)

    def test_rejects_conflicting_sources_empty_evidence_and_imperative_recommendation(self) -> None:
        conflicting = valid_output()
        conflicting["stock_viewpoints"][0]["dissenting_source_ids"] = ["source-a"]
        with self.assertRaisesRegex(structured.SchemaError, "both supporting and dissenting"):
            self.parse(conflicting)

        empty_evidence = valid_output()
        empty_evidence["stock_viewpoints"][0]["evidence_post_ids"] = []
        with self.assertRaisesRegex(structured.SchemaError, "evidence.*non-empty"):
            self.parse(empty_evidence)

        imperative = valid_output()
        imperative["stock_viewpoints"][0]["statement"] = "系统建议立即买入该股票。"
        with self.assertRaisesRegex(structured.SchemaError, "imperative"):
            self.parse(imperative)

    def test_rejects_strong_consensus_wording_without_two_unopposed_sources(self) -> None:
        single_source = valid_output()
        single_source["stock_viewpoints"][0].update({
            "statement": "市场已确认估值见底。",
            "supporting_source_ids": ["source-a"],
            "dissenting_source_ids": [],
            "analysis_ids": ["post-a@1"],
            "evidence_post_ids": ["post-a"],
        })
        with self.assertRaisesRegex(structured.SchemaError, "strong consensus"):
            self.parse(single_source)

        dissenting_source = valid_output()
        dissenting_source["stock_viewpoints"][0]["statement"] = "多位博主一致认为估值见底。"
        with self.assertRaisesRegex(structured.SchemaError, "strong consensus"):
            self.parse(dissenting_source)

    def test_accepts_strong_consensus_wording_from_two_unopposed_sources(self) -> None:
        consensus = valid_output()
        consensus["stock_viewpoints"][0].update({
            "statement": "两位博主形成共识，认为估值仍需观察。",
            "supporting_source_ids": ["source-a", "source-b"],
            "dissenting_source_ids": [],
            "analysis_ids": ["post-a@1", "post-b@1"],
            "evidence_post_ids": ["post-a", "post-b"],
        })

        self.assertEqual(
            self.parse(consensus)["stock_viewpoints"][0]["supporting_source_ids"],
            ["source-a", "source-b"],
        )

    def test_allows_no_input_viewpoints_without_inventing_a_theme(self) -> None:
        empty = {
            "schema_version": "v2-x-cross-blogger",
            "stock_viewpoints": [],
            "market_industry_viewpoints": [],
            "uncertainties": ["没有可用于跨博主比较的新观点"],
        }
        self.assertEqual(self.parse(empty)["stock_viewpoints"], [])

    def test_rejects_an_unlisted_third_theme(self) -> None:
        invalid = valid_output()
        invalid["third_theme"] = []
        with self.assertRaisesRegex(structured.SchemaError, "unknown"):
            self.parse(invalid)

    def test_runtime_returns_only_validated_completion_and_safe_provider_telemetry(self) -> None:
        class MockProvider:
            def __init__(self) -> None:
                self.context: ProviderContext | None = None

            def complete(self, input_chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
                self.context = context
                self.assertEqual(input_chunk, tuple(context_payload["sources"]))
                return ProviderResponse(
                    status="success", provider="codex_cli", model_reported="gpt-fixture",
                    prompt_version=context.prompt_version, elapsed_ms=1, attempt=context.attempt,
                    raw_ref="/private/evidence/raw.json", parsed_output_ref="/private/evidence/structured.json",
                    parsed_output=valid_output(),
                )

            def assertEqual(self, left: object, right: object) -> None:
                if left != right:
                    raise AssertionError("runtime must pass only frozen included source context")

        context_payload = {
            "run_id": "judgement-run-1", "batch_id": "batch-1", "attempt": 1,
            "prompt_version": "v2-x-cross-blogger-1",
            "sources": [
                {"source_id": source_id, "display_name": source_id, "window_segments": [{
                    "id": f"segment-{source_id}", "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z",
                    "viewpoints": ["观点"], "uncertainties": [], "analyses": [{
                        "post_id": analysis_id, "blogger_viewpoint": "观点", "arguments": [], "quoted_post_viewpoint": None,
                        "uncertainties": [], "evidence_post_ids": [post_id],
                    }],
                }]} for source_id, analysis_id, post_id in (
                    ("source-a", "post-a@1", "post-a"), ("source-b", "post-b@1", "post-b"), ("source-c", "post-c@1", "post-c"),
                )
            ],
            "excluded_sources": [{"source_id": "source-z", "display_name": "Z", "reason": "no_new_information"}],
        }
        provider = MockProvider()
        runtime_type = getattr(runtime, "XDailyJudgementRuntime", None)
        self.assertIsNotNone(runtime_type, "daily judgement runtime must be public")
        result = runtime_type(provider=provider, prompt_template="private supplement").execute(  # type: ignore[misc]
            {"run_id": "judgement-run-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z", "batch": {"id": "batch-1", "natural_date": "2099-01-01", "cutoff_at": "2099-01-01T08:00:00Z", "coverage_status": "complete"}},
            context_payload,
        )
        self.assertEqual(result["provider"], "codex_cli")
        self.assertEqual(result["model_reported"], "gpt-fixture")
        self.assertNotIn("raw_ref", result)
        self.assertEqual(provider.context.operation, "v2_x_cross_blogger")

    def test_runtime_rejects_no_new_context_without_calling_provider(self) -> None:
        class NoNewProvider:
            called = False

            def complete(self, input_chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
                self.called = True
                return ProviderResponse(
                    status="success", provider="codex_cli", model_reported="gpt-fixture",
                    prompt_version=context.prompt_version, elapsed_ms=1, attempt=context.attempt,
                    raw_ref=None, parsed_output_ref=None, parsed_output={
                        "schema_version": "v2-x-cross-blogger",
                        "stock_viewpoints": [],
                        "market_industry_viewpoints": [],
                        "uncertainties": ["本窗口没有新增信息"],
                    },
                )

        context_payload = {
            "run_id": "judgement-run-1", "batch_id": "batch-1", "attempt": 1,
            "prompt_version": "v2-x-cross-blogger-1",
            "sources": [],
            "excluded_sources": [{
                "source_id": "source-no-new", "display_name": "No new", "reason": "no_new_information",
            }],
        }
        provider = NoNewProvider()
        with self.assertRaisesRegex(runtime.RuntimeExecutionError, "no included source"):
            runtime.XDailyJudgementRuntime(provider=provider, prompt_template="private").execute(
                {"run_id": "judgement-run-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z", "batch": {"id": "batch-1", "natural_date": "2099-01-01", "cutoff_at": "2099-01-01T08:00:00Z", "coverage_status": "complete"}},
                context_payload,
            )
        self.assertFalse(provider.called, "a no-new judgement must never reach the Provider")

    def test_runtime_rejects_no_new_claim_even_with_nonempty_context_without_calling_provider(self) -> None:
        class NoNewProvider:
            called = False

            def complete(self, _input_chunk: tuple[object, ...], _context: ProviderContext) -> ProviderResponse:
                self.called = True
                raise AssertionError("a no-new claim must never reach the Provider")

        context_payload = {
            "run_id": "judgement-run-1", "batch_id": "batch-1", "attempt": 1,
            "prompt_version": "v2-x-cross-blogger-1",
            "sources": [{"source_id": "source-a", "display_name": "A", "window_segments": [{
                "id": "segment-a", "occurred_from_at": "2099-01-01T00:00:00Z",
                "occurred_through_at": "2099-01-01T08:00:00Z", "viewpoints": [], "uncertainties": [],
                "analyses": [{"post_id": "post-a@1", "blogger_viewpoint": None, "arguments": [],
                    "quoted_post_viewpoint": None, "uncertainties": [], "evidence_post_ids": ["post-a"]}],
            }]}],
            "excluded_sources": [],
        }
        provider = NoNewProvider()
        with self.assertRaisesRegex(runtime.RuntimeExecutionError, "no-new"):
            runtime.XDailyJudgementRuntime(provider=provider, prompt_template="private").execute(
                {"run_id": "judgement-run-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z",
                 "batch": {"id": "batch-1", "natural_date": "2099-01-01",
                           "cutoff_at": "2099-01-01T08:00:00Z", "coverage_status": "no_new_information"}},
                context_payload,
            )
        self.assertFalse(provider.called, "a no-new claim must never reach the Provider")

    def test_runtime_rejects_unsafe_model_reported_before_completion(self) -> None:
        class UnsafeTelemetryProvider:
            def complete(self, _input_chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
                return ProviderResponse(
                    status="success", provider="codex_cli", model_reported="file:///private/evidence",
                    prompt_version=context.prompt_version, elapsed_ms=1, attempt=context.attempt,
                    raw_ref=None, parsed_output_ref=None, parsed_output=valid_output(),
                )

        context_payload = {
            "run_id": "judgement-run-1", "batch_id": "batch-1", "attempt": 1,
            "prompt_version": "v2-x-cross-blogger-1",
            "sources": [{"source_id": source_id, "display_name": source_id, "window_segments": [{
                "id": source_id, "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z",
                "viewpoints": [], "uncertainties": [], "analyses": [{
                    "post_id": analysis_id, "blogger_viewpoint": None, "arguments": [], "quoted_post_viewpoint": None,
                    "uncertainties": [], "evidence_post_ids": [post_id],
                }],
            }]} for source_id, analysis_id, post_id in (
                ("source-a", "post-a@1", "post-a"), ("source-b", "post-b@1", "post-b"), ("source-c", "post-c@1", "post-c"),
            )],
            "excluded_sources": [],
        }
        with self.assertRaisesRegex(runtime.RuntimeExecutionError, "model telemetry"):
            runtime.XDailyJudgementRuntime(provider=UnsafeTelemetryProvider(), prompt_template="private").execute(
                {"run_id": "judgement-run-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z", "batch": {"id": "batch-1", "natural_date": "2099-01-01", "cutoff_at": "2099-01-01T08:00:00Z", "coverage_status": "complete"}},
                context_payload,
            )

    def test_runtime_rejects_batch_run_and_segment_ids_in_every_natural_language_field(self) -> None:
        claim = {
            "run_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "attempt": 1,
            "lease_expires_at": "2099-01-01T00:10:00Z",
            "batch": {"id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "natural_date": "2099-01-01",
                      "cutoff_at": "2099-01-01T08:00:00Z", "coverage_status": "complete"},
        }
        context_payload = {
            "run_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            "batch_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "attempt": 1,
            "prompt_version": "v2-x-cross-blogger-1",
            "sources": [{"source_id": source_id, "display_name": source_id, "window_segments": [{
                "id": segment_id, "occurred_from_at": "2099-01-01T00:00:00Z", "occurred_through_at": "2099-01-01T08:00:00Z",
                "viewpoints": [], "uncertainties": [], "analyses": [{
                    "post_id": analysis_id, "blogger_viewpoint": None, "arguments": [], "quoted_post_viewpoint": None,
                    "uncertainties": [], "evidence_post_ids": [post_id],
                }],
            }]} for source_id, segment_id, analysis_id, post_id in (
                ("source-a", "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "post-a@1", "post-a"),
                ("source-b", "segment-b", "post-b@1", "post-b"),
                ("source-c", "segment-c", "post-c@1", "post-c"),
            )],
            "excluded_sources": [],
        }

        for opaque_kind, opaque_id in (
            ("batch", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
            ("run", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
            ("segment", "cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
        ):
            for rendered_opaque_id in (opaque_id, opaque_id.upper()):
                for natural_language_field in ("statement", "item_uncertainty", "top_uncertainty"):
                    with self.subTest(
                        opaque_kind=opaque_kind,
                        case_variant=rendered_opaque_id != opaque_id,
                        natural_language_field=natural_language_field,
                    ):
                        output = valid_output()
                        if natural_language_field == "statement":
                            output["stock_viewpoints"][0]["statement"] = f"{rendered_opaque_id} 表示估值仍需观察。"
                        elif natural_language_field == "item_uncertainty":
                            output["stock_viewpoints"][0]["uncertainties"] = [f"{rendered_opaque_id} 的上下文不足"]
                        else:
                            output["uncertainties"] = [f"{rendered_opaque_id} 的上下文不足"]

                        class OpaqueContextProvider:
                            def complete(self, _input_chunk: tuple[object, ...], provider_context: ProviderContext) -> ProviderResponse:
                                return ProviderResponse(
                                    status="success", provider="codex_cli", model_reported="gpt-fixture",
                                    prompt_version=provider_context.prompt_version, elapsed_ms=1, attempt=provider_context.attempt,
                                    raw_ref=None, parsed_output_ref=None, parsed_output=output,
                                )

                        with self.assertRaisesRegex(runtime.RuntimeExecutionError, "evidence validation"):
                            runtime.XDailyJudgementRuntime(provider=OpaqueContextProvider(), prompt_template="private").execute(
                                claim,
                                context_payload,
                            )

    def test_standard_worker_claim_completes_one_regeneration_without_touching_source_state(self) -> None:
        class RegenerationProtocol:
            def __init__(self) -> None:
                self.run_kind = "regeneration"
                self.source_tasks = {"source-a": "succeeded"}
                self.coverage = {"source-a": "2099-01-01T08:00:00Z"}
                self.completions: list[dict[str, object]] = []

            def heartbeat(self, *_args: object, **_kwargs: object) -> dict[str, object]:
                return {"status": "idle"}

            def claim_x_daily_judgement(self) -> dict[str, object] | None:
                return {
                    "run_id": "regeneration-run-1", "attempt": 1, "lease_expires_at": "2099-01-01T00:10:00Z",
                    "batch": {"id": "batch-1", "natural_date": "2099-01-01", "cutoff_at": "2099-01-01T08:00:00Z", "coverage_status": "complete"},
                }

            def get_x_daily_judgement_context(self, run_id: str, attempt: int) -> dict[str, object]:
                return {"run_id": run_id, "attempt": attempt, "prompt_version": "v2-x-cross-blogger-1", "sources": [], "excluded_sources": []}

            def complete_x_daily_judgement(self, completion: dict[str, object]) -> dict[str, object]:
                self.completions.append(completion)
                return {"status": "succeeded"}

            def fail_x_daily_judgement(self, _run_id: str, _attempt: int, _failure_class: str) -> dict[str, object]:
                raise AssertionError("a successful regeneration must not report failure")

        protocol = RegenerationProtocol()
        source_tasks_before = dict(protocol.source_tasks)
        coverage_before = dict(protocol.coverage)

        outcome = Worker(protocol).run_x_daily_judgement_once(
            lambda claim, _context: {"run_id": claim["run_id"], "attempt": claim["attempt"], "schema_version": "v2-x-cross-blogger"},
        )

        self.assertEqual(outcome.status, "succeeded")
        self.assertEqual(protocol.run_kind, "regeneration")
        self.assertEqual(protocol.completions, [{"run_id": "regeneration-run-1", "attempt": 1, "schema_version": "v2-x-cross-blogger"}])
        self.assertEqual(protocol.source_tasks, source_tasks_before)
        self.assertEqual(protocol.coverage, coverage_before)


if __name__ == "__main__":
    unittest.main()
