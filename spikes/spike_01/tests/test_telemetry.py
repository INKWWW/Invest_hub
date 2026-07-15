import json
import tempfile
import unittest
from pathlib import Path

from spike_01.telemetry import PageTiming, TelemetryRecorder


class TelemetryTests(unittest.TestCase):
    def test_record_writes_safe_page_timing_jsonl(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "telemetry.jsonl"
            recorder = TelemetryRecorder(target)
            recorder.record(
                PageTiming(
                    page_index=1,
                    elapsed_ms=120,
                    open_ms=10,
                    wait_ms=20,
                    network_observation_ms=30,
                    detail_ms=15,
                    mapping_ms=12,
                    validation_ms=8,
                    persist_ms=25,
                    network_attempts=2,
                    match_state="matched_new",
                    error_code=None,
                )
            )

            payload = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(payload["page_index"], 1)
            self.assertEqual(payload["match_state"], "matched_new")
            self.assertNotIn("content", payload)
            self.assertNotIn("channel_url", payload)
            self.assertNotIn("profile_path", payload)

    def test_unknown_match_state_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            recorder = TelemetryRecorder(Path(directory) / "telemetry.jsonl")
            with self.assertRaisesRegex(ValueError, "match_state"):
                recorder.record(
                    PageTiming(
                        page_index=1,
                        elapsed_ms=1,
                        open_ms=0,
                        wait_ms=0,
                        network_observation_ms=0,
                        detail_ms=0,
                        mapping_ms=0,
                        validation_ms=0,
                        persist_ms=0,
                        network_attempts=0,
                        match_state="old_response",
                        error_code="stale_response",
                    )
                )


if __name__ == "__main__":
    unittest.main()
