from __future__ import annotations

import math
import time
import uuid
from dataclasses import dataclass
from typing import Callable

from .chunking import build_chunks, split_chunk
from .evidence import EvidenceStore
from .model import (
    Chunk,
    ChunkResult,
    FixtureCase,
    LLMRequest,
    ProviderName,
    RunReport,
)
from .providers import CodexCLIProvider, LLMProvider
from .schema import SchemaError, parse_structured_output, validate_structured_output


RETRYABLE_STATUSES = frozenset(
    {
        "timeout",
        "provider_failed",
        "empty_response",
        "invalid_provider_response",
        "rate_limited",
        "provider_unavailable",
        "invalid_provider_response",
        "invalid_json",
        "schema_error",
    }
)


@dataclass(frozen=True)
class RunConfig:
    max_primary_messages: int
    context_limit: int = 2
    max_attempts: int = 3
    prompt_version: str = "spike-02-v1"
    retry_delays_seconds: tuple[float, ...] = (1.0, 2.0)
    max_concurrency: int = 1


def run_case(
    case: FixtureCase,
    provider: LLMProvider,
    config: RunConfig,
    evidence: EvidenceStore,
    *,
    sleep: Callable[[float], None] = time.sleep,
) -> RunReport:
    if config.max_attempts < 1:
        raise ValueError("max_attempts must be positive")
    if config.max_concurrency < 1:
        raise ValueError("max_concurrency must be positive")
    batch_started = time.monotonic_ns()
    run_id = uuid.uuid4().hex
    initial_chunks = list(
        build_chunks(
            case,
            max_primary_messages=config.max_primary_messages,
            context_limit=config.context_limit,
        )
    )
    queue = initial_chunks[:]
    first_successes = 0
    request_count = 0
    retry_count = 0
    json_attempts = 0
    json_successes = 0
    latencies: list[int] = []
    results: list[ChunkResult] = []

    while queue:
        chunk = queue.pop(0)
        attempts = 0
        completed = False
        first_response_success = False
        while attempts < config.max_attempts:
            attempts += 1
            request = LLMRequest(
                run_id=run_id,
                chunk=chunk,
                attempt=attempts,
                prompt_version=config.prompt_version,
            )
            response = provider.complete(request)
            request_count += 1
            latencies.append(response.latency_ms)
            if attempts == 1 and response.status == "success":
                first_response_success = True
            evidence.persist_request(request, response)
            evidence.persist_raw_response(
                f"{run_id}-{chunk.chunk_id}-{attempts}",
                {
                    "status": response.status,
                    "content": response.content,
                    "finish_reason": response.finish_reason,
                    "error_code": response.error_code,
                    "process_exit_code": response.process_exit_code,
                    "diagnostic": response.diagnostic,
                },
            )

            if response.content is not None:
                json_attempts += 1
            if response.status == "truncated":
                if len(chunk.primary_message_ids) > 1:
                    left, right = split_chunk(chunk)
                    queue[0:0] = [left, right]
                    retry_count += 1
                    completed = True
                    break
                results.append(
                    ChunkResult(
                        chunk_id=chunk.chunk_id,
                        status="truncated",
                        attempts=attempts,
                        output=None,
                        error_code=response.error_code,
                    )
                )
                completed = True
                break

            if response.status == "success" and response.content is not None:
                try:
                    output = parse_structured_output(response.content)
                    input_ids = set(chunk.primary_message_ids) | set(chunk.context_message_ids)
                    target_ids = {
                        message.author_id
                        for message in case.messages
                        if message.author_scope == "target"
                    }
                    validate_structured_output(output, input_ids, target_ids)
                except SchemaError as exc:
                    json_attempts += 0
                    status = "invalid_json" if exc.code == "invalid_json" else "schema_error"
                    if attempts < config.max_attempts:
                        retry_count += 1
                        sleep(_retry_delay(config, attempts))
                        continue
                    results.append(
                        ChunkResult(chunk.chunk_id, status, attempts, None, exc.code)
                    )
                    completed = True
                    break
                json_successes += 1
                result = ChunkResult(chunk.chunk_id, "success", attempts, output, None)
                evidence.persist_result(result)
                results.append(result)
                completed = True
                break

            if response.status in RETRYABLE_STATUSES and attempts < config.max_attempts:
                retry_count += 1
                sleep(_retry_delay(config, attempts))
                continue

            results.append(
                ChunkResult(
                    chunk_id=chunk.chunk_id,
                    status=response.status,
                    attempts=attempts,
                    output=None,
                    error_code=response.error_code or response.status,
                )
            )
            completed = True
            break

        if not completed:
            results.append(
                ChunkResult(
                    chunk_id=chunk.chunk_id,
                    status="failed",
                    attempts=attempts,
                    output=None,
                    error_code="max_attempts_exhausted",
                )
            )
        if first_response_success:
            first_successes += 1

    provider_name: ProviderName = (
        "codex" if isinstance(provider, CodexCLIProvider) else "mock"
    )
    report = RunReport(
        run_id=run_id,
        provider=provider_name,
        case_id=case.case_id,
        scale=case.scale,
        chunk_size=config.max_primary_messages,
        request_count=request_count,
        retry_count=retry_count,
        first_success_rate=_rate(first_successes, len(initial_chunks)),
        final_success_rate=_rate(
            sum(result.status == "success" for result in results),
            len(results),
        ),
        json_parse_rate=_rate(json_successes, json_attempts),
        p50_latency_ms=_percentile(latencies, 0.50),
        p95_latency_ms=_percentile(latencies, 0.95),
        primary_message_ids=tuple(message.message_id for message in case.messages),
        results=tuple(results),
        batch_elapsed_ms=(time.monotonic_ns() - batch_started) // 1_000_000,
        max_concurrency=config.max_concurrency,
        max_active_requests=1 if request_count else 0,
    )
    evidence.persist_metrics(report)
    return report


def _retry_delay(config: RunConfig, attempts: int) -> float:
    index = min(attempts - 1, len(config.retry_delays_seconds) - 1)
    return config.retry_delays_seconds[index] if config.retry_delays_seconds else 0.0


def _rate(numerator: int, denominator: int) -> float:
    return numerator / denominator if denominator else 0.0


def _percentile(values: list[int], percentile: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(percentile * len(ordered)) - 1))
    return ordered[index]
