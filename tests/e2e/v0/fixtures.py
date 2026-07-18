from __future__ import annotations

import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from invest_hub_worker.canonical import CanonicalMessage, Canonicalizer
from invest_hub_worker.connectors.base import RawPage
from invest_hub_worker.providers.base import ProviderContext
from invest_hub_worker.providers.mock import MockOutcome, MockProvider
from invest_hub_worker.protocol import WorkerProtocol
from invest_hub_worker.retry import RetryPolicy
from invest_hub_worker.structured import SchemaError, validate_structured_output
from invest_hub_worker.worker import Worker


class FixturePersistenceError(RuntimeError):
    pass


class LeaseExpiredError(RuntimeError):
    pass


def public_discord_page() -> RawPage:
    return RawPage(
        page_id="fixture-page-1",
        source_id="discord-source-1",
        cursor_before=None,
        cursor_after="cursor-1",
        raw_payload_ref="local://fixture/raw/page-1",
        messages=(
            {
                "id": "message-1",
                "author": {"id": "author-1", "name": "Public Author"},
                "published_at": "2026-07-18T12:00:00Z",
                "content": "Public fixture message one.",
            },
            {
                "id": "message-2",
                "author": {"id": "author-1", "name": "Public Author"},
                "published_at": "2026-07-18T12:01:00Z",
                "content": "Public fixture message with an unresolved reply and media metadata.",
                "reply_to": {"id": "message-outside-page"},
                "attachments": [{"kind": "image", "url": "https://cdn.example.invalid/fixture-image.png"}],
            },
        ),
    )


class FixtureConnector:
    def __init__(self, page: RawPage | None = None) -> None:
        self.page = page or public_discord_page()

    def collect(self, _source: object, checkpoint: str | None):
        if checkpoint == self.page.cursor_after:
            return iter(())
        return iter((self.page,))


class InMemoryEvidence:
    def __init__(self, failure_stage: str | None = None) -> None:
        self.failure_stage = failure_stage
        self.raw: dict[str, RawPage] = {}
        self.canonical: dict[tuple[str, str], CanonicalMessage] = {}
        self.structured: dict[str, dict[str, Any]] = {}

    def persist_raw(self, page: RawPage) -> None:
        if self.failure_stage == "raw":
            raise FixturePersistenceError("raw persistence injected failure")
        self.raw[page.page_id] = page

    def persist_canonical(self, messages: tuple[CanonicalMessage, ...]) -> dict[str, int]:
        if self.failure_stage == "canonical":
            raise FixturePersistenceError("canonical persistence injected failure")
        canonical_count = 0
        duplicate_count = 0
        for message in messages:
            key = (message.source_id, message.external_message_id)
            if key in self.canonical:
                duplicate_count += 1
            else:
                self.canonical[key] = message
                canonical_count += 1
        return {"canonical_count": canonical_count, "duplicate_count": duplicate_count}


class InMemoryControlPlane:
    """A public, deterministic transport double for the V0 HTTP contract."""

    def __init__(self) -> None:
        self.users = {"admin-1": "admin", "user-1": "user"}
        self.invites: dict[str, dict[str, Any]] = {}
        self.workers: dict[str, dict[str, Any]] = {}
        self.tasks: dict[str, dict[str, Any]] = {}
        self.checkpoints: dict[str, str | None] = {"discord-source-1": None}
        self.events: list[dict[str, Any]] = []
        self.structured_runs: dict[str, dict[str, Any]] = {}
        self.evidence_refs: dict[str, dict[str, Any]] = {}
        self._worker_number = 0
        self._task_number = 0

    def create_invite(self, created_by: str, *, purpose: str) -> str:
        if self.users.get(created_by) != "admin":
            raise PermissionError("admin_required")
        if purpose not in {"user", "worker"}:
            raise ValueError("invalid_purpose")
        code = "fixture-enrolment-code" if purpose == "worker" else "fixture-user-code"
        self.invites[code] = {"purpose": purpose, "created_by": created_by, "consumed": False}
        return code

    def consume_user_invite(self, code: str, user_id: str) -> bool:
        invite = self.invites.get(code)
        if not invite or invite["purpose"] != "user" or invite["consumed"]:
            return False
        invite["consumed"] = True
        self.users[user_id] = "user"
        return True

    def enrol_worker(self, code: str, name: str) -> dict[str, str]:
        invite = self.invites.get(code)
        if not invite or invite["purpose"] != "worker" or invite["consumed"]:
            raise ValueError("invite_replayed")
        invite["consumed"] = True
        self._worker_number += 1
        worker_id = f"worker-{self._worker_number}"
        secret = f"fixture-device-secret-{self._worker_number}-012345678901234567890123"
        self.workers[worker_id] = {"id": worker_id, "name": name, "secret": secret, "status": "enrolled"}
        return {
            "contract_version": "v0",
            "worker_id": worker_id,
            "device_secret": secret,
            "expires_at": "2099-01-01T00:00:00Z",
        }

    def create_task(self, source_id: str) -> str:
        self._task_number += 1
        task_id = f"task-{self._task_number}"
        self.tasks[task_id] = {
            "task_id": task_id,
            "source_id": source_id,
            "status": "queued",
            "attempt": 0,
            "worker_id": None,
            "lease_expires_at": None,
            "checkpoint": self.checkpoints.get(source_id),
            "raw_count": 0,
            "canonical_count": 0,
            "duplicate_count": 0,
            "unresolved_count": 0,
            "unparsed_media_count": 0,
            "structured_run_ids": [],
        }
        return task_id

    def requeue(self, task_id: str) -> None:
        task = self.tasks[task_id]
        task.update({"status": "queued", "worker_id": None, "lease_expires_at": None})

    def expire_lease(self, task_id: str) -> None:
        self.tasks[task_id]["lease_expires_at"] = "2000-01-01T00:00:00Z"

    def list_tasks(self, user_id: str) -> list[dict[str, Any]]:
        if self.users.get(user_id) != "admin":
            raise PermissionError("forbidden")
        return [dict(task) for task in self.tasks.values()]

    def list_workers(self, user_id: str) -> list[dict[str, Any]]:
        if self.users.get(user_id) != "admin":
            raise PermissionError("forbidden")
        return [{key: value for key, value in worker.items() if key != "secret"} for worker in self.workers.values()]

    def transport(
        self,
        method: str,
        url: str,
        body: object | None,
        headers: dict[str, str],
        _timeout: float,
    ) -> tuple[int, object | None]:
        del method
        path = urlparse(url).path
        payload = body if isinstance(body, dict) else {}
        if path == "/api/worker/enrol":
            try:
                return 201, self.enrol_worker(str(payload.get("code", "")), str(payload.get("name", "fixture-worker")))
            except ValueError as exc:
                return 409, {"error": str(exc)}

        worker = self._worker_from_headers(headers)
        if worker is None:
            return 401, {"error": "unauthorized"}
        if path == "/api/worker/heartbeat":
            if payload.get("worker_id") != worker["id"]:
                return 403, {"error": "worker_mismatch"}
            worker["status"] = "online"
            return 200, {"worker_id": worker["id"], "status": "online", "heartbeat_interval_seconds": 60}
        if path == "/api/worker/tasks/claim":
            return self._claim(worker["id"])
        parts = [part for part in path.split("/") if part]
        if len(parts) >= 5 and parts[0:3] == ["api", "worker", "tasks"]:
            task_id = parts[3]
            action = parts[4]
            if action == "result":
                return self._result(task_id, worker["id"], payload)
            if action == "failure":
                return self._failure(task_id, worker["id"], payload)
            if action == "events":
                self.events.append(dict(payload))
                return 200, {"status": "accepted"}
            if action == "lease":
                return self._renew(task_id, worker["id"])
        return 404, {"error": "not_found"}

    def accept_result(self, task_id: str, worker_id: str, result: dict[str, Any]) -> dict[str, Any]:
        status, value = self._result(task_id, worker_id, result)
        if status >= 400:
            raise LeaseExpiredError(str(value))
        return dict(value or {})

    def _worker_from_headers(self, headers: dict[str, str]) -> dict[str, Any] | None:
        authorization = headers.get("Authorization", "")
        secret = authorization.removeprefix("Bearer ")
        return next((worker for worker in self.workers.values() if worker["secret"] == secret), None)

    def _claim(self, worker_id: str) -> tuple[int, object | None]:
        for task in self.tasks.values():
            if task["status"] != "queued":
                continue
            task["attempt"] += 1
            task["status"] = "leased"
            task["worker_id"] = worker_id
            task["lease_expires_at"] = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()
            return 200, {
                "contract_version": "v0",
                "task_id": task["task_id"],
                "attempt": task["attempt"],
                "task_type": "discord_sync",
                "source_id": task["source_id"],
                "parameter_version": "v0-default",
                "lease_expires_at": task["lease_expires_at"],
                "safe_checkpoint": self.checkpoints.get(task["source_id"]),
            }
        return 204, None

    def _result(self, task_id: str, worker_id: str, result: dict[str, Any]) -> tuple[int, object | None]:
        task = self.tasks.get(task_id)
        if not task or task["worker_id"] != worker_id or task["attempt"] != result.get("attempt"):
            return 409, {"error": "lease_mismatch"}
        if task["lease_expires_at"] and _expired(task["lease_expires_at"]):
            return 409, {"error": "lease_mismatch"}
        if task["status"] == "succeeded":
            return 200, {"status": "succeeded", "idempotent": True}
        if result.get("status") != "succeeded":
            return 422, {"error": "invalid_task_result"}
        task.update(
            {
                "status": "succeeded",
                "checkpoint": result.get("safe_checkpoint"),
                "lease_expires_at": None,
                "raw_count": result.get("raw_count", 0),
                "canonical_count": result.get("canonical_count", 0),
                "duplicate_count": result.get("duplicate_count", 0),
                "unresolved_count": result.get("unresolved_count", 0),
                "unparsed_media_count": result.get("unparsed_media_count", 0),
                "structured_run_ids": list(result.get("structured_run_ids", [])),
            }
        )
        self.checkpoints[task["source_id"]] = result.get("safe_checkpoint")
        self.events.append({"task_id": task_id, "event_type": "succeeded", "attempt": task["attempt"]})
        return 200, {"status": "succeeded", "idempotent": False}

    def _failure(self, task_id: str, worker_id: str, failure: dict[str, Any]) -> tuple[int, object | None]:
        task = self.tasks.get(task_id)
        if not task or task["worker_id"] != worker_id:
            return 409, {"error": "lease_mismatch"}
        task["status"] = str(failure.get("status", "failed"))
        task["lease_expires_at"] = None
        self.events.append({"task_id": task_id, "event_type": "failed", "failure_class": failure.get("failure_class")})
        return 200, {"status": task["status"]}

    def _renew(self, task_id: str, worker_id: str) -> tuple[int, object | None]:
        task = self.tasks.get(task_id)
        if not task or task["worker_id"] != worker_id or task["status"] not in {"leased", "running"}:
            return 409, {"error": "lease_mismatch"}
        task["lease_expires_at"] = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()
        task["status"] = "running"
        return 200, {"task_id": task_id, "attempt": task["attempt"], "lease_expires_at": task["lease_expires_at"]}


@dataclass
class FixtureExecution:
    control: InMemoryControlPlane
    failure_stage: str | None = None
    worker_id: str | None = None
    calls: int = 0

    def __post_init__(self) -> None:
        self.connector = FixtureConnector()
        self.evidence = InMemoryEvidence(self.failure_stage)

    def execute(self, claim: dict[str, Any]) -> dict[str, Any]:
        return self.prepare(claim)

    def prepare(self, claim: dict[str, Any]) -> dict[str, Any]:
        self.calls += 1
        previous = claim.get("safe_checkpoint")
        raw_count = canonical_count = duplicate_count = unresolved_count = 0
        unparsed_media_count = 0
        all_messages: list[CanonicalMessage] = []
        try:
            for page in self.connector.collect(claim["source_id"], previous):
                raw_count += len(page.messages)
                self.evidence.failure_stage = self.failure_stage
                self.evidence.persist_raw(page)
                mapped = Canonicalizer().map(page)
                persisted = self.evidence.persist_canonical(mapped)
                canonical_count += persisted["canonical_count"]
                duplicate_count += persisted["duplicate_count"]
                unresolved_count += sum(1 for message in mapped if message.unresolved)
                unparsed_media_count += sum(1 for message in mapped if message.attachments)
                all_messages.extend(mapped)
        except FixturePersistenceError:
            return _failure_result(claim, "persistence_failure")

        if not all_messages:
            return _success_result(claim, previous, 0, 0, 0, 0, 0, [])

        input_ids = {message.external_message_id for message in all_messages}
        media_ids = {message.external_message_id for message in all_messages if message.attachments}
        output = {
            "topics": [],
            "media_unparsed": bool(media_ids),
            "media_source_message_ids": sorted(media_ids),
            "warnings": ["media not parsed"] if media_ids else [],
        }
        provider_outcome = MockOutcome.provider_failure() if self.failure_stage == "provider" else MockOutcome.success(output)
        provider = MockProvider({"fixture-chunk": [provider_outcome]})
        response = RetryPolicy(max_attempts=1).execute(
            provider,
            tuple(all_messages),
            ProviderContext(
                chunk_id="fixture-chunk",
                prompt_version="prompt-v0",
                prompt_text="fixture prompt must not enter cloud result",
                input_message_ids=frozenset(input_ids),
                unparsed_media_message_ids=frozenset(media_ids),
            ),
        )
        if response.status != "success" or response.parsed_output is None:
            return _failure_result(claim, response.failure_class or response.status)
        try:
            validate_structured_output(response.parsed_output, input_ids, media_ids)
        except SchemaError:
            return _failure_result(claim, "schema_error")

        run_id = f"structured-{claim['task_id']}-{claim['attempt']}"
        self.evidence.structured[run_id] = {"provider": response.provider, "prompt_version": response.prompt_version}
        self.control.structured_runs[run_id] = {"task_id": claim["task_id"], "provider": response.provider}
        self.control.evidence_refs[run_id] = {
            "canonical_message_ids": sorted(input_ids),
            "media_source_message_ids": sorted(media_ids),
            "raw_page_refs": [self.connector.page.raw_payload_ref],
        }
        return _success_result(
            claim,
            "cursor-1",
            raw_count,
            canonical_count,
            duplicate_count,
            unresolved_count,
            unparsed_media_count,
            [run_id],
        )


def build_fixture_worker(
    control: InMemoryControlPlane,
    *,
    failure_stage: str | None = None,
) -> tuple[Worker, WorkerProtocol, FixtureExecution]:
    control.create_invite("admin-1", purpose="worker")
    credential_path = Path(tempfile.mkdtemp(prefix="invest-hub-v0-e2e-")) / "credentials.json"
    protocol = WorkerProtocol(
        "https://control.example.invalid",
        credential_path,
        transport=control.transport,
        worker_name="fixture-worker",
    )
    credential = protocol.enrol("fixture-enrolment-code")
    setattr(protocol, "credential_path", credential_path)
    execution = FixtureExecution(control, failure_stage=failure_stage, worker_id=credential.worker_id)
    worker = Worker(protocol, execute=execution.execute)
    return worker, protocol, execution


def run_fixture_sync(
    control: InMemoryControlPlane,
    execution: FixtureExecution,
    claim: dict[str, Any] | None,
) -> dict[str, Any]:
    if claim is None:
        return {"status": "retryable_failed", "safe_checkpoint": None, "failure_class": "no_claim"}
    result = execution.prepare(claim)
    if result["status"] != "succeeded":
        return result
    try:
        control.accept_result(claim["task_id"], execution.worker_id or "", result)
    except LeaseExpiredError:
        return _failure_result(claim, "lease_expired")
    return result


def _success_result(
    claim: dict[str, Any],
    checkpoint: str | None,
    raw_count: int,
    canonical_count: int,
    duplicate_count: int,
    unresolved_count: int,
    unparsed_media_count: int,
    structured_run_ids: list[str],
) -> dict[str, Any]:
    return {
        "contract_version": "v0",
        "task_id": claim["task_id"],
        "attempt": claim["attempt"],
        "status": "succeeded",
        "safe_checkpoint": checkpoint,
        "raw_count": raw_count,
        "canonical_count": canonical_count,
        "duplicate_count": duplicate_count,
        "unresolved_count": unresolved_count,
        "unparsed_media_count": unparsed_media_count,
        "structured_run_ids": structured_run_ids,
        "telemetry": {"elapsed_ms": 1, "retry_count": 0, "failure_class": None},
    }


def _failure_result(claim: dict[str, Any], failure_class: str) -> dict[str, Any]:
    return {
        "status": "retryable_failed",
        "task_id": claim["task_id"],
        "attempt": claim["attempt"],
        "safe_checkpoint": claim.get("safe_checkpoint"),
        "failure_class": failure_class,
    }


def _expired(value: str) -> bool:
    return datetime.fromisoformat(value.replace("Z", "+00:00")) <= datetime.now(timezone.utc)
