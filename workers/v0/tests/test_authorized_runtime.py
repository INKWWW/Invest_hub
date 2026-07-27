from __future__ import annotations

import json
import multiprocessing
import stat
import tempfile
import threading
import time
import unittest
from pathlib import Path

from invest_hub_worker.canonical import CanonicalMessage, Canonicalizer
from invest_hub_worker.config import LocalWorkerConfig, LocalWorkerConfigSet
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.evidence import LocalEvidenceStore
from invest_hub_worker.providers.base import ProviderContext, ProviderResponse
from invest_hub_worker.runtime import AuthorizedDiscordRuntime, AuthorizedDiscordRuntimeSet, RuntimeExecutionError, build_authorized_runtime_set, build_dynamic_x_config


def _canonical_message(*, external_message_id: str = "message-1", content: str = "fixture content") -> CanonicalMessage:
    return CanonicalMessage(
        source_id="source-1",
        external_message_id=external_message_id,
        author_id="author-1",
        author_name="Author",
        occurred_at="2099-01-01T00:00:00Z",
        content=content,
        reply_to_message_id=None,
        quote=None,
        attachments=(),
    )


def _persist_same_canonical(root: str) -> None:
    LocalEvidenceStore(Path(root)).persist_canonical((_canonical_message(),))


def _write_unlocked_stale_fragment(path: str, opened: object, start: object, partial_written: object) -> None:
    with Path(path).open("a", encoding="utf-8") as stream:
        opened.set()
        if not start.wait(timeout=5):
            raise RuntimeError("stale writer did not receive start signal")
        stream.write('{"stale":')
        stream.flush()
        partial_written.set()
        time.sleep(0.5)
        stream.write('"writer"}\n')
        stream.flush()


class FakeConnector:
    def collect(
        self,
        _source: object,
        _checkpoint: str | None,
        *,
        max_pages: int = 1,
        collection_mode: str = "history",
    ):
        if max_pages < 1:
            raise AssertionError("invalid page limit")
        if collection_mode not in {"history", "incremental"}:
            raise AssertionError("invalid collection mode")
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
    def __init__(self) -> None:
        self.contexts: list[ProviderContext] = []

    def complete(self, _chunk: tuple[object, ...], context: ProviderContext) -> ProviderResponse:
        self.contexts.append(context)
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
    def test_dynamic_x_config_accepts_the_server_created_x_parameter_version(self) -> None:
        template = LocalWorkerConfig.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "source_id": "template-x",
            "source_type": "x",
            "source_url": "https://x.com/template",
            "profile_ref": "/private/profile",
            "opencli_contract_version": "v2",
            "parameter_version": "v2-x-collection-v1",
        })

        dynamic = build_dynamic_x_config(template, "new-source", {
            "source_type": "x", "account_id": "fixture_account", "display_name": "Fixture", "parameter_version": "x-standard-v2",
        })

        self.assertEqual(dynamic.source_id, "new-source")
        self.assertEqual(dynamic.parameter_version, "x-standard-v2")
        self.assertEqual(dynamic.source_url, "https://x.com/fixture_account")

    def test_production_runtime_builder_routes_an_unconfigured_x_source_to_dynamic_runtime(self) -> None:
        config = LocalWorkerConfigSet.from_mapping({
            "control_plane_url": "https://control.example.invalid",
            "sources": [{
                "source_id": "template-x", "source_type": "x", "source_url": "https://x.com/template",
                "profile_ref": "/private/profile", "opencli_contract_version": "v2",
                "parameter_version": "v2-x-collection-v1",
            }],
        })
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.md"
            prompt.write_text("private", encoding="utf-8")
            runtimes = build_authorized_runtime_set(
                config=config, evidence_dir=Path(directory) / "evidence", prompt_path=prompt,
                opencli_contract_path=Path(directory) / "unused.json", opencli_executable="/bin/echo",
            )
            runtime = runtimes._runtime_for({
                "source_id": "new-source",
                "source_snapshot": {
                    "source_type": "x", "account_id": "fixture_account", "display_name": "Fixture",
                    "parameter_version": "x-standard-v2",
                },
            })
        self.assertEqual(runtime.config.source_id, "new-source")
        self.assertEqual(runtime.config.parameter_version, "x-standard-v2")
    def test_local_evidence_store_reloads_a_record_with_a_unicode_line_separator(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "evidence"
            evidence = LocalEvidenceStore(root)
            message = _canonical_message(content="first\u2028second")

            self.assertEqual(evidence.persist_canonical((message,)), {"canonical_count": 1, "duplicate_count": 0})
            self.assertEqual(evidence.persist_canonical((message,)), {"canonical_count": 0, "duplicate_count": 1})

            payloads = [
                json.loads(row)
                for row in (root / "canonical" / "messages.jsonl").read_text(encoding="utf-8").split("\n")
                if row
            ]
            self.assertEqual([payload["content"] for payload in payloads], ["first\u2028second"])

    def test_local_evidence_store_escapes_unicode_line_separators_in_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "evidence"
            LocalEvidenceStore(root).persist_canonical((_canonical_message(content="first\u2028second"),))

            stored = (root / "canonical" / "messages.jsonl").read_text(encoding="utf-8")
            self.assertNotIn("\u2028", stored)
            self.assertIn("\\u2028", stored)

    def test_local_evidence_store_replaces_file_before_an_unlocked_stale_writer_completes(self) -> None:
        context = multiprocessing.get_context("fork")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "evidence"
            evidence = LocalEvidenceStore(root)
            evidence.persist_canonical((_canonical_message(),))
            target = root / "canonical" / "messages.jsonl"
            opened = context.Event()
            start = context.Event()
            partial_written = context.Event()
            stale_writer = context.Process(
                target=_write_unlocked_stale_fragment,
                args=(str(target), opened, start, partial_written),
            )
            stale_writer.start()
            self.assertTrue(opened.wait(timeout=5))

            original_existing_ids = LocalEvidenceStore._existing_ids

            def start_stale_writer_after_read(existing_target: Path) -> set[str]:
                existing = original_existing_ids(existing_target)
                start.set()
                self.assertTrue(partial_written.wait(timeout=5))
                return existing

            LocalEvidenceStore._existing_ids = staticmethod(start_stale_writer_after_read)
            try:
                evidence.persist_canonical((_canonical_message(external_message_id="message-2"),))
            finally:
                LocalEvidenceStore._existing_ids = staticmethod(original_existing_ids)
            stale_writer.join(timeout=5)
            self.assertEqual(stale_writer.exitcode, 0)

            rows = (root / "canonical" / "messages.jsonl").read_text(encoding="utf-8").splitlines()
            payloads = [json.loads(row) for row in rows]
            self.assertEqual({payload["external_message_id"] for payload in payloads}, {"message-1", "message-2"})

    def test_local_evidence_store_serializes_concurrent_duplicate_writes(self) -> None:
        context = multiprocessing.get_context("fork")
        barrier = context.Barrier(2)
        original_existing_ids = LocalEvidenceStore._existing_ids

        def synchronized_existing_ids(target: Path) -> set[str]:
            existing = original_existing_ids(target)
            try:
                barrier.wait(timeout=0.5)
            except threading.BrokenBarrierError:
                pass
            return existing

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "evidence"
            LocalEvidenceStore._existing_ids = staticmethod(synchronized_existing_ids)
            try:
                processes = [context.Process(target=_persist_same_canonical, args=(str(root),)) for _ in range(2)]
                for process in processes:
                    process.start()
                for process in processes:
                    process.join(timeout=5)
                self.assertEqual([process.exitcode for process in processes], [0, 0])
            finally:
                LocalEvidenceStore._existing_ids = staticmethod(original_existing_ids)

            rows = (root / "canonical" / "messages.jsonl").read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(rows), 1)
            self.assertEqual(json.loads(rows[0])["external_message_id"], "message-1")

    def test_local_evidence_store_restricts_directories_and_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "evidence"
            evidence = LocalEvidenceStore(root)
            evidence.persist_raw(
                RawPage(
                    page_id="page-1",
                    source_id="discord-source",
                    cursor_before=None,
                    cursor_after=None,
                    messages=(),
                    raw_payload_ref="local://discord/page-1",
                )
            )
            evidence.persist_canonical(())
            evidence.persist_validation({"status": "ok"})

            for directory_path in (root, *(root / name for name in ("raw", "canonical", "validation", "metrics"))):
                self.assertEqual(stat.S_IMODE(directory_path.stat().st_mode), 0o700)
            for file_path in (
                root / "raw" / "page-1.json",
                root / "canonical" / "messages.jsonl",
                root / "canonical" / "messages.lock",
                root / "validation" / "reports.jsonl",
            ):
                self.assertEqual(stat.S_IMODE(file_path.stat().st_mode), 0o600)

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
            "rule_snapshot": {"version": 2, "target_author_ids": ["author-1", "author-2"]},
            "collection_scope": {"mode": "incremental", "max_pages": 1},
        }
        with tempfile.TemporaryDirectory() as directory:
            provider = FakeProvider()
            runtime = AuthorizedDiscordRuntime(
                config=config,
                connector=FakeConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=provider,
                prompt_template="private prompt template",
            )

            bundle = runtime.execute(claim)

        payload = bundle["persistence"]
        self.assertEqual(bundle["result"]["raw_count"], 1)
        self.assertEqual(bundle["result"]["canonical_count"], 1)
        self.assertEqual(bundle["result"]["unparsed_media_count"], 1)
        self.assertEqual(payload["raw_messages"][0]["local_raw_ref"], "local://discord/page-1")
        self.assertEqual(payload["structured_runs"][0]["media_source_message_ids"], ["message-1"])
        self.assertEqual(payload["batch_summaries"][0]["natural_date"], "2099-01-01")
        self.assertNotIn("local://", str(payload["batch_summaries"]))
        self.assertEqual(provider.contexts[0].target_author_ids, frozenset({"author-1", "author-2"}))
        self.assertNotIn("profile_ref", str(payload))
        self.assertNotIn("private prompt template", str(payload))

    def test_missing_rule_snapshot_or_scope_is_a_preflight_failure(self) -> None:
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
        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=config,
                connector=FakeConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=FakeProvider(),
                prompt_template="private prompt template",
            )
            with self.assertRaises(RuntimeExecutionError) as caught:
                runtime.execute({
                    "task_id": "task-1",
                    "attempt": 1,
                    "source_id": "discord-source",
                    "parameter_version": "v0-test-1",
                    "safe_checkpoint": None,
                })

        self.assertEqual(caught.exception.failure_class, "preflight")

    def test_empty_incremental_page_preserves_the_safe_checkpoint(self) -> None:
        test_case = self

        class EmptyConnector:
            def collect(self, source: LocalWorkerConfig, checkpoint: str | None, *, max_pages: int, collection_mode: str):
                test_case.assertEqual(source.source_id, "discord-source")
                test_case.assertEqual(checkpoint, "checkpoint-1")
                test_case.assertEqual(max_pages, 1)
                test_case.assertEqual(collection_mode, "incremental")
                yield RawPage(
                    page_id="page-empty",
                    source_id="discord-source",
                    cursor_before="checkpoint-1",
                    cursor_after=None,
                    messages=(),
                    raw_payload_ref="local://discord/page-empty",
                )

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
            "safe_checkpoint": "checkpoint-1",
            "rule_snapshot": {"version": 2, "target_author_ids": []},
            "collection_scope": {"mode": "incremental", "max_pages": 1},
        }
        with tempfile.TemporaryDirectory() as directory:
            runtime = AuthorizedDiscordRuntime(
                config=config,
                connector=EmptyConnector(),
                evidence=LocalEvidenceStore(Path(directory) / "evidence"),
                canonicalizer=Canonicalizer(),
                provider=FakeProvider(),
                prompt_template="private prompt template",
            )
            bundle = runtime.execute(claim)

        self.assertEqual(bundle["result"]["safe_checkpoint"], "checkpoint-1")

    def test_runtime_set_routes_only_to_a_locally_authorized_source(self) -> None:
        class RecordingRuntime:
            def __init__(self) -> None:
                self.claims: list[dict[str, object]] = []

            def execute(self, claim: dict[str, object]) -> dict[str, object]:
                self.claims.append(claim)
                return {"source": "discord-source"}

        runtime = RecordingRuntime()
        runtime_set = AuthorizedDiscordRuntimeSet({"discord-source": runtime})  # type: ignore[arg-type]
        claim = {"source_id": "discord-source"}

        self.assertEqual(runtime_set.execute(claim), {"source": "discord-source"})
        self.assertEqual(runtime.claims, [claim])
        with self.assertRaises(RuntimeExecutionError) as caught:
            runtime_set.execute({"source_id": "not-configured"})
        self.assertEqual(caught.exception.failure_class, "unauthorized")


if __name__ == "__main__":
    unittest.main()
