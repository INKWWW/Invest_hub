from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from .x_identity import OpenCLIProfileInvoker


class ActivationProtocol(Protocol):
    def claim_x_activation(self) -> dict[str, object] | None: ...
    def resolve_x_source_identity(self, source_id: str, parameter_version: str, account_id: str) -> dict[str, object]: ...
    def initialize_x_activation(self, source_id: str) -> dict[str, object]: ...


@dataclass(frozen=True)
class ActivationOutcome:
    status: str
    task_id: str | None = None
    error: str | None = None


def activate_one_x_source(protocol: ActivationProtocol, invoker: OpenCLIProfileInvoker) -> ActivationOutcome:
    activation = protocol.claim_x_activation()
    if activation is None:
        return ActivationOutcome("no_activation")
    source_id = activation.get("source_id")
    requested_handle = activation.get("requested_handle")
    parameter_version = activation.get("parameter_version")
    if not all(isinstance(value, str) and value for value in (source_id, requested_handle, parameter_version)):
        return ActivationOutcome("retryable_failed", error="invalid_x_activation")
    verified = invoker.resolve(requested_handle)
    protocol.resolve_x_source_identity(source_id, parameter_version, verified)
    initialized = protocol.initialize_x_activation(source_id)
    task_id = initialized.get("task_id")
    return ActivationOutcome("initialized", task_id if isinstance(task_id, str) and task_id else None)
