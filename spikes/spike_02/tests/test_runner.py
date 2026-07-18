import threading
import tempfile
import time
import unittest
from pathlib import Path

from spike_02.evidence import EvidenceStore
from spike_02.fixtures import load_fixture
from spike_02.model import ProviderResponse
from spike_02.providers import MockOutcome, MockProvider
from spike_02.runner import RunConfig, run_case


VALID_JSON = '{"topics":[],"media_unparsed":false,"media_source_message_ids":[],"warnings":[]}'
MEDIA_INVALID_JSON = (
    '{"topics":[],"media_unparsed":true,"media_source_message_ids":[],'
    '"warnings":["存在未解析媒体，未推测其内容。"]}'
)
MEDIA_VALID_JSON = (
    '{"topics":[],"media_unparsed":true,"media_source_message_ids":["public-008"],'
    '"warnings":["存在未解析媒体，未推测其内容。"]}'
)


def response_json_for_request(request):
    input_ids = set(request.chunk.primary_message_ids) | set(request.chunk.context_message_ids)
    return MEDIA_VALID_JSON if "public-008" in input_ids else VALID_JSON


class SlowProvider:
    def __init__(self, delay_seconds: float):
        self.delay_seconds = delay_seconds
        self._lock = threading.Lock()
        self._active = 0
        self.max_active = 0
        self._calls: dict[str, int] = {}

    def complete(self, request):
        with self._lock:
            self._active += 1
            self.max_active = max(self.max_active, self._active)
            self._calls[request.chunk.chunk_id] = self._calls.get(request.chunk.chunk_id, 0) + 1
        try:
            time.sleep(self.delay_seconds)
            return ProviderResponse(
                "success",
                response_json_for_request(request),
                10,
                None,
                None,
                "stop",
                None,
            )
        finally:
            with self._lock:
                self._active -= 1

    def calls_for(self, chunk_id: str) -> int:
        with self._lock:
            return self._calls.get(chunk_id, 0)


class DelayedScriptProvider:
    def __init__(self, scripts, delays):
        self._scripts = {chunk_id: tuple(outcomes) for chunk_id, outcomes in scripts.items()}
        self._delays = delays
        self._lock = threading.Lock()
        self._calls: dict[str, int] = {}

    def complete(self, request):
        chunk_id = request.chunk.chunk_id
        with self._lock:
            call_index = self._calls.get(chunk_id, 0)
            self._calls[chunk_id] = call_index + 1
        time.sleep(self._delays.get((chunk_id, call_index), 0.0))
        outcome = self._scripts[chunk_id][call_index]
        return ProviderResponse(
            status=outcome.status,
            content=outcome.content,
            latency_ms=10,
            input_tokens=None,
            output_tokens=None,
            finish_reason=outcome.finish_reason,
            error_code=outcome.error_code,
        )

    def calls_for(self, chunk_id: str) -> int:
        with self._lock:
            return self._calls.get(chunk_id, 0)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.case = load_fixture(Path("spikes/spike_02/fixtures/public_small.json"))

    def test_failed_chunk_retries_without_recalling_completed_chunk(self):
        ids = [
            f"{self.case.case_id}-{index:04d}"
            for index in range(4)
        ]
        provider = MockProvider(
            {
                ids[0]: [MockOutcome.failure("timeout"), MockOutcome.success(VALID_JSON)],
                ids[1]: [MockOutcome.success(VALID_JSON)],
                ids[2]: [MockOutcome.success(MEDIA_VALID_JSON)],
                ids[3]: [MockOutcome.success(MEDIA_VALID_JSON)],
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            report = run_case(
                self.case,
                provider,
                RunConfig(max_primary_messages=3, max_attempts=3),
                EvidenceStore(Path(directory)),
                sleep=lambda _: None,
            )
        self.assertEqual(report.final_success_rate, 1.0)
        self.assertEqual(provider.calls_for(ids[0]), 2)
        self.assertEqual(provider.calls_for(ids[1]), 1)
        self.assertEqual(report.retry_count, 1)

    def test_invalid_media_source_schema_retries_and_accepts_complete_source(self):
        chunk_id = f"{self.case.case_id}-0000"
        provider = MockProvider(
            {chunk_id: [MockOutcome.success(MEDIA_INVALID_JSON), MockOutcome.success(MEDIA_VALID_JSON)]}
        )
        with tempfile.TemporaryDirectory() as directory:
            report = run_case(
                self.case,
                provider,
                RunConfig(max_primary_messages=12),
                EvidenceStore(Path(directory)),
                sleep=lambda _: None,
            )
        self.assertEqual(report.final_success_rate, 1.0)
        self.assertEqual(provider.calls_for(chunk_id), 2)
        self.assertEqual(report.retry_count, 1)
        self.assertEqual(report.results[0].output.media_source_message_ids, ("public-008",))

    def test_bounded_concurrency_processes_chunks_in_parallel(self):
        provider = SlowProvider(delay_seconds=0.05)
        with tempfile.TemporaryDirectory() as directory:
            report = run_case(
                self.case,
                provider,
                RunConfig(max_primary_messages=3, max_concurrency=2),
                EvidenceStore(Path(directory)),
                sleep=lambda _: None,
            )
        self.assertGreaterEqual(provider.max_active, 2)
        self.assertLessEqual(report.max_active_requests, 2)
        self.assertEqual(report.max_concurrency, 2)
        self.assertEqual(report.request_count, 4)
        self.assertEqual(report.final_success_rate, 1.0)

    def test_concurrent_retry_isolated_and_results_are_stably_ordered(self):
        ids = [f"{self.case.case_id}-{index:04d}" for index in range(2)]
        provider = DelayedScriptProvider(
            {
                ids[0]: [MockOutcome.failure("timeout"), MockOutcome.success(VALID_JSON)],
                ids[1]: [MockOutcome.success(MEDIA_VALID_JSON)],
            },
            {(ids[0], 0): 0.05},
        )
        with tempfile.TemporaryDirectory() as directory:
            report = run_case(
                self.case,
                provider,
                RunConfig(max_primary_messages=6, max_concurrency=2),
                EvidenceStore(Path(directory)),
                sleep=lambda _: None,
            )
        self.assertEqual(provider.calls_for(ids[0]), 2)
        self.assertEqual(provider.calls_for(ids[1]), 1)
        self.assertEqual(report.final_success_rate, 1.0)
        self.assertEqual([result.chunk_id for result in report.results], ids)

    def test_truncated_chunk_splits_and_preserves_primary_ids(self):
        root_id = f"{self.case.case_id}-0000"
        provider = MockProvider(
            {
                root_id: [MockOutcome.truncated("partial")],
                f"{root_id}-split-0000": [MockOutcome.success(VALID_JSON)],
                f"{root_id}-split-0001": [MockOutcome.success(VALID_JSON)],
                f"{self.case.case_id}-0001": [MockOutcome.success(MEDIA_VALID_JSON)],
                f"{self.case.case_id}-0002": [MockOutcome.success(MEDIA_VALID_JSON)],
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            report = run_case(
                self.case,
                provider,
                RunConfig(max_primary_messages=4),
                EvidenceStore(Path(directory)),
                sleep=lambda _: None,
            )
        self.assertEqual(report.final_success_rate, 1.0)
        self.assertEqual(
            set(report.primary_message_ids),
            {message.message_id for message in self.case.messages},
        )
        self.assertEqual(report.request_count, 5)


if __name__ == "__main__":
    unittest.main()
