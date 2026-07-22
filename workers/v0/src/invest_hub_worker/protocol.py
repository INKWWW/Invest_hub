from __future__ import annotations

import json
import os
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

    def get_daily_fact_context(self, task_id: str, attempt: int) -> dict[str, Any]:
        self._require_credential()
        if not isinstance(task_id, str) or not task_id or isinstance(attempt, bool) or not isinstance(attempt, int) or attempt < 1:
            raise ProtocolError("invalid daily fact context request")
        _, value = self._request("GET", f"api/worker/tasks/{task_id}/daily-fact-context?attempt={attempt}", None)
        return self._object(value, "invalid daily fact context response")

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
        _, value = self._request("POST", f"api/worker/tasks/{payload['task_id']}/range-complete", payload)
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

    def _request(self, method: str, path: str, body: object | None, *, authenticated: bool = True) -> tuple[int, object | None]:
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        bypass = os.environ.get("V0_VERCEL_PROTECTION_BYPASS", "").strip()
        if bypass:
            headers["x-vercel-protection-bypass"] = bypass
        if authenticated:
            headers["Authorization"] = f"Bearer {self._require_credential().device_secret}"
        status, value = self.transport(method, urljoin(self.base_url, path), body, headers, self.timeout)
        if status >= 400:
            error = value.get("error") if isinstance(value, dict) else None
            if status == 409:
                raise RemoteConflict(str(error or "remote conflict"))
            raise ProtocolError(str(error or f"remote status {status}"))
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
