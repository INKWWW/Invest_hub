from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from invest_hub_worker.config import ConfigError, LocalWorkerConfig


class LocalWorkerConfigTests(unittest.TestCase):
    def write_config(self, directory: str, payload: object, suffix: str = ".json") -> Path:
        path = Path(directory) / f"worker{suffix}"
        if suffix == ".toml":
            path.write_text(
                "\n".join(f'{key} = "{value}"' for key, value in payload.items()),
                encoding="utf-8",
            )
        else:
            path.write_text(json.dumps(payload), encoding="utf-8")
        os.chmod(path, 0o600)
        return path

    def valid_payload(self) -> dict[str, str]:
        return {
            "control_plane_url": "https://control.example.invalid",
            "source_id": "discord-source-1",
            "channel_url": "https://discord.com/channels/server/channel",
            "profile_ref": "/private/worker-profile",
            "opencli_contract_version": "2026-07-15",
            "parameter_version": "v0-default",
        }

    def test_owner_only_json_loads_and_redaction_does_not_expose_private_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = LocalWorkerConfig.load(self.write_config(directory, self.valid_payload()))
            self.assertEqual(config.source_id, "discord-source-1")
            redacted = config.redacted()
            self.assertEqual(redacted["source_id"], "discord-source-1")
            self.assertNotIn("control.example.invalid", json.dumps(redacted))
            self.assertNotIn("worker-profile", json.dumps(redacted))
            self.assertRegex(redacted["config_hash"], r"^[0-9a-f]{64}$")

    def test_group_or_other_permissions_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(directory, self.valid_payload())
            os.chmod(path, 0o640)
            with self.assertRaises(ConfigError):
                LocalWorkerConfig.load(path)

    def test_missing_field_and_unknown_field_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            payload = self.valid_payload()
            payload.pop("profile_ref")
            with self.assertRaises(ConfigError):
                LocalWorkerConfig.load(self.write_config(directory, payload))

            payload = self.valid_payload()
            payload["unexpected"] = "value"
            with self.assertRaises(ConfigError):
                LocalWorkerConfig.load(self.write_config(directory, payload))

    def test_toml_is_supported_with_the_same_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = LocalWorkerConfig.load(self.write_config(directory, self.valid_payload(), suffix=".toml"))
            self.assertEqual(config.parameter_version, "v0-default")


if __name__ == "__main__":
    unittest.main()
