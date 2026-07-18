from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker


class ContractError(ValueError):
    """Raised when a protocol payload fails schema or semantic validation."""


_SCHEMA_ROOT = Path(__file__).resolve().parents[4] / "contracts" / "v0"


def _schema_path(name: str) -> Path:
    path = _SCHEMA_ROOT / f"{name}.schema.json"
    if not path.is_file():
        raise ContractError(f"unknown contract: {name}")
    return path


def load_contract(name: str, value: object) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{name} must be an object")
    schema = json.loads(_schema_path(name).read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(value), key=lambda error: list(error.path))
    if errors:
        details = "; ".join(error.message for error in errors)
        raise ContractError(f"invalid {name} contract: {details}")
    return dict(value)


def validate_task_result(
    value: object,
    *,
    previous_checkpoint: str | None,
    allowed_checkpoints: set[str | None],
) -> dict[str, Any]:
    result = load_contract("task-result", value)
    checkpoint = result["safe_checkpoint"]
    if checkpoint not in allowed_checkpoints:
        raise ContractError("safe_checkpoint is outside the current input range")
    if previous_checkpoint is not None and previous_checkpoint not in allowed_checkpoints:
        raise ContractError("previous_checkpoint is outside the current input range")
    return result
