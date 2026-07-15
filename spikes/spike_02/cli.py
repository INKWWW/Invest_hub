from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path

from .chunking import build_chunks
from .evaluation import evaluate_review_sheet
from .evidence import EvidenceStore
from .fixtures import build_synthetic_scale_case, load_fixture
from .providers import GLMProvider, MockOutcome, MockProvider
from .runner import RunConfig, run_case


VALID_JSON = '{"topics":[],"media_unparsed":false,"warnings":[]}'


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
        if args.command == "evaluate":
            report = evaluate_review_sheet(Path(args.review_file))
            print(json.dumps(asdict(report), ensure_ascii=False, sort_keys=True))
            return 0
        case = _load_case(args)
        evidence = EvidenceStore(Path(args.evidence_dir))
        config = RunConfig(
            max_primary_messages=args.chunk_size,
            max_attempts=args.max_attempts,
            prompt_version=args.prompt_version,
        )
        if args.command == "mock":
            chunks = build_chunks(case, args.chunk_size, config.context_limit)
            provider = MockProvider(
                {chunk.chunk_id: [MockOutcome.success(VALID_JSON)] for chunk in chunks}
            )
        else:
            missing = [
                name
                for name in (
                    "SPIKE02_GLM_API_KEY",
                    "SPIKE02_GLM_ENDPOINT",
                    "SPIKE02_GLM_MODEL",
                )
                if not os.environ.get(name)
            ]
            if missing:
                print(f"missing runtime environment: {', '.join(missing)}", file=sys.stderr)
                return 2
            provider = GLMProvider(
                endpoint=os.environ["SPIKE02_GLM_ENDPOINT"],
                api_key=os.environ["SPIKE02_GLM_API_KEY"],
                model=os.environ["SPIKE02_GLM_MODEL"],
            )
        report = run_case(case, provider, config, evidence)
        summary = asdict(report)
        summary.pop("primary_message_ids", None)
        summary.pop("results", None)
        summary["result_count"] = len(report.results)
        summary["primary_message_count"] = len(report.primary_message_ids)
        print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
        return 0
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except SystemExit as exc:
        return int(exc.code)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the local Spike-02 harness")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("mock", "glm"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--fixture")
        subparser.add_argument("--synthetic-count", type=int)
        subparser.add_argument("--evidence-dir", required=True)
        subparser.add_argument("--chunk-size", type=int, default=25)
        subparser.add_argument("--max-attempts", type=int, default=3)
        subparser.add_argument("--prompt-version", default="spike-02-v1")
    evaluate = subparsers.add_parser("evaluate")
    evaluate.add_argument("--evidence-dir", required=True)
    evaluate.add_argument("--review-file", required=True)
    return parser


def _load_case(args):
    if args.fixture and args.synthetic_count is not None:
        raise ValueError("use either --fixture or --synthetic-count")
    if args.fixture:
        return load_fixture(Path(args.fixture))
    if args.synthetic_count is not None:
        return build_synthetic_scale_case("synthetic-scale", args.synthetic_count)
    raise ValueError("one of --fixture or --synthetic-count is required")


if __name__ == "__main__":
    raise SystemExit(main())
