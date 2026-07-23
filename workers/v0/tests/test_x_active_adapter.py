from __future__ import annotations

import json
import unittest
from datetime import datetime, timezone
from pathlib import Path

from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import ConnectorError
from invest_hub_worker.connectors.x_active_adapter import XActiveAdapter


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
