from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from invest_hub_worker.config import LocalWorkerConfig
from scripts.v0.preflight import _reachable, run_preflight


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

    def test_preflight_uses_only_the_local_bypass_header_when_supplied(self) -> None:
        captured: dict[str, str | None] = {}

        class Response:
            def __enter__(self) -> "Response":
                return self

            def __exit__(self, *_: object) -> None:
                return None

        def urlopen(request: object, timeout: float) -> Response:
            captured["header"] = request.get_header("X-vercel-protection-bypass")  # type: ignore[attr-defined]
            return Response()

        previous = os.environ.get("V0_VERCEL_PROTECTION_BYPASS")
        os.environ["V0_VERCEL_PROTECTION_BYPASS"] = "local-only-bypass-secret"
        try:
            with patch("scripts.v0.preflight.urllib.request.urlopen", side_effect=urlopen):
                self.assertTrue(_reachable("https://control.example.invalid"))
        finally:
            if previous is None:
                os.environ.pop("V0_VERCEL_PROTECTION_BYPASS", None)
            else:
                os.environ["V0_VERCEL_PROTECTION_BYPASS"] = previous

        self.assertEqual(captured["header"], "local-only-bypass-secret")


if __name__ == "__main__":
    unittest.main()
