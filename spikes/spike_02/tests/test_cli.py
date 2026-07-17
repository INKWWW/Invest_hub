import os
import json
import stat
import tempfile
import textwrap
import unittest
from pathlib import Path

from spike_02.chunking import build_chunks
from spike_02.cli import main
from spike_02.fixtures import load_fixture


FIXTURE_PATH = "spikes/spike_02/fixtures/public_small.json"


class CLITests(unittest.TestCase):
    def test_mock_cli_requires_fixture_and_evidence_dir(self):
        self.assertEqual(main(["mock"]), 2)

    def test_glm_command_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(main(["glm", "--evidence-dir", directory]), 2)

    def test_codex_cli_uses_binary_and_optional_model_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = self._write_fake_codex(directory)
            old_binary = os.environ.get("SPIKE02_CODEX_BIN")
            old_model = os.environ.get("SPIKE02_CODEX_MODEL")
            os.environ["SPIKE02_CODEX_BIN"] = binary
            os.environ["SPIKE02_CODEX_MODEL"] = "test-model"
            try:
                code = main(
                    [
                        "codex",
                        "--fixture",
                        FIXTURE_PATH,
                        "--evidence-dir",
                        directory,
                        "--max-attempts",
                        "1",
                    ]
                )
            finally:
                if old_binary is None:
                    os.environ.pop("SPIKE02_CODEX_BIN", None)
                else:
                    os.environ["SPIKE02_CODEX_BIN"] = old_binary
                if old_model is None:
                    os.environ.pop("SPIKE02_CODEX_MODEL", None)
                else:
                    os.environ["SPIKE02_CODEX_MODEL"] = old_model
            self.assertEqual(code, 0)

    def test_cli_records_concurrency_telemetry(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = self._write_fake_codex(directory)
            old_binary = os.environ.get("SPIKE02_CODEX_BIN")
            os.environ["SPIKE02_CODEX_BIN"] = binary
            try:
                code = main(
                    [
                        "codex",
                        "--fixture",
                        FIXTURE_PATH,
                        "--evidence-dir",
                        directory,
                        "--max-attempts",
                        "1",
                        "--max-concurrency",
                        "2",
                    ]
                )
            finally:
                if old_binary is None:
                    os.environ.pop("SPIKE02_CODEX_BIN", None)
                else:
                    os.environ["SPIKE02_CODEX_BIN"] = old_binary
            self.assertEqual(code, 0)
            metrics = json.loads((Path(directory) / "metrics.json").read_text())
            self.assertEqual(metrics["max_concurrency"], 2)
            self.assertIn("batch_elapsed_ms", metrics)
            self.assertIn("max_active_requests", metrics)

            with tempfile.TemporaryDirectory() as default_directory:
                default_code = main(
                    [
                        "codex",
                        "--fixture",
                        FIXTURE_PATH,
                        "--evidence-dir",
                        default_directory,
                        "--max-attempts",
                        "1",
                    ]
                )
                self.assertEqual(default_code, 0)
                default_metrics = json.loads(
                    (Path(default_directory) / "metrics.json").read_text()
                )
                self.assertEqual(default_metrics["max_concurrency"], 1)

    def test_cli_rejects_non_positive_concurrency(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(
                main(
                    [
                        "mock",
                        "--fixture",
                        FIXTURE_PATH,
                        "--evidence-dir",
                        directory,
                        "--max-concurrency",
                        "0",
                    ]
                ),
                2,
            )

    def test_chunk_prompt_forbids_tools_and_requires_json(self):
        case = load_fixture(Path(FIXTURE_PATH))
        chunk = build_chunks(case, max_primary_messages=3)[0]
        self.assertIn("Do not use tools", chunk.prompt_text)
        self.assertIn("JSON", chunk.prompt_text)
        self.assertIn("source_message_ids", chunk.prompt_text)
        self.assertIn("target-analyst", chunk.prompt_text)
        self.assertIn("unparsed_media", build_chunks(case, max_primary_messages=12)[0].prompt_text)

    def test_mock_cli_runs_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            code = main(
                [
                    "mock",
                    "--fixture",
                    FIXTURE_PATH,
                    "--evidence-dir",
                    directory,
                    "--chunk-size",
                    "3",
                ]
            )
            self.assertEqual(code, 0)
            self.assertTrue((Path(directory) / "metrics.json").exists())

    def _write_fake_codex(self, directory: str) -> str:
        path = Path(directory) / "fake-codex.py"
        path.write_text(
            textwrap.dedent(
                """
                #!/usr/bin/env python3
                import pathlib
                import sys
                output_path = sys.argv[sys.argv.index("--output-last-message") + 1]
                pathlib.Path(output_path).write_text(
                    '{"topics":[],"media_unparsed":false,"warnings":[]}'
                )
                """
            ).lstrip(),
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return str(path)


if __name__ == "__main__":
    unittest.main()
