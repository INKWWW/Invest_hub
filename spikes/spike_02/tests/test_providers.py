import json
import os
import stat
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

from spike_02.model import Chunk, LLMRequest
from spike_02.providers import CodexCLIProvider, MockOutcome, MockProvider


VALID_JSON = '{"topics":[],"media_unparsed":false,"media_source_message_ids":[],"warnings":[]}'


def request_for(chunk_id="case-0000"):
    chunk = Chunk(
        chunk_id=chunk_id,
        case_id="case",
        index=0,
        primary_message_ids=("public-001",),
        context_message_ids=(),
        prompt_text="prompt",
        input_chars=6,
        prompt_lines=("primary\tpublic-001",),
    )
    return LLMRequest("run-001", chunk, attempt=1, prompt_version="test-v1")


class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def write_fake_codex(self, body: str) -> str:
        path = self.root / f"fake-codex-{len(list(self.root.iterdir()))}.py"
        path.write_text(
            "#!/usr/bin/env python3\n" + textwrap.dedent(body),
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return str(path)

    def write_fake_exit(self, code: int) -> str:
        return self.write_fake_codex(f"import sys\nsys.exit({code})\n")

    def write_fake_no_output(self) -> str:
        return self.write_fake_codex("import sys\nsys.stdin.read()\n")

    def write_fake_sleep(self, seconds: float) -> str:
        return self.write_fake_codex(
            f"import time\ntime.sleep({seconds})\n"
        )

    def write_fake_child_that_holds_pipes(self) -> str:
        return self.write_fake_codex(
            """
            import os
            import pathlib
            import subprocess
            import sys
            import time
            child = subprocess.Popen(
                [
                    sys.executable,
                    '-c',
                    'import time; time.sleep(5)',
                ],
                close_fds=False,
            )
            pathlib.Path(os.environ['CHILD_PID_PATH']).write_text(str(child.pid))
            time.sleep(5)
            """
        )

    def write_fake_exit_with_stderr(self) -> str:
        return self.write_fake_codex(
            "import sys\nsys.stderr.write('secret-prompt')\nsys.exit(7)\n"
        )

    def test_mock_returns_scripted_json_and_counts_calls(self):
        provider = MockProvider({"case-0000": [MockOutcome.success(VALID_JSON)]})
        response = provider.complete(request_for("case-0000"))
        self.assertEqual(response.status, "success")
        self.assertEqual(provider.call_count, 1)
        self.assertEqual(provider.calls_for("case-0000"), 1)

    def test_mock_can_inject_timeout_then_success(self):
        provider = MockProvider(
            {
                "case-0000": [
                    MockOutcome.failure("timeout"),
                    MockOutcome.success(VALID_JSON),
                ]
            }
        )
        self.assertEqual(provider.complete(request_for("case-0000")).status, "timeout")
        self.assertEqual(provider.complete(request_for("case-0000")).status, "success")

    def test_codex_success_reads_final_message_and_sends_prompt_on_stdin(self):
        binary = self.write_fake_codex(
            """
            import pathlib
            import sys
            payload = sys.stdin.read()
            if "prompt" not in payload:
                sys.exit(9)
            output_path = sys.argv[sys.argv.index("--output-last-message") + 1]
            pathlib.Path(output_path).write_text(
                '{"topics":[],"media_unparsed":false,"media_source_message_ids":[],"warnings":[]}'
            )
            """
        )
        response = CodexCLIProvider(binary=binary, cwd=str(self.root)).complete(request_for())
        self.assertEqual(response.status, "success")
        self.assertEqual(response.process_exit_code, 0)
        self.assertIn('"topics"', response.content)

    def test_codex_includes_read_only_ephemeral_output_flags(self):
        capture_path = self.root / "argv.json"
        binary = self.write_fake_codex(
            """
            import json
            import os
            import sys
            pathlib = __import__("pathlib")
            pathlib.Path(os.environ["CODEX_ARGV_CAPTURE"]).write_text(
                json.dumps(sys.argv[1:])
            )
            """
        )
        old = os.environ.get("CODEX_ARGV_CAPTURE")
        os.environ["CODEX_ARGV_CAPTURE"] = str(capture_path)
        try:
            CodexCLIProvider(
                binary=binary,
                model="test-model",
                codex_home=str(self.root / "codex-home"),
                cwd=str(self.root),
            ).complete(request_for())
        finally:
            if old is None:
                os.environ.pop("CODEX_ARGV_CAPTURE", None)
            else:
                os.environ["CODEX_ARGV_CAPTURE"] = old
        args = json.loads(capture_path.read_text())
        self.assertEqual(args[:2], ["exec", "--sandbox"])
        self.assertIn("read-only", args)
        self.assertIn("--add-dir", args)
        self.assertIn(str(self.root / "codex-home"), args)
        self.assertIn("--ephemeral", args)
        self.assertIn("--output-last-message", args)
        self.assertIn("--model", args)
        self.assertIn("-", args)

    def test_codex_maps_nonzero_exit_to_provider_failed_without_business_output(self):
        response = CodexCLIProvider(
            binary=self.write_fake_exit(7),
            cwd=str(self.root),
        ).complete(request_for())
        self.assertEqual(response.status, "provider_failed")
        self.assertEqual(response.process_exit_code, 7)
        self.assertIsNone(response.content)

    def test_codex_maps_missing_final_message_to_empty_response(self):
        response = CodexCLIProvider(
            binary=self.write_fake_no_output(),
            cwd=str(self.root),
        ).complete(request_for())
        self.assertEqual(response.status, "empty_response")

    def test_codex_timeout_terminates_process(self):
        response = CodexCLIProvider(
            binary=self.write_fake_sleep(2),
            timeout_seconds=0.05,
            cwd=str(self.root),
        ).complete(request_for())
        self.assertEqual(response.status, "timeout")

    def test_codex_timeout_does_not_wait_for_descendant_pipe_cleanup(self):
        child_pid_path = self.root / "child.pid"
        old = os.environ.get("CHILD_PID_PATH")
        os.environ["CHILD_PID_PATH"] = str(child_pid_path)
        started = time.monotonic()
        try:
            response = CodexCLIProvider(
                binary=self.write_fake_child_that_holds_pipes(),
                timeout_seconds=2.0,
                cwd=str(self.root),
            ).complete(request_for())
        finally:
            if old is None:
                os.environ.pop("CHILD_PID_PATH", None)
            else:
                os.environ["CHILD_PID_PATH"] = old
        elapsed = time.monotonic() - started
        self.assertEqual(response.status, "timeout")
        self.assertLess(elapsed, 3.0)
        child_pid = int(child_pid_path.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)

    def test_codex_does_not_expose_command_diagnostics_as_content(self):
        response = CodexCLIProvider(
            binary=self.write_fake_exit_with_stderr(),
            cwd=str(self.root),
        ).complete(request_for())
        self.assertIsNone(response.content)
        self.assertNotIn("secret-prompt", response.content or "")


if __name__ == "__main__":
    unittest.main()
