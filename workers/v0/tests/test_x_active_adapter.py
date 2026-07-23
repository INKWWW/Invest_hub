from __future__ import annotations

import json
import unittest
from datetime import datetime, timezone
from pathlib import Path

from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import ConnectorError
from invest_hub_worker.connectors.x_active_adapter import OpenCLICollectionInvoker, XActiveAdapter


LOWER_BOUND = datetime(2026, 7, 22, 23, 30, tzinfo=timezone.utc)
END_AT = datetime(2026, 7, 23, 8, tzinfo=timezone.utc)


def source_config() -> LocalWorkerConfig:
    return LocalWorkerConfig.from_mapping({
        "control_plane_url": "https://control.example.invalid", "source_id": "x-source-1", "source_type": "x",
        "source_url": "https://x.com/fixture", "profile_ref": "/private/x-profile", "opencli_contract_version": "v2", "parameter_version": "v2-test",
    })


class FakeCollectionInvoker:
    def __init__(self, response: dict[str, object]) -> None:
        self.response = response
        self.calls: list[dict[str, object]] = []

    def fetch_page(self, **kwargs: object) -> dict[str, object]:
        self.calls.append(kwargs)
        return self.response


class XActiveAdapterTests(unittest.TestCase):
    def fixture(self, name: str) -> dict[str, object]:
        return json.loads((Path(__file__).parent / "fixtures" / name).read_text())

    def test_collection_command_requires_a_lower_time_boundary_and_returns_receipt_backed_posts(self) -> None:
        commands: list[list[str]] = []

        class Result:
            returncode = 0
            stdout = json.dumps(self.fixture("opencli_collection_success.json"))

        def runner(command: list[str], **_kwargs: object) -> Result:
            commands.append(command)
            return Result()

        invoker = OpenCLICollectionInvoker("dedicated-opencli", runner=runner)
        page = XActiveAdapter(invoker).fetch_page(source_config(), None, lower_bound_at=LOWER_BOUND, end_at=END_AT)

        self.assertEqual(commands[0][:4], ["dedicated-opencli", "twitter", "collection", "fixture"])
        self.assertIn("--until", commands[0])
        self.assertEqual(commands[0][commands[0].index("--until") + 1], "2026-07-22T23:30:00Z")
        self.assertNotIn("tweets", commands[0])
        self.assertEqual([post["post_type"] for post in page.messages], ["original", "quote", "reply", "repost"])
        self.assertEqual(page.messages[1]["quoted_post_id"], "quoted-1")
        self.assertEqual(page.messages[2]["reply_to_post_id"], "parent-1")
        self.assertEqual(page.messages[3]["text"], "")
        self.assertIsNone(page.cursor_after)
        self.assertTrue(page.telemetry["collection_receipt_verified"])
        self.assertEqual(page.telemetry["collection_stop_reason"], "time_boundary_reached")
        self.assertNotIn("fixture", str(page.telemetry))

    def test_incomplete_or_unknown_receipt_cannot_become_a_page(self) -> None:
        for response in (self.fixture("opencli_collection_incomplete.json"), {"posts": [], "receipt": {}}):
            with self.assertRaises(ConnectorError) as caught:
                XActiveAdapter(FakeCollectionInvoker(response)).fetch_page(
                    source_config(), None, lower_bound_at=LOWER_BOUND, end_at=END_AT,
                )
            self.assertEqual(caught.exception.code, "opencli_contract")

    def test_collection_rejects_a_receipt_for_a_different_lower_boundary(self) -> None:
        response = self.fixture("opencli_collection_success.json")
        response["receipt"]["requested_until"] = "2026-07-22T23:31:00.000Z"
        with self.assertRaises(ConnectorError) as caught:
            XActiveAdapter(FakeCollectionInvoker(response)).fetch_page(
                source_config(), None, lower_bound_at=LOWER_BOUND, end_at=END_AT,
            )
        self.assertEqual(caught.exception.code, "opencli_contract")

    def test_collection_refuses_a_resume_cursor_instead_of_falling_back_to_tweets(self) -> None:
        invoker = OpenCLICollectionInvoker("dedicated-opencli", runner=lambda *_args, **_kwargs: None)
        with self.assertRaises(ConnectorError) as caught:
            invoker.fetch_page(
                source_url="https://x.com/fixture", profile_ref="/private/x-profile", cursor="old-cursor",
                cache_buster=None, lower_bound_at=LOWER_BOUND, end_at=END_AT,
            )
        self.assertEqual(caught.exception.code, "opencli_contract")


if __name__ == "__main__":
    unittest.main()
