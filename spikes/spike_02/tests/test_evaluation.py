import json
import tempfile
import unittest
from pathlib import Path

from spike_02.evaluation import (
    classify_run,
    evaluate_output,
    evaluate_review_sheet,
)
from spike_02.fixtures import load_fixture
from spike_02.model import (
    RunReport,
    StructuredOutput,
    StructuredTopic,
)


def output_with_claim(summary, source_ids=("public-001",), *, author_id="target-analyst"):
    return StructuredOutput(
        topics=(
            StructuredTopic(
                title="ABC",
                summary=summary,
                source_message_ids=tuple(source_ids),
                author_scope="target",
                author_id=author_id,
                tickers=("ABC",),
                operation_tendency=None,
                uncertainty=None,
            ),
        ),
        media_unparsed=False,
        warnings=(),
    )


def successful_report(scale):
    return RunReport(
        run_id=f"run-{scale}",
        provider="codex",
        case_id=f"case-{scale}",
        scale=scale,
        chunk_size=3,
        request_count=1,
        retry_count=0,
        first_success_rate=1.0,
        final_success_rate=1.0,
        json_parse_rate=1.0,
        p50_latency_ms=10,
        p95_latency_ms=20,
        primary_message_ids=(),
        results=(),
        batch_elapsed_ms=0,
        max_concurrency=1,
        max_active_requests=0,
    )


class EvaluationTests(unittest.TestCase):
    def setUp(self):
        self.case = load_fixture(Path("spikes/spike_02/fixtures/public_small.json"))

    def test_claim_is_grounded_only_when_source_ids_and_terms_match(self):
        report = evaluate_output(
            self.case,
            output_with_claim("ABC 收入增速仍然稳健", ("public-001",)),
        )
        self.assertEqual(report.grounded_claims, 1)

    def test_wrong_target_author_is_severe_attribution_error(self):
        report = evaluate_output(
            self.case,
            output_with_claim(
                "先观察，不追高",
                ("public-005",),
                author_id="wrong-author",
            ),
        )
        self.assertEqual(report.severe_attribution_errors, 1)

    def test_media_hallucination_is_blocking(self):
        output = output_with_claim(
            "图片显示了明确的上涨形态",
            ("public-008",),
        )
        report = evaluate_output(self.case, output)
        self.assertEqual(report.media_hallucinations, 1)

    def test_review_sheet_requires_boolean_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "review.jsonl"
            path.write_text(
                json.dumps(
                    {
                        "case_id": self.case.case_id,
                        "claim_id": "claim-001",
                        "covered": True,
                        "grounded": True,
                        "correct_attribution": True,
                        "media_hallucination": False,
                        "note": "ok",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            report = evaluate_review_sheet(path)
            self.assertEqual(report.grounded_claims, 1)

    def test_threshold_classifier_returns_conditional_pass_for_capacity_limit(self):
        quality = type(
            "Quality",
            (),
            {
                "grounded_claims": 95,
                "required_claims": 100,
                "severe_attribution_errors": 0,
                "media_hallucinations": 0,
            },
        )()
        decision = classify_run(
            (
                successful_report("small"),
                successful_report("medium"),
                successful_report("large"),
            ),
            quality,
            has_real_codex_evidence=True,
            constrained=True,
        )
        self.assertEqual(decision, "conditional_pass")


if __name__ == "__main__":
    unittest.main()
