from __future__ import annotations

import json
import unittest
from datetime import datetime, timezone
from pathlib import Path

from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import ConnectorError
from invest_hub_worker.connectors.x_active_adapter import OpenCLITweetsInvoker, XActiveAdapter


class FakeXInvoker:
    def __init__(self, *responses: dict[str, object]) -> None:
        self.responses = list(responses)
        self.calls: list[dict[str, object]] = []

    def fetch_page(self, **kwargs: object) -> dict[str, object]:
        self.calls.append(kwargs)
        return self.responses.pop(0)


def source_config() -> LocalWorkerConfig:
    return LocalWorkerConfig.from_mapping({
        "control_plane_url": "https://control.example.invalid", "source_id": "x-source-1", "source_type": "x",
        "source_url": "https://x.com/fixture", "profile_ref": "/private/x-profile", "opencli_contract_version": "v2", "parameter_version": "v2-test",
    })


class XActiveAdapterTests(unittest.TestCase):
    def fixture(self) -> dict[str, object]:
        return json.loads((Path(__file__).parent / "fixtures" / "x_public_timeline_page.json").read_text())

    def test_fresh_page_preserves_an_opaque_cursor_and_all_post_types(self) -> None:
        invoker = FakeXInvoker(self.fixture())
        page = XActiveAdapter(invoker).fetch_page(source_config(), "fixture-cursor", end_at=datetime(2026, 7, 23, 8, tzinfo=timezone.utc))
        self.assertEqual(page.cursor_after, "fixture-cursor-next")
        self.assertEqual([post["post_type"] for post in page.messages], ["original", "quote", "reply", "repost"])
        self.assertNotIn("fixture", str(page.telemetry))
        self.assertEqual(invoker.calls[0]["cursor"], "fixture-cursor")

    def test_stale_response_retries_once_then_returns_a_classified_failure(self) -> None:
        stale = self.fixture()
        stale["network"] = [{"request_key": "old", "request_url": "https://x.com/i/api/graphql/old", "posts": []}]
        with self.assertRaises(ConnectorError) as caught:
            XActiveAdapter(FakeXInvoker(stale, stale)).fetch_page(source_config(), None)
        self.assertEqual(caught.exception.code, "opencli_stale")

    def test_missing_response_is_classified_without_a_fallback_collector(self) -> None:
        response = self.fixture()
        response["network"] = []
        with self.assertRaises(ConnectorError) as caught:
            XActiveAdapter(FakeXInvoker(response, response)).fetch_page(source_config(), None)
        self.assertEqual(caught.exception.code, "opencli_missing")

    def test_existing_opencli_tweets_capability_is_the_only_live_transport(self) -> None:
        commands: list[list[str]] = []

        class Result:
            returncode = 0
            stdout = json.dumps([{
                "id": "1", "author": "Fixture", "created_at": "2026-07-23T00:01:00Z", "text": "fixture",
                "url": "https://x.com/fixture/status/1", "is_retweet": False, "media_urls": [],
                "quoted_tweet": {"id": "2", "author": "Quoted", "text": "quoted", "url": "https://x.com/quoted/status/2"},
            }])

        def runner(command: list[str], **_kwargs: object) -> Result:
            commands.append(command)
            return Result()

        invoker = OpenCLITweetsInvoker("opencli", runner=runner)
        page = XActiveAdapter(invoker).fetch_page(source_config(), None, end_at=datetime(2026, 7, 23, 8, tzinfo=timezone.utc))

        self.assertEqual(commands[0][:4], ["opencli", "twitter", "tweets", "fixture"])
        self.assertEqual(page.messages[0]["post_type"], "quote")
        self.assertTrue(page.telemetry["history_exhausted"])
