from __future__ import annotations

import json
import os
import re
import stat
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urljoin

from .contracts import ContractError, load_contract
from .errors import AlreadyEnrolled, ProtocolError, RemoteConflict
from .heartbeat import build_heartbeat


Transport = Callable[[str, str, object | None, dict[str, str], float], tuple[int, object | None]]


@dataclass(frozen=True)
class DeviceCredential:
    contract_version: str
    worker_id: str
    device_secret: str
    expires_at: str


class CredentialStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    def save(self, credential: DeviceCredential) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        fd = os.open(self.path, flags, 0o600)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(asdict(credential), stream, sort_keys=True)
                stream.write("\n")
        except Exception:
            try:
                os.close(fd)
            except OSError:
                pass
            raise

    def load(self) -> DeviceCredential | None:
        if not self.path.exists():
            return None
        if stat.S_IMODE(self.path.stat().st_mode) & 0o077:
            raise ProtocolError("credential store must be owner-only")
        try:
            value = json.loads(self.path.read_text(encoding="utf-8"))
            return DeviceCredential(**load_contract("worker-enrolment", value))
        except (OSError, ValueError, TypeError, KeyError) as exc:
            raise ProtocolError("invalid credential store") from exc


class WorkerProtocol:
    def __init__(
        self,
        base_url: str,
        credential_path: Path,
        *,
        transport: Transport | None = None,
        timeout: float = 30.0,
        worker_name: str = "v0-worker",
    ) -> None:
        self.base_url = base_url.rstrip("/") + "/"
        self.store = CredentialStore(credential_path)
        self.transport = transport or self._urllib_transport
        self.timeout = timeout
        self.worker_name = worker_name

    @property
    def credential(self) -> DeviceCredential | None:
        return self.store.load()

    def enrol(self, code: str) -> DeviceCredential:
        if self.credential is not None:
            raise AlreadyEnrolled("worker already has a device credential")
        status, value = self._request("POST", "api/worker/enrol", {"code": code, "name": self.worker_name}, authenticated=False)
        if status not in {200, 201}:
            raise ProtocolError(f"enrolment failed with status {status}")
        try:
            credential = DeviceCredential(**load_contract("worker-enrolment", value))
        except (ContractError, TypeError, KeyError) as exc:
            raise ProtocolError("invalid enrolment response") from exc
        self.store.save(credential)
        return credential

    def heartbeat(self, status: str, capabilities: list[str], sent_at: str) -> dict[str, Any]:
        credential = self._require_credential()
        payload = build_heartbeat(credential.worker_id, status, capabilities, sent_at)
        _, value = self._request("POST", "api/worker/heartbeat", payload)
        return self._object(value, "invalid heartbeat response")

    def claim(self) -> dict[str, Any] | None:
        self._require_credential()
        status, value = self._request("POST", "api/worker/tasks/claim", {"contract_version": "v0"})
        if status == 204 or value is None:
            return None
        try:
            return load_contract("task-claim", value)
        except ContractError as exc:
            raise ProtocolError("invalid task claim response") from exc

    def schedule_tick(self) -> dict[str, Any]:
        self._require_credential()
        _, value = self._request("POST", "api/worker/schedule/tick", {})
        return self._object(value, "invalid schedule tick response")

    def claim_x_daily_judgement(self) -> dict[str, Any] | None:
        self._require_credential()
        status, value = self._request("POST", "api/worker/x-daily-judgements/claim", {})
        if status == 204 or value is None:
            return None
        return _parse_x_daily_judgement_claim(self._object(value, "invalid x daily judgement claim"))

    def get_x_daily_judgement_context(self, run_id: str, attempt: int) -> dict[str, Any]:
        self._require_credential()
        _validate_x_daily_judgement_identity(run_id, attempt, "context")
        _, value = self._request("POST", f"api/worker/x-daily-judgements/{run_id}/context", {"attempt": attempt})
        return _parse_x_daily_judgement_context(self._object(value, "invalid x daily judgement context"), run_id, attempt)

    def complete_x_daily_judgement(self, completion: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        _validate_x_daily_judgement_completion(completion)
        run_id = str(completion["run_id"])
        _, value = self._request("POST", f"api/worker/x-daily-judgements/{run_id}/complete", completion)
        acknowledgement = self._object(value, "invalid x daily judgement completion acknowledgement")
        if acknowledgement.get("status") != "succeeded":
            raise ProtocolError("x daily judgement completion was not acknowledged")
        return acknowledgement

    def fail_x_daily_judgement(self, run_id: str, attempt: int, failure_class: str) -> dict[str, Any]:
        self._require_credential()
        _validate_x_daily_judgement_identity(run_id, attempt, "failure")
        if failure_class not in {"timeout", "provider_failure", "empty_response", "invalid_json", "schema_error", "persistence_failure"}:
            raise ProtocolError("invalid x daily judgement failure")
        _, value = self._request(
            "POST", f"api/worker/x-daily-judgements/{run_id}/failure",
            {"attempt": attempt, "failure_class": failure_class},
        )
        return self._object(value, "invalid x daily judgement failure acknowledgement")

    def claim_x_v3_verification_replay(self, replay_id: str) -> dict[str, Any] | None:
        self._require_credential()
        _validate_x_v3_verification_identity(replay_id, 1, "claim")
        status, value = self._request("POST", f"api/worker/x-v3-verification-replays/{replay_id}/claim", {})
        if status == 204 or value is None:
            return None
        response = self._object(value, "invalid x v3 verification replay claim")
        if set(response) != {"replay_id", "attempt", "lease_expires_at"} or response.get("replay_id") != replay_id or response.get("attempt") != 1 or not _non_empty_string(response.get("lease_expires_at")):
            raise ProtocolError("invalid x v3 verification replay claim")
        return response

    def get_x_v3_verification_replay_context(self, replay_id: str, attempt: int) -> dict[str, Any]:
        self._require_credential()
        _validate_x_v3_verification_identity(replay_id, attempt, "context")
        _, value = self._request("POST", f"api/worker/x-v3-verification-replays/{replay_id}/context", {"attempt": attempt})
        return _parse_x_v3_verification_replay_context(self._object(value, "invalid x v3 verification replay context"), replay_id, attempt)

    def complete_x_v3_verification_replay(self, completion: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        _validate_x_v3_verification_replay_completion(completion)
        replay_id = str(completion["replay_id"])
        _, value = self._request("POST", f"api/worker/x-v3-verification-replays/{replay_id}/complete", completion)
        acknowledgement = self._object(value, "invalid x v3 verification replay completion acknowledgement")
        if acknowledgement.get("status") != "succeeded":
            raise ProtocolError("x v3 verification replay completion was not acknowledged")
        return acknowledgement

    def fail_x_v3_verification_replay(self, replay_id: str, attempt: int, failure_class: str) -> dict[str, Any]:
        self._require_credential()
        _validate_x_v3_verification_identity(replay_id, attempt, "failure")
        if failure_class not in {"timeout", "provider_failure", "empty_response", "invalid_json", "schema_error", "persistence_failure"}:
            raise ProtocolError("invalid x v3 verification replay failure")
        _, value = self._request("POST", f"api/worker/x-v3-verification-replays/{replay_id}/failure", {"attempt": attempt, "failure_class": failure_class})
        return self._object(value, "invalid x v3 verification replay failure acknowledgement")

    def claim_x_v3_verification_acceptance_run(self, acceptance_run_id: str) -> dict[str, Any] | None:
        self._require_credential(); _validate_x_v3_verification_identity(acceptance_run_id, 1, "claim")
        status, value = self._request("POST", f"api/worker/x-v3-verification-acceptance-runs/{acceptance_run_id}/claim", {})
        if status == 204 or value is None: return None
        response = self._object(value, "invalid x v3 verification acceptance claim")
        if set(response) != {"acceptance_run_id", "attempt", "lease_expires_at"} or response.get("acceptance_run_id") != acceptance_run_id or response.get("attempt") != 1 or not _non_empty_string(response.get("lease_expires_at")): raise ProtocolError("invalid x v3 verification acceptance claim")
        return {"replay_id": acceptance_run_id, "attempt": 1, "lease_expires_at": response["lease_expires_at"]}

    def get_x_v3_verification_acceptance_context(self, acceptance_run_id: str, attempt: int) -> dict[str, Any]:
        self._require_credential(); _validate_x_v3_verification_identity(acceptance_run_id, attempt, "context")
        _, value = self._request("POST", f"api/worker/x-v3-verification-acceptance-runs/{acceptance_run_id}/context", {"attempt": attempt})
        response = self._object(value, "invalid x v3 verification acceptance context")
        if set(response) != {"acceptance_run_id", "attempt", "sources"} or response.get("acceptance_run_id") != acceptance_run_id: raise ProtocolError("invalid x v3 verification acceptance context")
        return _parse_x_v3_verification_replay_context({"replay_id": acceptance_run_id, "attempt": response.get("attempt"), "sources": response.get("sources")}, acceptance_run_id, attempt)

    def complete_x_v3_verification_acceptance_run(self, completion: dict[str, Any]) -> dict[str, Any]:
        self._require_credential(); _validate_x_v3_verification_replay_completion(completion)
        acceptance_run_id = str(completion["replay_id"])
        _, value = self._request("POST", f"api/worker/x-v3-verification-acceptance-runs/{acceptance_run_id}/complete", completion)
        acknowledgement = self._object(value, "invalid x v3 verification acceptance completion acknowledgement")
        if acknowledgement.get("status") != "succeeded": raise ProtocolError("x v3 verification acceptance completion was not acknowledged")
        return acknowledgement

    def fail_x_v3_verification_acceptance_run(self, acceptance_run_id: str, attempt: int, failure_class: str) -> dict[str, Any]:
        self._require_credential(); _validate_x_v3_verification_identity(acceptance_run_id, attempt, "failure")
        if failure_class not in {"timeout", "provider_failure", "empty_response", "invalid_json", "schema_error", "persistence_failure"}: raise ProtocolError("invalid x v3 verification acceptance failure")
        _, value = self._request("POST", f"api/worker/x-v3-verification-acceptance-runs/{acceptance_run_id}/failure", {"attempt": attempt, "failure_class": failure_class})
        return self._object(value, "invalid x v3 verification acceptance failure acknowledgement")

    def claim_x_activation(self) -> dict[str, Any] | None:
        self._require_credential()
        status, value = self._request("POST", "api/worker/x-activations/claim", {})
        if status == 204 or value is None:
            return None
        response = self._object(value, "invalid x activation response")
        activation = response.get("activation")
        if activation is None:
            if set(response) != {"activation"}:
                raise ProtocolError("invalid x activation response")
            return None
        if not isinstance(activation, dict) or set(response) != {"activation"}:
            raise ProtocolError("invalid x activation response")
        if set(activation) != {"source_id", "requested_handle", "parameter_version", "initial_end_at", "idempotent"}:
            raise ProtocolError("invalid x activation response")
        if not all(isinstance(activation.get(key), str) and activation[key] for key in ("source_id", "requested_handle", "parameter_version", "initial_end_at")) or not isinstance(activation.get("idempotent"), bool):
            raise ProtocolError("invalid x activation response")
        return dict(activation)

    def initialize_x_activation(self, source_id: str) -> dict[str, Any]:
        self._require_credential()
        if not isinstance(source_id, str) or not source_id:
            raise ProtocolError("invalid x activation initialization request")
        _, value = self._request("POST", f"api/worker/x-activations/{source_id}/initialize", {})
        response = self._object(value, "invalid x activation initialization response")
        activation = response.get("activation")
        if not isinstance(activation, dict) or set(response) != {"activation"}:
            raise ProtocolError("invalid x activation initialization response")
        if set(activation) != {"task_id", "source_id", "initial_end_at", "idempotent"}:
            raise ProtocolError("invalid x activation initialization response")
        if activation.get("source_id") != source_id or not isinstance(activation.get("initial_end_at"), str) or not activation["initial_end_at"] or activation.get("task_id") is not None and (not isinstance(activation.get("task_id"), str) or not activation["task_id"]) or not isinstance(activation.get("idempotent"), bool):
            raise ProtocolError("invalid x activation initialization response")
        return dict(activation)

    def mark_x_activation_identity_failed(self, source_id: str, error_code: str) -> dict[str, Any]:
        self._require_credential()
        if not isinstance(source_id, str) or not source_id or error_code not in {'identity_mismatch', 'invalid_x_identity', 'profile_timeout', 'profile_invocation_failed', 'activation_protocol_failure', 'identity_resolution_failed'}:
            raise ProtocolError("invalid x activation failure request")
        _, value = self._request("POST", f"api/worker/x-activations/{source_id}/identity-failed", {"error_code": error_code})
        response = self._object(value, "invalid x activation failure response")
        if set(response) != {"activation"} or not isinstance(response.get("activation"), dict):
            raise ProtocolError("invalid x activation failure response")
        activation = response["activation"]
        if set(activation) != {"source_id", "stage"} or activation.get("source_id") != source_id or activation.get("stage") != "identity_failed":
            raise ProtocolError("invalid x activation failure response")
        return dict(activation)

    def get_daily_fact_context(self, task_id: str, attempt: int) -> dict[str, Any]:
        self._require_credential()
        if not isinstance(task_id, str) or not task_id or isinstance(attempt, bool) or not isinstance(attempt, int) or attempt < 1:
            raise ProtocolError("invalid daily fact context request")
        _, value = self._request("GET", f"api/worker/tasks/{task_id}/daily-fact-context?attempt={attempt}", None)
        return self._object(value, "invalid daily fact context response")

    def resolve_author_profiles(self, task_id: str, attempt: int) -> dict[str, Any]:
        self._require_credential()
        if not isinstance(task_id, str) or not task_id or isinstance(attempt, bool) or not isinstance(attempt, int) or attempt < 1:
            raise ProtocolError("invalid author profile resolution request")
        _, value = self._request("POST", f"api/worker/tasks/{task_id}/resolve-author-profiles", {"attempt": attempt})
        response = self._object(value, "invalid author profile resolution response")
        if set(response) != {"author_profiles"} or not isinstance(response.get("author_profiles"), list):
            raise ProtocolError("invalid author profile resolution response")
        return response

    def resolve_x_source_identity(self, source_id: str, parameter_version: str, account_id: str) -> dict[str, object]:
        self._require_credential()
        if not all(isinstance(value, str) and value for value in (source_id, parameter_version, account_id)):
            raise ProtocolError("invalid x identity resolution request")
        _, value = self._request(
            "POST",
            f"api/worker/x-sources/{source_id}/resolve-identity",
            {"parameter_version": parameter_version, "account_id": account_id},
        )
        response = self._object(value, "invalid x identity resolution response")
        if set(response) != {"identity"} or not isinstance(response.get("identity"), dict):
            raise ProtocolError("invalid x identity resolution response")
        identity = response["identity"]
        if set(identity) != {"resolution_status", "parameter_version", "idempotent"}:
            raise ProtocolError("invalid x identity resolution response")
        if identity.get("resolution_status") != "resolved" or identity.get("parameter_version") != parameter_version or not isinstance(identity.get("idempotent"), bool):
            raise ProtocolError("invalid x identity resolution response")
        return {
            "resolution_status": "resolved",
            "parameter_version": parameter_version,
            "idempotent": identity["idempotent"],
        }

    def renew(self, task_id: str, attempt: int) -> dict[str, Any]:
        self._require_credential()
        _, value = self._request("POST", f"api/worker/tasks/{task_id}/lease", {"contract_version": "v0", "attempt": attempt})
        return self._object(value, "invalid lease response")

    def report_result(self, result: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        try:
            payload = load_contract("task-result", result)
        except ContractError as exc:
            raise ProtocolError("invalid task result") from exc
        _, value = self._request("POST", f"api/worker/tasks/{payload['task_id']}/result", payload)
        return self._object(value, "invalid result acknowledgement")

    def persist(self, persistence: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        try:
            payload = load_contract("worker-persistence", persistence)
        except ContractError as exc:
            raise ProtocolError("invalid worker persistence") from exc
        _, value = self._request("POST", f"api/worker/tasks/{payload['task_id']}/persist", payload)
        acknowledgement = self._object(value, "invalid persistence acknowledgement")
        if acknowledgement.get("persisted") is not True:
            raise ProtocolError("persistence was not acknowledged")
        return acknowledgement

    def record_capture_segment(self, segment: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        try:
            payload = load_contract("task-capture-segment", segment)
        except ContractError as exc:
            raise ProtocolError("invalid capture segment") from exc
        _, value = self._request("POST", f"api/worker/tasks/{payload['task_id']}/capture-segments", payload)
        return self._object(value, "invalid capture segment acknowledgement")

    def complete_capture_range(self, completion: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        try:
            payload = load_contract("window-range-completion", completion)
        except ContractError as exc:
            raise ProtocolError("invalid range completion") from exc
        # The capture pages are individually durable before this final atomic
        # commit.  Its control-plane function allows 120s, while this client
        # stops at 110s so Vercel can propagate cancellation to Supabase
        # instead of leaving an abandoned database transaction behind.
        _, value = self._request(
            "POST",
            f"api/worker/tasks/{payload['task_id']}/range-complete",
            payload,
            timeout=max(self.timeout, 110.0),
        )
        acknowledgement = self._object(value, "invalid range completion acknowledgement")
        if acknowledgement.get("status") != "succeeded":
            raise ProtocolError("range completion was not acknowledged")
        return acknowledgement

    def report_failure(self, failure: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        try:
            payload = load_contract("task-failure", failure)
        except ContractError as exc:
            raise ProtocolError("invalid task failure") from exc
        _, value = self._request("POST", f"api/worker/tasks/{payload['task_id']}/failure", payload)
        return self._object(value, "invalid failure acknowledgement")

    def report_event(self, event: dict[str, Any]) -> dict[str, Any]:
        self._require_credential()
        try:
            payload = load_contract("task-event", event)
        except ContractError as exc:
            raise ProtocolError("invalid task event") from exc
        _, value = self._request("POST", f"api/worker/tasks/{payload['task_id']}/events", payload)
        return self._object(value, "invalid event acknowledgement")

    def _require_credential(self) -> DeviceCredential:
        credential = self.credential
        if credential is None:
            raise ProtocolError("worker is not enrolled")
        return credential

    def _request(
        self,
        method: str,
        path: str,
        body: object | None,
        *,
        authenticated: bool = True,
        timeout: float | None = None,
    ) -> tuple[int, object | None]:
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        bypass = os.environ.get("V0_VERCEL_PROTECTION_BYPASS", "").strip()
        if bypass:
            headers["x-vercel-protection-bypass"] = bypass
        if authenticated:
            headers["Authorization"] = f"Bearer {self._require_credential().device_secret}"
        status, value = self.transport(method, urljoin(self.base_url, path), body, headers, self.timeout if timeout is None else timeout)
        if status >= 400:
            error = value.get("error") if isinstance(value, dict) else None
            if status == 409:
                raise RemoteConflict(str(error or "remote conflict"))
            raise ProtocolError(str(error or f"remote status {status}"), status=status)
        return status, value

    @staticmethod
    def _object(value: object | None, message: str) -> dict[str, Any]:
        if not isinstance(value, dict):
            raise ProtocolError(message)
        return dict(value)

    @staticmethod
    def _urllib_transport(method: str, url: str, body: object | None, headers: dict[str, str], timeout: float) -> tuple[int, object | None]:
        data = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
                return response.status, None if not raw else json.loads(raw.decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raw = exc.read()
            try:
                value = json.loads(raw.decode("utf-8")) if raw else None
            except ValueError:
                value = None
            return exc.code, value
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise ProtocolError("control-plane request failed") from exc


def _non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_array(value: object) -> bool:
    return isinstance(value, list) and all(_non_empty_string(item) for item in value)


def _validate_x_daily_judgement_identity(run_id: object, attempt: object, label: str) -> None:
    if not _non_empty_string(run_id) or isinstance(attempt, bool) or not isinstance(attempt, int) or attempt < 1:
        raise ProtocolError(f"invalid x daily judgement {label} request")


def _parse_x_daily_judgement_claim(value: dict[str, Any]) -> dict[str, Any]:
    if set(value) != {"run_id", "attempt", "lease_expires_at", "batch"}:
        raise ProtocolError("invalid x daily judgement claim")
    _validate_x_daily_judgement_identity(value.get("run_id"), value.get("attempt"), "claim")
    batch = value.get("batch")
    if not _non_empty_string(value.get("lease_expires_at")) or not isinstance(batch, dict) or set(batch) != {"id", "natural_date", "cutoff_at", "coverage_status"}:
        raise ProtocolError("invalid x daily judgement claim")
    if not all(_non_empty_string(batch.get(key)) for key in ("id", "natural_date", "cutoff_at")) or batch.get("coverage_status") not in {"complete", "partial"}:
        raise ProtocolError("invalid x daily judgement claim")
    return {"run_id": value["run_id"], "attempt": value["attempt"], "lease_expires_at": value["lease_expires_at"], "batch": dict(batch)}


def _parse_x_daily_judgement_context(value: dict[str, Any], run_id: str, attempt: int) -> dict[str, Any]:
    if set(value) != {"run_id", "batch_id", "attempt", "prompt_version", "sources", "excluded_sources"} or value.get("run_id") != run_id or not _non_empty_string(value.get("batch_id")) or value.get("attempt") != attempt or value.get("prompt_version") != "v3-x-cross-blogger-1":
        raise ProtocolError("invalid x daily judgement context")
    sources = value.get("sources")
    excluded = value.get("excluded_sources")
    if not isinstance(sources, list) or not isinstance(excluded, list):
        raise ProtocolError("invalid x daily judgement context")
    source_ids: set[str] = set()
    for source in sources:
        if not isinstance(source, dict) or set(source) != {"source_id", "display_name", "window_segments"} or not _non_empty_string(source.get("source_id")) or not _non_empty_string(source.get("display_name")) or not isinstance(source.get("window_segments"), list) or source["source_id"] in source_ids:
            raise ProtocolError("invalid x daily judgement context")
        source_ids.add(source["source_id"])
        for segment in source["window_segments"]:
            if not isinstance(segment, dict) or set(segment) != {"id", "occurred_from_at", "occurred_through_at", "viewpoints", "uncertainties", "analyses"} or not all(_non_empty_string(segment.get(key)) for key in ("id", "occurred_from_at", "occurred_through_at")) or not _string_array(segment.get("viewpoints")) and segment.get("viewpoints") != [] or not isinstance(segment.get("uncertainties"), list) or not isinstance(segment.get("analyses"), list):
                raise ProtocolError("invalid x daily judgement context")
            for analysis in segment["analyses"]:
                if not isinstance(analysis, dict) or set(analysis) != {"post_id", "blogger_viewpoint", "arguments", "quoted_post_viewpoint", "uncertainties", "evidence_post_ids"} or not _non_empty_string(analysis.get("post_id")) or analysis.get("blogger_viewpoint") is not None and not _non_empty_string(analysis.get("blogger_viewpoint")) or analysis.get("quoted_post_viewpoint") is not None and not _non_empty_string(analysis.get("quoted_post_viewpoint")) or not isinstance(analysis.get("arguments"), list) or not isinstance(analysis.get("uncertainties"), list) or not _string_array(analysis.get("evidence_post_ids")):
                    raise ProtocolError("invalid x daily judgement context")
    for source in excluded:
        if not isinstance(source, dict) or set(source) != {"source_id", "display_name", "reason"} or not all(_non_empty_string(source.get(key)) for key in ("source_id", "display_name", "reason")):
            raise ProtocolError("invalid x daily judgement context")
    return value


def _validate_x_daily_judgement_completion(value: dict[str, Any]) -> None:
    required = {
        "run_id", "attempt", "schema_version", "provider", "model_reported", "prompt_version",
        "security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints", "uncertainties",
    }
    if set(value) != required or value.get("schema_version") != "v3-x-cross-blogger" or value.get("provider") != "codex_cli" or value.get("prompt_version") != "v3-x-cross-blogger-1":
        raise ProtocolError("invalid x daily judgement completion")
    _validate_x_daily_judgement_identity(value.get("run_id"), value.get("attempt"), "completion")
    categories = ("security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints")
    if not _safe_model_reported(value.get("model_reported")) or not all(isinstance(value.get(category), list) for category in categories) or not _string_array(value.get("uncertainties")):
        raise ProtocolError("invalid x daily judgement completion")
    item_fields = {
        "statement", "action_intent", "action_scope", "conditions", "supporting_source_ids",
        "dissenting_source_ids", "analysis_ids", "evidence_post_ids", "uncertainties",
    }
    action_intents = {"build_position", "buy", "add", "hold", "reduce", "sell", "watch", "avoid", "none"}
    for item in [*(entry for category in categories for entry in value[category])]:
        if not isinstance(item, dict) or set(item) != item_fields or not _non_empty_string(item.get("statement")):
            raise ProtocolError("invalid x daily judgement completion")
        action_intent = item.get("action_intent")
        action_scope = item.get("action_scope")
        if action_intent not in action_intents or not isinstance(action_scope, str) or (action_intent == "none" and action_scope) or (action_intent != "none" and not action_scope.strip()):
            raise ProtocolError("invalid x daily judgement completion")
        if not all(isinstance(item.get(key), list) and all(_non_empty_string(entry) for entry in item[key]) for key in ("conditions", "supporting_source_ids", "dissenting_source_ids", "analysis_ids", "evidence_post_ids", "uncertainties")):
            raise ProtocolError("invalid x daily judgement completion")
        if not item["analysis_ids"] or not item["evidence_post_ids"]:
            raise ProtocolError("invalid x daily judgement completion")


def _validate_x_v3_verification_identity(replay_id: object, attempt: object, label: str) -> None:
    if not isinstance(replay_id, str) or not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", replay_id, re.IGNORECASE) or isinstance(attempt, bool) or attempt != 1:
        raise ProtocolError(f"invalid x v3 verification replay {label} request")


def _parse_x_v3_verification_replay_context(value: dict[str, Any], replay_id: str, attempt: int) -> dict[str, Any]:
    if set(value) != {"replay_id", "attempt", "sources"} or value.get("replay_id") != replay_id or value.get("attempt") != attempt or not isinstance(value.get("sources"), list):
        raise ProtocolError("invalid x v3 verification replay context")
    source_keys = {"source_id", "display_name", "occurred_from_at", "occurred_through_at", "posts"}
    post_keys = {"post_id", "content", "occurred_at", "post_url", "post_type", "quoted_post_id", "reply_to_post_id", "reposted_post_id", "context_status", "attachments"}
    source_ids: set[str] = set()
    for source in value["sources"]:
        if not isinstance(source, dict) or set(source) != source_keys or not all(_non_empty_string(source.get(key)) for key in ("source_id", "display_name", "occurred_from_at", "occurred_through_at")) or source["source_id"] in source_ids or not isinstance(source.get("posts"), list) or not source["posts"]:
            raise ProtocolError("invalid x v3 verification replay context")
        source_ids.add(source["source_id"])
        post_ids: set[str] = set()
        for post in source["posts"]:
            if not isinstance(post, dict) or set(post) != post_keys or not all(_non_empty_string(post.get(key)) for key in ("post_id", "occurred_at", "post_url", "post_type", "context_status")) or not isinstance(post.get("content"), str) or post["post_id"] in post_ids or post["post_type"] not in {"original", "quote", "reply", "repost"} or post["context_status"] not in {"complete", "unavailable", "deleted", "unresolved"} or not isinstance(post.get("attachments"), list):
                raise ProtocolError("invalid x v3 verification replay context")
            if any(post.get(key) is not None and not _non_empty_string(post.get(key)) for key in ("quoted_post_id", "reply_to_post_id", "reposted_post_id")):
                raise ProtocolError("invalid x v3 verification replay context")
            post_ids.add(post["post_id"])
    if not value["sources"]:
        raise ProtocolError("invalid x v3 verification replay context")
    return value


def _validate_x_v3_verification_replay_completion(value: dict[str, Any]) -> None:
    required = {"replay_id", "attempt", "provider", "model_reported", "sources", "daily"}
    if set(value) != required or value.get("provider") != "codex_cli" or not _safe_model_reported(value.get("model_reported")) or not isinstance(value.get("sources"), list) or not isinstance(value.get("daily"), dict):
        raise ProtocolError("invalid x v3 verification replay completion")
    _validate_x_v3_verification_identity(value.get("replay_id"), value.get("attempt"), "completion")
    source_keys = {"source_id", "analyses", "segment"}
    analysis_keys = {"post_id", "analysis_id", "analysis_version", "schema_version", "prompt_version", "analysis_output", "blogger_viewpoint", "arguments", "quoted_post_viewpoint", "uncertainties", "evidence_post_ids", "post_link"}
    segment_keys = {"occurred_from_at", "occurred_through_at", "schema_version", "prompt_version", "segment_output", "analysis_ids", "evidence_post_ids", "uncertainties"}
    source_ids: set[str] = set()
    for source in value["sources"]:
        if not isinstance(source, dict) or set(source) != source_keys or not _non_empty_string(source.get("source_id")) or source["source_id"] in source_ids or not isinstance(source.get("analyses"), list) or not source["analyses"] or not isinstance(source.get("segment"), dict) or set(source["segment"]) != segment_keys:
            raise ProtocolError("invalid x v3 verification replay completion")
        source_ids.add(source["source_id"])
        segment = source["segment"]
        if not all(_non_empty_string(segment.get(key)) for key in ("occurred_from_at", "occurred_through_at")) or segment.get("schema_version") != "v3-x-window" or segment.get("prompt_version") != "v3-x-window-1" or not isinstance(segment.get("segment_output"), dict) or segment["segment_output"].get("schema_version") != "v3-x-window" or not all(_string_array(segment.get(key)) for key in ("analysis_ids", "evidence_post_ids", "uncertainties")):
            raise ProtocolError("invalid x v3 verification replay completion")
        analysis_ids: set[str] = set()
        for analysis in source["analyses"]:
            if not isinstance(analysis, dict) or set(analysis) != analysis_keys or not _non_empty_string(analysis.get("post_id")) or analysis.get("analysis_id") != f"{analysis.get('post_id')}@2" or analysis.get("analysis_version") != 2 or analysis.get("schema_version") != "v3-x-post-analysis" or analysis.get("prompt_version") != "v3-x-post-analysis-1" or not isinstance(analysis.get("analysis_output"), dict) or analysis["analysis_output"].get("post_id") != analysis["post_id"] or analysis.get("blogger_viewpoint") is not None and not _non_empty_string(analysis.get("blogger_viewpoint")) or not _string_array(analysis.get("arguments")) or analysis.get("quoted_post_viewpoint") is not None and not _non_empty_string(analysis.get("quoted_post_viewpoint")) or not _string_array(analysis.get("uncertainties")) or not _string_array(analysis.get("evidence_post_ids")) or not _non_empty_string(analysis.get("post_link")) or analysis["analysis_id"] in analysis_ids:
                raise ProtocolError("invalid x v3 verification replay completion")
            analysis_ids.add(analysis["analysis_id"])
        if set(segment["analysis_ids"]) != analysis_ids or len(segment["analysis_ids"]) != len(analysis_ids):
            raise ProtocolError("invalid x v3 verification replay completion")
    daily = value["daily"]
    daily_keys = {"schema_version", "prompt_version", "security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints", "uncertainties"}
    if set(daily) != daily_keys or daily.get("schema_version") != "v3-x-cross-blogger" or daily.get("prompt_version") != "v3-x-cross-blogger-1" or not all(isinstance(daily.get(category), list) for category in ("security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints")) or not _string_array(daily.get("uncertainties")):
        raise ProtocolError("invalid x v3 verification replay completion")


def _safe_model_reported(value: object) -> bool:
    if value is None:
        return True
    if not isinstance(value, str) or not 1 <= len(value) <= 160 or any(ord(character) < 32 or ord(character) == 127 for character in value):
        return False
    stripped = value.lstrip()
    return not (
        stripped.startswith("/")
        or bool(re.match(r"^[A-Za-z]:[\\/]", stripped))
        or stripped.lower().startswith("file:")
        or bool(re.match(r"^(local_evidence(_path)?|local_path|raw_x_content|raw_content|cookie|browser[_ -]?profile)[\s:=/\\]", stripped, re.IGNORECASE))
    )
