from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from invest_hub_worker.providers.base import ProviderContext
from invest_hub_worker.providers.codex_cli import CodexCLIProvider
from invest_hub_worker.structured import SchemaError


VALID_OUTPUT = {"topics": [], "media_unparsed": False, "media_source_message_ids": [], "warnings": []}


class FakeStdin:
    def close(self) -> None:
        pass


class SuccessProcess:
    pid = 1234
    returncode = 0
    stdin = FakeStdin()

    def communicate(self, input: str, timeout: float) -> tuple[str, str]:
        del input, timeout
        return "", ""

    def wait(self, timeout: float) -> int:
        del timeout
        return 0


class TimeoutProcess:
    pid = 4321
    returncode = None
    stdin = FakeStdin()
    waited = False

    def communicate(self, input: str, timeout: float) -> tuple[str, str]:
        del input
        raise subprocess.TimeoutExpired("codex", timeout)

    def wait(self, timeout: float) -> int:
        del timeout
        self.waited = True
        return 0


class CodexProcessCleanupTests(unittest.TestCase):
    def test_v1_1_daily_operation_validates_the_configured_author_and_fact_evidence(self) -> None:
        context = ProviderContext(
            chunk_id="daily-1",
            prompt_version="v1.1",
            prompt_text="private prompt",
            operation="v1_1_daily",
            input_message_authors=(("message-1", "author-1", "Author One"),),
            configured_author_profiles=(("author-1", "Author One"),),
            expected_natural_date="2099-01-01",
            expected_as_of="2099-01-01T08:00:00Z",
        )
        output = {
            "schema_version": "v1.1",
            "natural_date": "2099-01-01",
            "as_of": "2099-01-01T08:00:00Z",
            "author_cards": [{
                "author_id": "author-1",
                "author_display": "Author One",
                "core_logic": {"market_trend": None, "stock_judgments": []},
                "operation_tendency": {"market": None, "stocks": None},
                "methodology": [],
                "uncertainty": [],
                "source_message_ids": ["message-1"],
            }],
            "topic_discussions": [],
            "warnings": [],
        }

        parsed = CodexCLIProvider._parse_for_context(json.dumps(output), (), context)

        self.assertEqual(parsed["author_cards"][0]["author_id"], "author-1")
        invalid = {**output, "author_cards": [{**output["author_cards"][0], "author_id": "author-2"}]}
        with self.assertRaises(SchemaError):
            CodexCLIProvider._parse_for_context(json.dumps(invalid), (), context)

    def test_success_uses_read_only_ephemeral_command_and_persists_raw_ref(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"
            captured: list[list[str]] = []

            def popen(command: list[str], **_kwargs: object) -> SuccessProcess:
                captured.append(command)
                output_path = Path(command[command.index("--output-last-message") + 1])
                output_path.write_text(json.dumps(VALID_OUTPUT), encoding="utf-8")
                return SuccessProcess()

            provider = CodexCLIProvider(evidence_dir=evidence, codex_home="/private/codex-home")
            with patch("invest_hub_worker.providers.codex_cli.subprocess.Popen", side_effect=popen):
                response = provider.complete(("message-1",), ProviderContext("chunk-1", "v0", "prompt"))
            self.assertEqual(response.status, "success")
            self.assertTrue(response.raw_ref)
            self.assertTrue(Path(response.raw_ref).exists())
            command = captured[0]
            self.assertIn("--sandbox", command)
            self.assertIn("read-only", command)
            self.assertIn("--ephemeral", command)
            self.assertIn("/private/codex-home", command)

    def test_timeout_kills_the_whole_process_group_without_unbounded_cleanup(self) -> None:
        process = TimeoutProcess()
        with tempfile.TemporaryDirectory() as directory:
            provider = CodexCLIProvider(evidence_dir=Path(directory) / "evidence", timeout_seconds=0.1)
            with patch("invest_hub_worker.providers.codex_cli.subprocess.Popen", return_value=process), patch(
                "invest_hub_worker.providers.codex_cli.os.killpg"
            ) as killpg:
                response = provider.complete(("message-1",), ProviderContext("chunk-1", "v0", "prompt"))
            self.assertEqual(response.status, "timeout")
            killpg.assert_called_once_with(process.pid, unittest.mock.ANY)
            self.assertTrue(process.waited)


if __name__ == "__main__":
    unittest.main()
