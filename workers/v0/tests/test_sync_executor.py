from __future__ import annotations

import unittest

from invest_hub_worker.canonical import Canonicalizer
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.sync_executor import SyncExecutor


PAGE = RawPage(
    page_id="page-1",
    source_id="source-1",
    cursor_before=None,
    cursor_after="cursor-1",
    messages=(
        {"id": "message-1", "author": {"id": "author-1", "name": "Author"}, "content": "hello"},
        {"id": "message-1", "author": {"id": "author-1", "name": "Author"}, "content": "duplicate"},
    ),
    raw_payload_ref="local://raw/page-1",
)


class FakeConnector:
    def __init__(self, pages: tuple[RawPage, ...] = (PAGE,)) -> None:
        self.pages = pages

    def collect(self, _source: object, checkpoint: str | None):
        del checkpoint
        yield from self.pages


class FakeEvidence:
    def __init__(self, *, fail_raw: bool = False, fail_canonical: bool = False) -> None:
        self.fail_raw = fail_raw
        self.fail_canonical = fail_canonical
        self.raw: list[str] = []
        self.canonical: list[object] = []

    def persist_raw(self, page: RawPage) -> None:
        if self.fail_raw:
            raise OSError("raw persistence failed")
        self.raw.append(page.page_id)

    def persist_canonical(self, messages: tuple[object, ...]) -> dict[str, int]:
        if self.fail_canonical:
            raise OSError("canonical persistence failed")
        self.canonical.extend(messages)
        return {"canonical_count": 1, "duplicate_count": 1}


class FakeProvider:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error

    def __call__(self, _messages: tuple[object, ...]) -> dict[str, object]:
        if self.error:
            raise self.error
        return {"structured_run_ids": []}


CLAIM = {
    "task_id": "task-1",
    "attempt": 1,
    "safe_checkpoint": None,
}


class SyncExecutorTests(unittest.TestCase):
    def executor(self, evidence: FakeEvidence, provider: FakeProvider | None = None, persistence_ack: str = "accepted") -> SyncExecutor:
        return SyncExecutor(
            connector=FakeConnector(),
            evidence=evidence,
            canonicalizer=Canonicalizer(),
            provider=provider or FakeProvider(),
            checkpoint_ack=lambda _result: persistence_ack,
        )

    def test_duplicate_messages_are_persisted_once_and_result_is_checkpoint_safe(self) -> None:
        evidence = FakeEvidence()
        result = self.executor(evidence).execute(CLAIM, object())
        self.assertEqual(result.status, "succeeded")
        self.assertEqual(result.duplicate_count, 1)
        self.assertEqual(result.safe_checkpoint, "cursor-1")

    def test_raw_persistence_failure_does_not_advance_checkpoint(self) -> None:
        result = self.executor(FakeEvidence(fail_raw=True)).execute(CLAIM, object())
        self.assertEqual(result.status, "retryable_failed")
        self.assertIsNone(result.safe_checkpoint)
        self.assertEqual(result.failure_class, "persistence_failure")

    def test_canonical_persistence_failure_does_not_advance_checkpoint(self) -> None:
        result = self.executor(FakeEvidence(fail_canonical=True)).execute(CLAIM, object())
        self.assertEqual(result.status, "retryable_failed")
        self.assertIsNone(result.safe_checkpoint)

    def test_provider_failure_does_not_advance_checkpoint(self) -> None:
        result = self.executor(FakeEvidence(), FakeProvider(RuntimeError("provider failed"))).execute(CLAIM, object())
        self.assertEqual(result.status, "retryable_failed")
        self.assertIsNone(result.safe_checkpoint)
        self.assertEqual(result.failure_class, "provider_failure")

    def test_cloud_persistence_ack_is_required_before_checkpoint(self) -> None:
        result = self.executor(FakeEvidence(), persistence_ack="pending").execute(CLAIM, object())
        self.assertEqual(result.status, "retryable_failed")
        self.assertIsNone(result.safe_checkpoint)

    def test_unknown_reply_is_unresolved_but_keeps_message_evidence(self) -> None:
        page = RawPage(
            page_id="page-reply",
            source_id="source-1",
            cursor_before=None,
            cursor_after="cursor-reply",
            messages=(
                {
                    "id": "message-reply",
                    "author": {"id": "author-1", "name": "Author"},
                    "content": "reply",
                    "reply_to": {"id": "message-not-in-page"},
                },
            ),
            raw_payload_ref="local://raw/page-reply",
        )
        result = SyncExecutor(
            connector=FakeConnector((page,)),
            evidence=FakeEvidence(),
            canonicalizer=Canonicalizer(),
            provider=FakeProvider(),
            checkpoint_ack=lambda _result: "accepted",
        ).execute(CLAIM, object())
        self.assertEqual(result.status, "succeeded")
        self.assertEqual(result.unresolved_count, 1)


if __name__ == "__main__":
    unittest.main()
