from __future__ import annotations


class WorkerError(Exception):
    """Base class for typed Worker lifecycle failures."""


class ConfigError(WorkerError, ValueError):
    pass


class ProtocolError(WorkerError):
    pass


class AlreadyEnrolled(ProtocolError):
    pass


class RemoteConflict(ProtocolError):
    pass


class LeaseUncertain(WorkerError):
    pass
