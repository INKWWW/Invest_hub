from __future__ import annotations

import json
import subprocess
import unittest

from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.x_identity import (
    IdentityResolutionError,
    OpenCLIProfileInvoker,
    normalize_x_handle,
    resolve_configured_x_identity,
)


def completed_profile(screen_name: str) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(
        args=["fixture-opencli"],
        returncode=0,
        stdout=json.dumps([{"screen_name": screen_name}]),
        stderr="private stderr must not escape",
    )


def x_config() -> LocalWorkerConfig:
    return LocalWorkerConfig.from_mapping({
        "control_plane_url": "https://control.example.invalid",
        "source_id": "x-source",
        "source_type": "x",
        "source_url": "https://x.com/Fixture_Handle",
        "profile_ref": "/private/x-profile",
        "opencli_contract_version": "v2",
        "parameter_version": "v2-test",
    })


class RecordingProtocol:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str]] = []

    def resolve_x_source_identity(self, source_id: str, parameter_version: str, account_id: str) -> dict[str, object]:
        self.calls.append((source_id, parameter_version, account_id))
        return {"resolution_status": "resolved", "parameter_version": parameter_version, "idempotent": False}


class XIdentityTests(unittest.TestCase):
    def test_normalize_handle_strips_at_sign_and_lowercases(self) -> None:
        self.assertEqual(normalize_x_handle(" @Fixture_Handle "), "fixture_handle")
        for value in ("", "@", "too-long-handle-name", "not-valid", "two@@signs"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(IdentityResolutionError, "invalid_x_identity"):
                    normalize_x_handle(value)

    def test_profile_invoker_uses_only_profile_command_and_normalizes_result(self) -> None:
        calls: list[tuple[object, ...]] = []

        def runner(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
            calls.append((args, kwargs))
            return completed_profile("@FIXTURE_HANDLE")

        invoker = OpenCLIProfileInvoker("fixture-opencli", runner=runner)

        self.assertEqual(invoker.resolve("@Fixture_Handle"), "fixture_handle")
        self.assertEqual(calls, [(
            (["fixture-opencli", "twitter", "profile", "fixture_handle", "--site-session", "persistent", "-f", "json"],),
            {"capture_output": True, "text": True, "timeout": 60, "check": False},
        )])

    def test_profile_invoker_rejects_a_screen_name_different_from_requested_handle(self) -> None:
        invoker = OpenCLIProfileInvoker("fixture-opencli", runner=lambda *_a, **_k: completed_profile("other"))

        with self.assertRaisesRegex(IdentityResolutionError, "identity_mismatch"):
            invoker.resolve("fixture_handle")

    def test_profile_invoker_rejects_non_single_or_missing_profile_rows(self) -> None:
        invalid_payloads = ["{}", "[]", "[{}, {}]", "[{}]", "[{'screen_name': 'fixture_handle'}]"]
        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                invoker = OpenCLIProfileInvoker(
                    "fixture-opencli",
                    runner=lambda *_a, payload=payload, **_k: subprocess.CompletedProcess(
                        args=["fixture-opencli"], returncode=0, stdout=payload, stderr="private stderr",
                    ),
                )
                with self.assertRaisesRegex(IdentityResolutionError, "invalid_profile_response"):
                    invoker.resolve("fixture_handle")

    def test_profile_invoker_maps_subprocess_timeout_and_nonzero_to_safe_codes(self) -> None:
        timeout = OpenCLIProfileInvoker(
            "fixture-opencli",
            runner=lambda *_a, **_k: (_ for _ in ()).throw(subprocess.TimeoutExpired("profile", 60)),
        )
        with self.assertRaisesRegex(IdentityResolutionError, "profile_timeout"):
            timeout.resolve("fixture_handle")

        failed = OpenCLIProfileInvoker(
            "fixture-opencli",
            runner=lambda *_a, **_k: subprocess.CompletedProcess(
                args=["fixture-opencli"], returncode=1, stdout="", stderr="private stderr",
            ),
        )
        with self.assertRaisesRegex(IdentityResolutionError, "profile_invocation_failed"):
            failed.resolve("fixture_handle")

    def test_resolution_posts_only_normalized_identity_to_protocol(self) -> None:
        protocol = RecordingProtocol()

        result = resolve_configured_x_identity(
            x_config(), protocol, executable="fixture-opencli",
            invoker=OpenCLIProfileInvoker("fixture-opencli", runner=lambda *_a, **_k: completed_profile("fixture_handle")),
        )

        self.assertEqual(protocol.calls, [("x-source", "v2-test", "fixture_handle")])
        self.assertEqual(result["resolution_status"], "resolved")
        self.assertEqual(set(result), {"resolution_status", "parameter_version", "idempotent"})

    def test_resolution_rejects_non_x_config_without_protocol_call(self) -> None:
        config = x_config()
        config = LocalWorkerConfig(
            control_plane_url=config.control_plane_url, source_id=config.source_id, source_type="discord",
            source_url="https://discord.com/channels/a/b", profile_ref=config.profile_ref,
            opencli_contract_version=config.opencli_contract_version, parameter_version=config.parameter_version,
            config_hash=config.config_hash,
        )
        protocol = RecordingProtocol()
        with self.assertRaisesRegex(IdentityResolutionError, "source_not_x"):
            resolve_configured_x_identity(config, protocol, executable="fixture-opencli")
        self.assertEqual(protocol.calls, [])


if __name__ == "__main__":
    unittest.main()
