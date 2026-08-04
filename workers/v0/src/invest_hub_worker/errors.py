from __future__ import annotations


class WorkerError(Exception):
    """Base class for typed Worker lifecycle failures."""


class ConfigError(WorkerError, ValueError):
    pass


class ProtocolError(WorkerError):
    def __init__(self, message: str, *, status: int | None = None) -> None:
        super().__init__(message)
        self.status = status


class AlreadyEnrolled(ProtocolError):
    pass


class RemoteConflict(ProtocolError):
    pass


class LeaseUncertain(WorkerError):
    pass
