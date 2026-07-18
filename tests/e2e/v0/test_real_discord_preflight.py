from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from invest_hub_worker.config import LocalWorkerConfig
from scripts.v0.preflight import run_preflight


class RealDiscordPreflightTests(unittest.TestCase):
    def config_payload(self, profile_ref: str) -> dict[str, str]:
        return {
            "control_plane_url": "https://control.example.invalid",
            "source_id": "discord-source-1",
            "channel_url": "https://discord.example.invalid/private-channel",
            "profile_ref": profile_ref,
            "opencli_contract_version": "v0",
            "parameter_version": "v0-default",
        }

    def write_config(self, path: Path, payload: dict[str, str]) -> None:
        path.write_text(json.dumps(payload), encoding="utf-8")
        os.chmod(path, 0o600)

    def test_preflight_passes_without_emitting_url_or_profile_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "profile"
            profile.mkdir()
            config_path = Path(directory) / "worker.json"
            self.write_config(config_path, self.config_payload(str(profile)))

            result = run_preflight(config_path, opencli_version="opencli-test", network_check=False)

            self.assertEqual(result["status"], "pass")
            self.assertEqual(result["source_id"], "discord-source-1")
            rendered = json.dumps(result, ensure_ascii=False)
            self.assertNotIn("control.example.invalid", rendered)
            self.assertNotIn(str(profile), rendered)
            self.assertNotIn("private-channel", rendered)

    def test_missing_profile_is_a_typed_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "worker.json"
            self.write_config(config_path, self.config_payload(str(Path(directory) / "missing")))

            result = run_preflight(config_path, opencli_version="opencli-test", network_check=False)

            self.assertEqual(result["status"], "fail")
            self.assertIn("profile_missing", result["failures"])


if __name__ == "__main__":
    unittest.main()
