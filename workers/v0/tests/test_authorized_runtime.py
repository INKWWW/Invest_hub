from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from invest_hub_worker.canonical import Canonicalizer
from invest_hub_worker.config import LocalWorkerConfig
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.evidence import LocalEvidenceStore
from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
from invest_hub_worker.runtime import AuthorizedDiscordRuntime


class FakeConnector:
    def collect(self, _source: object, _checkpoint: str | None):
        yield RawPage(
            page_id="page-1",
            source_id="discord-source",
            cursor_before=None,
            cursor_after="message-1",
            messages=(
                {
                    "id": "message-1",
                    "published_at": "2099-01-01T00:00:00Z",
                    "author": {"id": "author-1", "name": "Author"},
                    "content": "fixture content",
                    "attachments": [{"name": "unparsed.pdf"}],
                },
            ),
            raw_payload_ref="local://discord/page-1",
        )


class FakeProvider:
    def complete(self, _chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
        return ProviderResponse(
            status="success",
            provider="codex_cli",
            model_reported=None,
            prompt_version=context.prompt_version,
            elapsed_ms=3,
            attempt=context.attempt,
            raw_ref=None,
            parsed_output_ref=None,
            parsed_output={
                "topics": [],
                "media_unparsed": True,
                "media_source_message_ids": ["message-1"],
                "warnings": ["附件未解析"],
            },
        )


class AuthorizedRuntimeTests(unittest.TestCase):
    def test_execution_bundle_keeps_private_paths_local_and_is_ready_for_remote_persistence(self) -> None:
        config = LocalWorkerConfig.from_mapping(
            {
                "control_plane_url": "https://control.example.invalid",
                "source_id": "discord-source",
                "channel_url": "https://discord.com/channels/1/2",
                "profile_ref": "/private/profile",
                "opencli_contract_version": "v0",
                "parameter_version": "v0-test-1",
            }
        )
        claim = {
            "task_id": "task-1",
            "attempt": 1,
            "source_id": "discord-source",
            "parameter_version": "v0-test-1",
            "safe_checkpoint": None,
        }
        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=config,
                connector=FakeConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=FakeProvider(),
                prompt_template="private prompt template",
            )

            bundle = runtime.execute(claim)

        payload = bundle["persistence"]
        self.assertEqual(bundle["result"]["raw_count"], 1)
        self.assertEqual(bundle["result"]["canonical_count"], 1)
        self.assertEqual(bundle["result"]["unparsed_media_count"], 1)
        self.assertEqual(payload["raw_messages"][0]["local_raw_ref"], "local://discord/page-1")
        self.assertEqual(payload["structured_runs"][0]["media_source_message_ids"], ["message-1"])
        self.assertNotIn("profile_ref", str(payload))
        self.assertNotIn("private prompt template", str(payload))


if __name__ == "__main__":
    unittest.main()
