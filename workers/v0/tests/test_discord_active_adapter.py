from __future__ import annotations

import unittest

from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.discord_active_adapter import (
    ConnectorError,
    DiscordActiveAdapter,
    normalize_channel_url,
)


class FakeInvoker:
    def __init__(self, *responses: dict[str, object]) -> None:
        self.responses = list(responses)
        self.calls: list[dict[str, object]] = []

    def fetch_page(self, *, channel_url: str, profile_ref: str, cursor: str | None, cache_buster: str | None = None) -> dict[str, object]:
        self.calls.append({"channel_url": channel_url, "profile_ref": profile_ref, "cursor": cursor, "cache_buster": cache_buster})
        if not self.responses:
            raise AssertionError("unexpected page request")
        return self.responses.pop(0)


def source_config() -> LocalWorkerConfig:
    return LocalWorkerConfig.from_mapping({
        "control_plane_url": "https://control.example.invalid",
        "source_id": "source-1",
        "channel_url": "https://discord.com/channels/server/channel/message-deep-link",
        "profile_ref": "/private/profile",
        "opencli_contract_version": "v0",
        "parameter_version": "v0-default",
    })


def response(*, network: list[dict[str, object]], cursor_after: str | None = None) -> dict[str, object]:
    return {
        "page_id": "page-1",
        "expected_request_key": "request-1",
        "expected_request_url": "https://discord.com/api/v9/channels/channel/messages?limit=50",
        "network": network,
        "cursor_after": cursor_after,
    }


class DiscordActiveAdapterTests(unittest.TestCase):
    def test_deep_link_is_normalized_to_channel_root(self) -> None:
        self.assertEqual(
            normalize_channel_url("https://discord.com/channels/server/channel/message"),
            "https://discord.com/channels/server/channel",
        )

    def test_fresh_request_key_and_url_are_selected(self) -> None:
        invoker = FakeInvoker(
            response(network=[{
                "request_key": "request-1",
                "request_url": "https://discord.com/api/v9/channels/channel/messages?limit=50",
                "messages": [{"id": "message-1", "author": {"id": "author-1"}, "content": "hello"}],
            }], cursor_after="cursor-1"),
            response(network=[{
                "request_key": "request-1",
                "request_url": "https://discord.com/api/v9/channels/channel/messages?limit=50",
                "messages": [],
            }]),
        )
        pages = list(DiscordActiveAdapter(invoker).collect(source_config(), checkpoint=None))
        self.assertEqual(pages[0].messages[0]["id"], "message-1")
        self.assertEqual(pages[0].cursor_after, "cursor-1")
        self.assertEqual(invoker.calls[0]["channel_url"], "https://discord.com/channels/server/channel")

    def test_real_run_batch_stops_after_one_fresh_page(self) -> None:
        invoker = FakeInvoker(
            response(network=[{
                "request_key": "request-1",
                "request_url": "https://discord.com/api/v9/channels/channel/messages?limit=50",
                "messages": [{"id": "message-1", "content": "first"}],
            }], cursor_after="cursor-1"),
            response(network=[{
                "request_key": "request-1",
                "request_url": "https://discord.com/api/v9/channels/channel/messages?limit=50",
                "messages": [{"id": "message-2", "content": "second"}],
            }]),
        )

        pages = list(DiscordActiveAdapter(invoker).collect(source_config(), checkpoint=None))

        self.assertEqual(len(pages), 1)
        self.assertEqual(pages[0].cursor_after, "cursor-1")
        self.assertEqual(len(invoker.calls), 1)

    def test_missing_network_response_reopens_once_then_returns_typed_failure(self) -> None:
        invoker = FakeInvoker(response(network=[]), response(network=[]))
        with self.assertRaises(ConnectorError) as caught:
            list(DiscordActiveAdapter(invoker).collect(source_config(), checkpoint=None))
        self.assertEqual(caught.exception.code, "opencli_missing")
        self.assertEqual(len(invoker.calls), 2)
        self.assertIsNotNone(invoker.calls[1]["cache_buster"])

    def test_stale_response_is_retried_once_and_fresh_response_is_used(self) -> None:
        invoker = FakeInvoker(
            response(network=[{"request_key": "old", "request_url": "https://discord.com/api/v9/old", "messages": []}]),
            response(network=[{
                "request_key": "request-1",
                "request_url": "https://discord.com/api/v9/channels/channel/messages?limit=50",
                "messages": [{"id": "message-2", "content": "fresh"}],
            }]),
        )
        pages = list(DiscordActiveAdapter(invoker).collect(source_config(), checkpoint=None))
        self.assertEqual(pages[0].messages[0]["id"], "message-2")
        self.assertEqual(len(invoker.calls), 2)

    def test_page_hard_deadline_is_not_softened_by_retry(self) -> None:
        invoker = FakeInvoker(response(network=[]))
        with self.assertRaises(ConnectorError) as caught:
            list(DiscordActiveAdapter(invoker, page_timeout_seconds=0).collect(source_config(), checkpoint=None))
        self.assertEqual(caught.exception.code, "timeout")
        self.assertEqual(len(invoker.calls), 0)


if __name__ == "__main__":
    unittest.main()
