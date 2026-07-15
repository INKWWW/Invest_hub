import json
import tempfile
import unittest
from pathlib import Path

from spike_01.checkpoint import JsonCheckpointStore
from spike_01.connectors import FakeConnector
from spike_01.evidence import LocalEvidenceStore
from spike_01.model import RawMessage, RawPage, SourceConfig
from spike_01.runner import build_parser, run_incremental
from spike_01.telemetry import TelemetryRecorder


FIXTURE = Path("spikes/spike_01/fixtures/recovery_pages.json")


class RunnerTests(unittest.TestCase):
    def config(self, channel="channel-public-001"):
        return SourceConfig(
            source_container_id=channel,
            channel_url=f"fixture://{channel}",
            source_account_id="test-account",
        )

    def test_second_run_uses_checkpoint_and_writes_no_new_messages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = LocalEvidenceStore(root / "evidence")
            checkpoints = JsonCheckpointStore(root / "checkpoint")
            connector = FakeConnector.from_fixture(
                FIXTURE,
                source_container_id="channel-public-001",
            )
            first = run_incremental(
                connector,
                self.config(),
                evidence,
                checkpoints,
            )
            second = run_incremental(
                connector,
                self.config(),
                evidence,
                checkpoints,
            )
            self.assertEqual(first.status, "success")
            self.assertEqual(second.status, "success")
            self.assertEqual(second.accepted_messages, 0)
            self.assertEqual(evidence.message_count(), 6)
            self.assertEqual(first.checkpoint_after, second.checkpoint_after)

    def test_replaying_without_checkpoint_records_duplicates_without_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = LocalEvidenceStore(root / "evidence")
            checkpoints = JsonCheckpointStore(root / "checkpoint")
            config = self.config()
            connector = FakeConnector.from_fixture(
                FIXTURE,
                source_container_id="channel-public-001",
            )
            first = run_incremental(connector, config, evidence, checkpoints)
            replay = run_incremental(
                FakeConnector.from_fixture(
                    FIXTURE,
                    source_container_id="channel-public-001",
                ),
                config,
                evidence,
                JsonCheckpointStore(root / "replay-checkpoint"),
            )
            self.assertEqual(first.accepted_messages, 5)
            self.assertEqual(replay.duplicate_messages, 6)
            self.assertEqual(replay.unresolved_messages, 0)
            self.assertEqual(evidence.message_count(), 6)

    def test_failure_does_not_advance_past_last_persisted_page(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = LocalEvidenceStore(root / "evidence")
            checkpoints = JsonCheckpointStore(root / "checkpoint")
            config = self.config()
            failed = run_incremental(
                FakeConnector.from_fixture(
                    FIXTURE,
                    source_container_id="channel-public-001",
                    fail_after_page=1,
                ),
                config,
                evidence,
                checkpoints,
            )
            self.assertEqual(failed.status, "partial")
            self.assertEqual(failed.checkpoint_after.cursor, "cursor-001")
            resumed = run_incremental(
                FakeConnector.from_fixture(
                    FIXTURE,
                    source_container_id="channel-public-001",
                ),
                config,
                evidence,
                checkpoints,
            )
            self.assertEqual(resumed.status, "success")
            self.assertEqual(resumed.checkpoint_after.cursor, "cursor-003")
            self.assertEqual(evidence.message_count(), 6)

    def test_one_channel_failure_does_not_block_another(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            channel_a = run_incremental(
                FakeConnector.from_fixture(
                    FIXTURE,
                    source_container_id="channel-public-001",
                    fail_after_page=0,
                ),
                self.config("channel-public-001"),
                LocalEvidenceStore(root / "a-evidence"),
                JsonCheckpointStore(root / "a-checkpoint"),
            )
            channel_b = run_incremental(
                FakeConnector.from_fixture(
                    FIXTURE,
                    source_container_id="channel-public-001",
                ),
                self.config("channel-public-001"),
                LocalEvidenceStore(root / "b-evidence"),
                JsonCheckpointStore(root / "b-checkpoint"),
            )
            self.assertEqual(channel_a.status, "failed")
            self.assertEqual(channel_b.status, "success")

    def test_invalid_message_preserves_raw_page_and_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            invalid_payload = {
                "page_id": "invalid-page",
                "source_container_id": "channel-public-001",
                "cursor_before": None,
                "cursor_after": "cursor-invalid",
                "messages": [
                    {
                        "id": "message-invalid",
                        "author": {"name": "No ID"},
                        "channel_id": "channel-public-001",
                        "published_at": "2026-01-01T08:00:00Z",
                        "content": "invalid fixture",
                        "content_type": "text",
                        "reply_to": None,
                        "quote": None,
                        "attachments": [],
                        "source_url": "https://discord.example/invalid",
                    }
                ],
            }
            path = root / "invalid.json"
            path.write_text(json.dumps({"pages": [invalid_payload]}))
            evidence = LocalEvidenceStore(root / "evidence")
            checkpoints = JsonCheckpointStore(root / "checkpoint")
            report = run_incremental(
                FakeConnector.from_fixture(
                    path,
                    source_container_id="channel-public-001",
                ),
                self.config(),
                evidence,
                checkpoints,
            )
            self.assertEqual(report.status, "partial")
            self.assertIsNone(report.checkpoint_after)
            self.assertTrue((root / "evidence" / "raw" / "invalid-page.json").exists())

    def test_run_records_connector_and_pipeline_phase_timing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            page = RawPage(
                page_id="timed-page",
                source_container_id="channel-public-001",
                cursor_before=None,
                cursor_after="cursor-timed",
                messages=(
                    RawMessage(
                        ordinal=0,
                        payload={
                            "id": "message-timed",
                            "author": {"id": "author-timed", "name": "Timed"},
                            "channel_id": "channel-public-001",
                            "published_at": "2026-01-01T08:00:00Z",
                            "content": "timed fixture",
                            "content_type": "text",
                            "reply_to": None,
                            "quote": None,
                            "attachments": [],
                            "source_url": "https://discord.example/message-timed",
                        },
                    ),
                ),
                raw_payload_ref="fixture://timed-page",
                telemetry={
                    "open_ms": 10,
                    "wait_ms": 20,
                    "network_observation_ms": 30,
                    "detail_ms": 15,
                    "network_attempts": 2,
                    "match_state": "matched_new",
                    "error_code": None,
                },
            )
            evidence = LocalEvidenceStore(root / "evidence")
            checkpoints = JsonCheckpointStore(root / "checkpoint")
            telemetry = TelemetryRecorder(root / "telemetry.jsonl")

            report = run_incremental(
                FakeConnector((page,)),
                self.config(),
                evidence,
                checkpoints,
                telemetry=telemetry,
            )

            self.assertEqual(report.status, "success")
            timing = json.loads(
                (root / "telemetry.jsonl")
                .read_text(encoding="utf-8")
                .splitlines()[0]
            )
            self.assertEqual(timing["network_attempts"], 2)
            self.assertEqual(timing["match_state"], "matched_new")
            self.assertGreaterEqual(timing["persist_ms"], 0)
            self.assertGreaterEqual(timing["elapsed_ms"], timing["open_ms"])

    def test_real_parser_accepts_telemetry_and_page_timeout(self):
        args = build_parser().parse_args(
            [
                "real",
                "--channel-url",
                "https://discord.example/channel",
                "--source-container-id",
                "channel-public-001",
                "--profile-path",
                "/private/profile",
                "--source-account-id",
                "local-test",
                "--opencli-bin",
                "opencli",
                "--contract-path",
                "/private/contract.json",
                "--evidence-dir",
                "/private/evidence",
                "--telemetry-path",
                "/private/evidence/telemetry.jsonl",
                "--page-timeout-seconds",
                "90",
                "--max-messages",
                "100",
            ]
        )
        self.assertEqual(args.telemetry_path, Path("/private/evidence/telemetry.jsonl"))
        self.assertEqual(args.page_timeout_seconds, 90)


if __name__ == "__main__":
    unittest.main()
