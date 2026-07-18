from __future__ import annotations


class CheckpointNotAdvanced(RuntimeError):
    pass


class CheckpointGuard:
    def __init__(self, previous: str | None, allowed: tuple[str | None, ...]) -> None:
        self.previous = previous
        self.allowed = allowed
        self.current = previous

    def commit(self, candidate: str | None, *, persistence_ack: str) -> str | None:
        if persistence_ack != "accepted":
            raise CheckpointNotAdvanced("checkpoint requires accepted persistence acknowledgement")
        if candidate not in self.allowed:
            raise CheckpointNotAdvanced("checkpoint is outside the current input range")
        if self.current is not None:
            try:
                current_index = self.allowed.index(self.current)
                candidate_index = self.allowed.index(candidate)
            except ValueError as exc:
                raise CheckpointNotAdvanced("checkpoint is not in the current range") from exc
            if candidate_index < current_index:
                raise CheckpointNotAdvanced("checkpoint cannot move backwards")
        self.current = candidate
        return self.current
