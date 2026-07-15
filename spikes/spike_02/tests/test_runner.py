import tempfile
import unittest
from pathlib import Path

from spike_02.evidence import EvidenceStore
from spike_02.fixtures import load_fixture
from spike_02.model import ProviderResponse
from spike_02.providers import MockOutcome, MockProvider
from spike_02.runner import RunConfig, run_case


VALID_JSON = '{"topics":[],"media_unparsed":false,"warnings":[]}'


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
                ids[2]: [MockOutcome.success(VALID_JSON)],
                ids[3]: [MockOutcome.success(VALID_JSON)],
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

    def test_truncated_chunk_splits_and_preserves_primary_ids(self):
        root_id = f"{self.case.case_id}-0000"
        provider = MockProvider(
            {
                root_id: [MockOutcome.truncated("partial")],
                f"{root_id}-split-0000": [MockOutcome.success(VALID_JSON)],
                f"{root_id}-split-0001": [MockOutcome.success(VALID_JSON)],
                f"{self.case.case_id}-0001": [MockOutcome.success(VALID_JSON)],
                f"{self.case.case_id}-0002": [MockOutcome.success(VALID_JSON)],
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
