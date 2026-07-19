import json
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess, TimeoutExpired

from spike_01.connectors import (
    BrowserBridgeOpenCLIInvoker,
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


def write_browser_contract(directory, *, version="1.8.6"):
    path = Path(directory) / "browser-contract.json"
    path.write_text(
        json.dumps(
            {
                "executable": "opencli",
                "version": version,
                "mode": "browser_bridge_discord_network",
                "browser_session": "spike01",
                "cache_buster_param": "opencli_spike_run",
                "wait_seconds": 0,
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

    def test_browser_bridge_filters_around_overlap_and_builds_raw_page(self):
        with tempfile.TemporaryDirectory() as directory:
            network = {
                "entries": [
                    {
                        "key": "GET discord.com/api/v9/channels/123/messages",
                        "status": 200,
                        "url": "https://discord.com/api/v9/channels/123/messages?limit=30&around=200",
                    }
                ]
            }
            detail = {
                "body": json.dumps(
                    [
                        {"id": "300", "channel_id": "123"},
                        {"id": "200", "channel_id": "123"},
                        {
                            "id": "100",
                            "channel_id": "123",
                            "content": "body",
                            "timestamp": "2026-07-15T00:00:00.000Z",
                            "author": {
                                "id": "author-100",
                                "username": "user",
                                "global_name": "Display",
                            },
                            "message_reference": {
                                "message_id": "90",
                                "channel_id": "123",
                            },
                            "referenced_message": {
                                "id": "90",
                                "content": "quoted",
                            },
                            "attachments": [
                                {
                                    "filename": "report.pdf",
                                    "content_type": "application/pdf",
                                    "url": "https://cdn.example/report.pdf",
                                }
                            ],
                        },
                    ]
                )
            }

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] == "wait":
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "open":
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "network" and "--detail" in args:
                            return CompletedProcess(args, 0, json.dumps(detail), "")
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [] if self.network_calls == 1 else network["entries"]
                            return CompletedProcess(
                                args,
                                0,
                                json.dumps({"entries": entries}),
                                "",
                            )
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if "--detail" in args:
                        return CompletedProcess(args, 0, json.dumps(detail), "")
                    return CompletedProcess(args, 0, "{}", "")

            runner = BrowserRunner()
            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=runner,
            )
            payload = invoker.fetch_page(
                channel_url="https://discord.com/channels/1/123",
                profile_path=Path("browser-bridge:spike01"),
                cursor="200",
            )

            self.assertEqual(payload["source_container_id"], "123")
            self.assertEqual([item["id"] for item in payload["messages"]], ["100"])
            self.assertEqual(payload["cursor_after"], "100")
            mapped = payload["messages"][0]
            self.assertEqual(mapped["author"]["name"], "Display")
            self.assertEqual(mapped["published_at"], "2026-07-15T00:00:00.000Z")
            self.assertEqual(mapped["reply_to"], {"id": "90"})
            self.assertEqual(
                mapped["quote"],
                {"id": "90", "content": "quoted", "resolved": True},
            )
            self.assertEqual(mapped["attachments"][0]["name"], "report.pdf")
            self.assertEqual(mapped["source_url"], "https://discord.com/channels/1/123/100")
            self.assertEqual(mapped["_discord_raw"]["id"], "100")
            self.assertIn(
                "/channels/1/123/200",
                " ".join(" ".join(call) for call in runner.calls),
            )

    def test_browser_bridge_requires_discord_message_network_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            class BrowserRunner(FakeRunner):
                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[3] == "network":
                        return CompletedProcess(args, 0, json.dumps({"entries": []}), "")
                    return CompletedProcess(args, 0, "{}", "")

            runner = BrowserRunner()
            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=runner,
            )
            with self.assertRaisesRegex(ConnectorError, "message network entry"):
                invoker.fetch_page(
                    channel_url="https://discord.com/channels/1/123",
                    profile_path=Path("browser-bridge:spike01"),
                    cursor=None,
                )

    def test_browser_bridge_reopens_once_after_missing_network_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            fresh = {
                "key": "GET discord.com/api/v9/channels/123/messages?around=200&fresh=2",
                "status": 200,
                "url": "https://discord.com/api/v9/channels/123/messages?limit=30&around=200&fresh=2",
            }
            detail = {
                "body": json.dumps(
                    [
                        {
                            "id": "100",
                            "channel_id": "123",
                            "content": "reopened body",
                            "timestamp": "2026-07-15T00:00:00.000Z",
                            "author": {"id": "author-100", "username": "user"},
                        }
                    ]
                )
            }

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.open_calls = 0
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] == "open":
                            self.open_calls += 1
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "wait":
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "network" and "--detail" in args:
                            return CompletedProcess(args, 0, json.dumps(detail), "")
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [fresh] if self.network_calls >= 3 else []
                            return CompletedProcess(
                                args,
                                0,
                                json.dumps({"entries": entries}),
                                "",
                            )
                    return CompletedProcess(args, 0, "{}", "")

            runner = BrowserRunner()
            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=runner,
            )
            payload = invoker.fetch_page(
                channel_url="https://discord.com/channels/1/123",
                profile_path=Path("browser-bridge:spike01"),
                cursor="200",
            )

            self.assertEqual(payload["messages"][0]["id"], "100")
            open_calls = [
                call for call in runner.calls if len(call) > 3 and call[3] == "open"
            ]
            self.assertEqual(len(open_calls), 2)
            self.assertNotEqual(open_calls[0][4], open_calls[1][4])

    def test_browser_bridge_ignores_stale_entry_and_matches_current_cursor(self):
        with tempfile.TemporaryDirectory() as directory:
            stale = {
                "key": "GET discord.com/api/v9/channels/123/messages",
                "status": 200,
                "url": "https://discord.com/api/v9/channels/123/messages?limit=30&around=200",
            }
            fresh = {
                "key": "GET discord.com/api/v9/channels/123/messages",
                "status": 200,
                "url": "https://discord.com/api/v9/channels/123/messages?limit=30&around=200&fresh=1",
            }
            detail = {
                "body": json.dumps(
                    [
                        {
                            "id": "100",
                            "channel_id": "123",
                            "content": "fresh body",
                            "timestamp": "2026-07-15T00:00:00.000Z",
                            "author": {"id": "author-100", "username": "user"},
                        }
                    ]
                )
            }

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] in {"open", "wait"}:
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "network" and "--detail" in args:
                            return CompletedProcess(args, 0, json.dumps(detail), "")
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [stale]
                            if self.network_calls >= 3:
                                entries = [stale, fresh]
                            return CompletedProcess(
                                args,
                                0,
                                json.dumps({"entries": entries}),
                                "",
                            )
                    return CompletedProcess(args, 0, "{}", "")

            runner = BrowserRunner()
            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=runner,
            )
            payload = invoker.fetch_page(
                channel_url="https://discord.com/channels/1/123",
                profile_path=Path("browser-bridge:spike01"),
                cursor="200",
            )

            self.assertEqual(payload["messages"][0]["id"], "100")
            self.assertEqual(payload["_telemetry"]["match_state"], "matched_new")
            self.assertGreaterEqual(payload["_telemetry"]["network_attempts"], 2)
            self.assertTrue(
                any(
                    call[3:5] == ["network", "--all"]
                    for call in runner.calls
                )
            )

    def test_browser_bridge_rejects_response_for_wrong_cursor(self):
        with tempfile.TemporaryDirectory() as directory:
            wrong = {
                "key": "GET discord.com/api/v9/channels/123/messages?around=999",
                "status": 200,
                "url": "https://discord.com/api/v9/channels/123/messages?limit=30&around=999",
            }

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [] if self.network_calls == 1 else [wrong]
                            return CompletedProcess(
                                args,
                                0,
                                json.dumps({"entries": entries}),
                                "",
                            )
                        return CompletedProcess(args, 0, "{}", "")
                    return CompletedProcess(args, 0, "{}", "")

            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=BrowserRunner(),
            )
            with self.assertRaisesRegex(ConnectorError, "cursor"):
                invoker.fetch_page(
                    channel_url="https://discord.com/channels/1/123",
                    profile_path=Path("browser-bridge:spike01"),
                    cursor="200",
                )

    def test_browser_bridge_rejects_fresh_after_cursor_response(self):
        with tempfile.TemporaryDirectory() as directory:
            fresh = {
                "key": "GET discord.com/api/v9/channels/123/messages?after=200&fresh=1",
                "status": 200,
                "url": "https://discord.com/api/v9/channels/123/messages?limit=30&after=200&fresh=1",
            }

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [] if self.network_calls == 1 else [fresh]
                            return CompletedProcess(
                                args, 0, json.dumps({"entries": entries}), ""
                            )
                        return CompletedProcess(args, 0, "{}", "")
                    return CompletedProcess(args, 0, "{}", "")

            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)), runner=BrowserRunner()
            )
            with self.assertRaises(ConnectorError) as raised:
                invoker.fetch_page(
                    channel_url="https://discord.com/channels/1/123",
                    profile_path=Path("browser-bridge:spike01"),
                    cursor="200",
                )
            self.assertEqual(raised.exception.code, "cursor_not_advanced")

    def test_browser_bridge_rejects_nonadvancing_fresh_around_response(self):
        with tempfile.TemporaryDirectory() as directory:
            fresh = {
                "key": "GET discord.com/api/v9/channels/123/messages?around=200&fresh=1",
                "status": 200,
                "url": "https://discord.com/api/v9/channels/123/messages?limit=30&around=200&fresh=1",
            }
            detail = {"body": json.dumps([{"id": "300"}, {"id": "200"}])}

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] in {"open", "wait"}:
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "network" and "--detail" in args:
                            return CompletedProcess(args, 0, json.dumps(detail), "")
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [] if self.network_calls == 1 else [fresh]
                            return CompletedProcess(
                                args, 0, json.dumps({"entries": entries}), ""
                            )
                    return CompletedProcess(args, 0, "{}", "")

            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)), runner=BrowserRunner()
            )
            with self.assertRaises(ConnectorError) as raised:
                invoker.fetch_page(
                    channel_url="https://discord.com/channels/1/123",
                    profile_path=Path("browser-bridge:spike01"),
                    cursor="200",
                )
            self.assertEqual(raised.exception.code, "cursor_not_advanced")

    def test_browser_bridge_treats_a_fresh_empty_cursor_response_as_history_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            fresh = {
                "key": "GET discord.com/api/v9/channels/123/messages?before=100&fresh=1",
                "status": 200,
                "url": "https://discord.com/api/v9/channels/123/messages?limit=30&before=100&fresh=1",
            }
            detail = {"body": "[]"}

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] in {"open", "wait"}:
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "network" and "--detail" in args:
                            return CompletedProcess(args, 0, json.dumps(detail), "")
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [] if self.network_calls == 1 else [fresh]
                            return CompletedProcess(args, 0, json.dumps({"entries": entries}), "")
                    return CompletedProcess(args, 0, "{}", "")

            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=BrowserRunner(),
            )

            payload = invoker.fetch_page(
                channel_url="https://discord.com/channels/1/123",
                profile_path=Path("browser-bridge:spike01"),
                cursor="100",
            )

            self.assertEqual(payload["messages"], [])
            self.assertIsNone(payload["cursor_after"])
            self.assertEqual(payload["_telemetry"]["match_state"], "matched_new")

    def test_browser_bridge_converts_subprocess_timeout_to_typed_error(self):
        with tempfile.TemporaryDirectory() as directory:
            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"] and args[3] == "network":
                        raise TimeoutExpired(args, 1)
                    return CompletedProcess(args, 0, "{}", "")

            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=BrowserRunner(),
                page_timeout_seconds=1,
            )
            with self.assertRaisesRegex(ConnectorError, "timed out"):
                invoker.fetch_page(
                    channel_url="https://discord.com/channels/1/123",
                    profile_path=Path("browser-bridge:spike01"),
                    cursor=None,
                )

    def test_browser_bridge_normalizes_message_deep_link_before_pagination(self):
        with tempfile.TemporaryDirectory() as directory:
            network = {
                "entries": [
                    {
                        "key": "GET discord.com/api/v9/channels/123/messages?around=200&fresh=1",
                        "status": 200,
                        "url": "https://discord.com/api/v9/channels/123/messages?limit=30&around=200&fresh=1",
                    }
                ]
            }
            detail = {
                "body": json.dumps(
                    [
                        {
                            "id": "100",
                            "channel_id": "123",
                            "content": "body",
                            "timestamp": "2026-07-15T00:00:00.000Z",
                            "author": {"id": "author-100", "username": "user"},
                        }
                    ]
                )
            }

            class BrowserRunner(FakeRunner):
                def __init__(self):
                    super().__init__(version="1.8.6")
                    self.network_calls = 0

                def __call__(self, args, **kwargs):
                    self.calls.append(list(args))
                    if args[1] == "--version":
                        return CompletedProcess(args, 0, "1.8.6\n", "")
                    if args[1:3] == ["browser", "spike01"]:
                        if args[3] == "open":
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "wait":
                            return CompletedProcess(args, 0, "{}", "")
                        if args[3] == "network" and "--detail" in args:
                            return CompletedProcess(args, 0, json.dumps(detail), "")
                        if args[3] == "network":
                            self.network_calls += 1
                            entries = [] if self.network_calls == 1 else network["entries"]
                            return CompletedProcess(
                                args,
                                0,
                                json.dumps({"entries": entries}),
                                "",
                            )
                    return CompletedProcess(args, 0, "{}", "")

            runner = BrowserRunner()
            invoker = BrowserBridgeOpenCLIInvoker(
                Path(write_browser_contract(directory)),
                runner=runner,
            )
            invoker.fetch_page(
                channel_url="https://discord.com/channels/1/123/999",
                profile_path=Path("browser-bridge:spike01"),
                cursor="200",
            )
            open_calls = [
                call for call in runner.calls if len(call) > 3 and call[3] == "open"
            ]
            self.assertEqual(
                open_calls[-1][4].split("?", 1)[0],
                "https://discord.com/channels/1/123/200",
            )
            self.assertIn("opencli_spike_run=", open_calls[-1][4])


if __name__ == "__main__":
    unittest.main()
