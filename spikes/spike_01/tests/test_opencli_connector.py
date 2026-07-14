import json
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess

from spike_01.connectors import (
    ConnectorError,
    OpenCLIConnector,
    SubprocessOpenCLIInvoker,
)
from spike_01.model import SourceConfig


class FakeRunner:
    def __init__(self, *, version="opencli 1.2.3", fetch_output=None):
        self.version = version
        self.fetch_output = fetch_output
        self.calls = []

    def __call__(self, args, **kwargs):
        self.calls.append(list(args))
        if len(args) > 1 and args[1] == "--version":
            return CompletedProcess(args, 0, self.version + "\n", "")
        if self.fetch_output is None:
            return CompletedProcess(args, 0, "{}", "")
        return self.fetch_output(args)


def write_contract(directory):
    path = Path(directory) / "contract.json"
    path.write_text(
        json.dumps(
            {
                "executable": "opencli",
                "version": "opencli 1.2.3",
                "args_template": [
                    "discord",
                    "collect",
                    "--channel-url",
                    "{channel_url}",
                    "--profile-path",
                    "{profile_path}",
                    "--cursor",
                    "{cursor}",
                    "--format",
                    "json",
                ],
                "output_mode": "json_stdout",
            }
        )
    )
    return path


def page_payload():
    return {
        "page_id": "opencli-page-001",
        "source_container_id": "channel-real-001",
        "cursor_before": None,
        "cursor_after": "cursor-001",
        "messages": [
            {
                "id": "real-message-001",
                "author": {"id": "real-author-001", "name": "Local Test"},
                "channel_id": "channel-real-001",
                "published_at": "2026-01-01T08:00:00Z",
                "content": "machine readable output",
                "content_type": "text",
                "reply_to": None,
                "quote": None,
                "attachments": [],
                "source_url": "https://discord.example/real-message-001",
            }
        ],
    }


class OpenCLIConnectorTests(unittest.TestCase):
    def test_json_stdout_becomes_raw_page_and_omits_empty_cursor(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = FakeRunner(
                fetch_output=lambda args: CompletedProcess(
                    args,
                    0,
                    json.dumps(page_payload()),
                    "diagnostic stderr",
                )
            )
            invoker = SubprocessOpenCLIInvoker(
                Path(write_contract(directory)),
                runner=runner,
            )
            connector = OpenCLIConnector(invoker, source_account_id="local")
            page = next(
                connector.iter_pages(
                    SourceConfig(
                        "channel-real-001",
                        "https://discord.example/channel-real-001",
                        "local",
                        profile_path="/private/profile",
                    ),
                    None,
                )
            )
            self.assertEqual(page.page_id, "opencli-page-001")
            self.assertEqual(page.messages[0].payload["content"], "machine readable output")
            fetch_call = runner.calls[-1]
            self.assertNotIn("--cursor", fetch_call)
            self.assertNotIn("None", fetch_call)
            self.assertNotIn("diagnostic stderr", json.dumps(page.messages[0].payload))

    def test_nonzero_exit_is_connector_error(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = FakeRunner(
                fetch_output=lambda args: CompletedProcess(
                    args, 2, "", "permission denied"
                )
            )
            invoker = SubprocessOpenCLIInvoker(
                Path(write_contract(directory)),
                runner=runner,
            )
            with self.assertRaisesRegex(ConnectorError, "exit code 2"):
                invoker.fetch_page(
                    channel_url="https://discord.example/channel",
                    profile_path=Path("/private/profile"),
                    cursor=None,
                )

    def test_non_json_output_is_connector_error(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = FakeRunner(
                fetch_output=lambda args: CompletedProcess(
                    args, 0, "not json", ""
                )
            )
            invoker = SubprocessOpenCLIInvoker(
                Path(write_contract(directory)),
                runner=runner,
            )
            with self.assertRaisesRegex(ConnectorError, "invalid JSON"):
                invoker.fetch_page(
                    channel_url="https://discord.example/channel",
                    profile_path=Path("/private/profile"),
                    cursor=None,
                )

    def test_version_mismatch_stops_before_fetch(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = FakeRunner(version="opencli 9.9.9")
            invoker = SubprocessOpenCLIInvoker(
                Path(write_contract(directory)),
                runner=runner,
            )
            with self.assertRaisesRegex(ConnectorError, "version mismatch"):
                invoker.fetch_page(
                    channel_url="https://discord.example/channel",
                    profile_path=Path("/private/profile"),
                    cursor=None,
                )
            self.assertEqual(len(runner.calls), 1)


if __name__ == "__main__":
    unittest.main()
