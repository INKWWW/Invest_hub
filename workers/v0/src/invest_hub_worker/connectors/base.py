from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable, Protocol


class ConnectorError(RuntimeError):
    def __init__(self, message: str, *, code: str = "command_failed") -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class RawPage:
    page_id: str
    source_id: str
    cursor_before: str | None
    cursor_after: str | None
    messages: tuple[dict[str, Any], ...]
    raw_payload_ref: str
    telemetry: dict[str, Any] = field(default_factory=dict)


class Connector(Protocol):
    def collect(self, source: Any, checkpoint: str | None) -> Iterable[RawPage]:
        raise NotImplementedError
