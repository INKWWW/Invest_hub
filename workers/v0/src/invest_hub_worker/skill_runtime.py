"""Minimal, fail-closed runtime boundary for the frozen Demo Skills.

The frozen bundle is read-only input.  Runtime output is addressed only by a
relative path below one Run workspace.  This module deliberately does not
modify the existing Worker runtime or protocol seams.
"""

from __future__ import annotations

import json
import hashlib
import os
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Final, Sequence


FROZEN_COMMIT: Final = "d64751635308d1920bcdae234e6dd957fd79e736"
FROZEN_REPOSITORY: Final = "https://github.com/xbtlin/ai-berkshire"
SKILL_IDS: Final = frozenset(
    {"investment-research", "portfolio-review", "investment-checklist"}
)
TOOL_NAMES: Final = frozenset({"financial_rigor.py", "report_audit.py"})
FROZEN_FILE_SHA256: Final = {
    "investment-research/SKILL.md": "4f616333c0f39a457445afc4666f262203e84f1998ca421777f3827f117e5976",
    "portfolio-review/SKILL.md": "7261b78e857f86bff6196571a4a17dbeb0d8bf2a8093d9dedb71de05fc2fa486",
    "investment-checklist/SKILL.md": "109f9df7f7264571f597bda5da7f26ddafaec34f364138476bc1e229ffd56a0b",
    "tools/financial_rigor.py": "dee5c9de8c2dd71f1fd1cd7467dda6e5315ffa98132b82ce393b3e3e8c74fce7",
    "tools/report_audit.py": "8848c1f4db06cd7145c519161d15e895ce14b39a437bd8859b72ba74b94b7e7b",
}


class SkillRuntimeError(ValueError):
    """A frozen Skill or Run-workspace boundary was violated."""


@dataclass(frozen=True)
class FrozenSkill:
    skill_id: str
    instruction_path: Path


def _is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def _reject_symlink_components(path: Path, anchor: Path) -> None:
    """Reject existing symlink components between anchor and path."""

    try:
        relative = path.relative_to(anchor)
    except ValueError as exc:
        raise SkillRuntimeError("path is outside its authorized root") from exc

    current = anchor
    for component in relative.parts:
        current /= component
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            raise SkillRuntimeError("symbolic links are not allowed")


def _validated_directory(path: Path, *, label: str, create: bool = False) -> Path:
    candidate = Path(path)
    if create and not candidate.exists():
        candidate.mkdir(parents=True, mode=0o700)
    if not candidate.is_absolute():
        raise SkillRuntimeError(f"{label} must be an absolute directory")
    try:
        mode = candidate.lstat().st_mode
    except FileNotFoundError as exc:
        raise SkillRuntimeError(f"{label} does not exist") from exc
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        raise SkillRuntimeError(f"{label} must be a real directory")
    resolved = candidate.resolve(strict=True)
    return resolved


def _validate_relative_path(value: str | os.PathLike[str]) -> Path:
    if not isinstance(value, (str, os.PathLike)):
        raise SkillRuntimeError("Run path must be text or a path-like value")
    raw = os.fspath(value)
    if not isinstance(raw, str) or not raw or "\x00" in raw:
        raise SkillRuntimeError("Run path must be a non-empty text path")

    # Reject both POSIX and Windows absolute syntax, even when this worker is
    # currently running on POSIX.  Backslashes are rejected to avoid a path
    # having different security meaning on another host.
    windows = PureWindowsPath(raw)
    if Path(raw).is_absolute() or windows.is_absolute() or windows.drive:
        raise SkillRuntimeError("absolute Run paths are not allowed")
    if "\\" in raw or any(part == ".." for part in raw.replace("/", "\\").split("\\")):
        raise SkillRuntimeError("parent traversal is not allowed")

    relative = Path(raw)
    if relative.is_absolute() or relative == Path("."):
        raise SkillRuntimeError("Run path must name a relative file")
    if any(part == ".." for part in relative.parts):
        raise SkillRuntimeError("parent traversal is not allowed")
    return relative


class SkillRuntime:
    """Read a pinned Skill bundle and write only below one Run directory."""

    def __init__(self, bundle_root: Path, run_workspace: Path) -> None:
        self.bundle_root = _validated_directory(Path(bundle_root), label="Skill bundle")
        self.run_workspace = _validated_directory(
            Path(run_workspace), label="Run workspace", create=True
        )
        if _is_relative_to(self.bundle_root, self.run_workspace) or _is_relative_to(
            self.run_workspace, self.bundle_root
        ):
            raise SkillRuntimeError("Skill bundle and Run workspace must be separate")
        self._validate_bundle()

    def _validate_bundle(self) -> None:
        provenance_path = self.bundle_root / "provenance.json"
        _reject_symlink_components(provenance_path, self.bundle_root)
        try:
            provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise SkillRuntimeError("invalid Skill provenance") from exc
        declared_paths = {
            path.removeprefix("codex-skills/")
            for path in provenance.get("paths", [])
            if isinstance(path, str)
        }
        expected_skill_paths = {f"{skill_id}/SKILL.md" for skill_id in SKILL_IDS}
        if (
            provenance.get("repository") != FROZEN_REPOSITORY
            or provenance.get("commit") != FROZEN_COMMIT
            or declared_paths != expected_skill_paths
        ):
            raise SkillRuntimeError("Skill bundle is not the approved frozen commit")

        for skill_id in SKILL_IDS:
            self._verify_frozen_file(self._skill_file(skill_id))
        for tool_name in TOOL_NAMES:
            self._verify_frozen_file(self._tool_file(tool_name))

    def _verify_frozen_file(self, path: Path) -> None:
        relative = path.relative_to(self.bundle_root)
        expected = FROZEN_FILE_SHA256.get(relative.as_posix())
        if expected is None:
            raise SkillRuntimeError("unexpected file in frozen Skill bundle")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise SkillRuntimeError("frozen Skill file has been modified")

    def _skill_file(self, skill_id: str) -> Path:
        if skill_id not in SKILL_IDS:
            raise SkillRuntimeError("Skill is not admitted")
        path = self.bundle_root / skill_id / "SKILL.md"
        _reject_symlink_components(path, self.bundle_root)
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError as exc:
            raise SkillRuntimeError("admitted Skill is incomplete") from exc
        if not stat.S_ISREG(mode):
            raise SkillRuntimeError("Skill instruction must be a regular file")
        return path

    def _tool_file(self, tool_name: str) -> Path:
        if tool_name not in TOOL_NAMES:
            raise SkillRuntimeError("tool is not admitted")
        path = self.bundle_root / "tools" / tool_name
        _reject_symlink_components(path, self.bundle_root)
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError as exc:
            raise SkillRuntimeError("admitted Skill tool is incomplete") from exc
        if not stat.S_ISREG(mode):
            raise SkillRuntimeError("Skill tool must be a regular file")
        return path

    def read_skill(self, skill_id: str) -> str:
        return self._skill_file(skill_id).read_text(encoding="utf-8")

    def tool_path(self, tool_name: str) -> Path:
        """Return an admitted tool path for read/execute use; never for writes."""

        return self._tool_file(tool_name)

    def run_tool(self, tool_name: str, args: Sequence[str] = ()) -> subprocess.CompletedProcess[str]:
        """Run one explicitly admitted helper with the current Run as cwd."""

        if not all(isinstance(arg, str) and "\x00" not in arg for arg in args):
            raise SkillRuntimeError("tool arguments must be safe text")
        return subprocess.run(
            [sys.executable, str(self._tool_file(tool_name)), *args],
            cwd=self.run_workspace,
            capture_output=True,
            text=True,
            check=False,
        )

    def skill(self, skill_id: str) -> FrozenSkill:
        return FrozenSkill(skill_id=skill_id, instruction_path=self._skill_file(skill_id))

    def resolve_run_path(self, relative_path: str | os.PathLike[str]) -> Path:
        relative = _validate_relative_path(relative_path)
        candidate = self.run_workspace / relative
        _reject_symlink_components(candidate, self.run_workspace)
        resolved = candidate.resolve(strict=False)
        if not _is_relative_to(resolved, self.run_workspace):
            raise SkillRuntimeError("Run path escapes the Run workspace")
        return candidate

    def write_run_text(
        self,
        relative_path: str | os.PathLike[str],
        content: str,
        *,
        overwrite: bool = False,
    ) -> Path:
        if not isinstance(content, str):
            raise SkillRuntimeError("Run output must be text")
        path = self.resolve_run_path(relative_path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        _reject_symlink_components(path, self.run_workspace)

        flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW
        flags |= os.O_TRUNC if overwrite else os.O_EXCL
        try:
            fd = os.open(path, flags, 0o600)
        except OSError as exc:
            raise SkillRuntimeError("cannot create the Run output file") from exc
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(content)
        except Exception:
            # fdopen owns the descriptor after successful construction; this
            # branch intentionally lets the original exception propagate.
            raise
        return path

    def read_run_text(self, relative_path: str | os.PathLike[str]) -> str:
        path = self.resolve_run_path(relative_path)
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError as exc:
            raise SkillRuntimeError("Run output does not exist") from exc
        if not stat.S_ISREG(mode):
            raise SkillRuntimeError("Run output must be a regular file")
        try:
            return path.read_text(encoding="utf-8")
        except OSError as exc:
            raise SkillRuntimeError("Run output cannot be read") from exc
