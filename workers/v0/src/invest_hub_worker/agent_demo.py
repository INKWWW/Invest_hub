"""Small local Demo runner seam.

The Demo deliberately accepts a run id supplied by the local test harness. It
does not start the production Runner, install a launch agent, or expose the
legacy Agent quota/trace/memory protocol.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import shutil
import subprocess
import tempfile
import os
import stat
from pathlib import Path
from typing import Any, Callable, Protocol

from .errors import ProtocolError
from .skill_runtime import SKILL_IDS, SkillRuntime
class DemoProvider(Protocol):
    def complete(self, question: str, prompt: str | None = None) -> str:
        raise NotImplementedError


class DemoRunProtocol(Protocol):
    def heartbeat(self, status: str, capabilities: list[str], sent_at: str) -> dict[str, Any]:
        raise NotImplementedError

    def claim_agent_demo_run(self, run_id: str) -> dict[str, Any] | None:
        raise NotImplementedError

    def next_agent_demo_run(self) -> str | None:
        raise NotImplementedError

    def complete_agent_demo_run(self, run_id: str, content: str, provider: str) -> dict[str, Any]:
        raise NotImplementedError


@dataclass(frozen=True)
class ScriptedDemoProvider:
    answer_prefix: str = "# 本地 Demo 研究结果"

    def complete(self, question: str, prompt: str | None = None) -> str:
        if not question.strip():
            raise ProtocolError("empty demo question")
        return f"{self.answer_prefix}\n\n问题：{question.strip()}\n\n这是 scripted Provider 的确定性 Markdown 回答。"


class CodexDemoProvider:
    """Bounded real Codex CLI adapter for one isolated Demo Run."""

    DEFAULT_TIMEOUT_SECONDS = 360.0

    def __init__(
        self,
        run_workspace: Path,
        *,
        binary: str = "codex",
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        readonly_dirs: tuple[Path, ...] = (),
        codex_home_source: Path | None = None,
        runner: Callable[[list[str], str, Path, float], str | None] | None = None,
    ) -> None:
        if not binary.strip() or timeout_seconds <= 0:
            raise ValueError("invalid Codex provider configuration")
        self.run_workspace = Path(run_workspace).resolve()
        self.run_workspace.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.binary = binary
        self.timeout_seconds = timeout_seconds
        self.readonly_dirs = tuple(Path(path).resolve() for path in readonly_dirs)
        self.last_execution_status = "not_started"
        self.last_failure_class: str | None = None
        self.last_diagnostic_path: Path | None = None
        self.codex_home = self.run_workspace / ".codex-home"
        self._prepare_codex_home(codex_home_source or (Path.home() / ".codex"))
        self.runner = runner or (lambda command, prompt, output_path, timeout: _run_codex_process(
            command, prompt, output_path, timeout, self.codex_home
        ))

    def _prepare_codex_home(self, source_home: Path) -> None:
        self.codex_home.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.codex_home, stat.S_IRWXU)
        auth_source = source_home / "auth.json"
        if auth_source.is_file() and not auth_source.is_symlink():
            auth_target = self.codex_home / "auth.json"
            shutil.copyfile(auth_source, auth_target)
            os.chmod(auth_target, stat.S_IRUSR | stat.S_IWUSR)

    def complete(self, question: str, prompt: str | None = None) -> str:
        if not question.strip():
            raise ProtocolError("empty demo question")
        output_path = self.run_workspace / "codex-last-message.md"
        output_path.unlink(missing_ok=True)
        self.last_failure_class = None
        self.last_diagnostic_path = output_path.with_suffix(".diagnostic.log")
        command = [
            self.binary,
            "exec",
            "--sandbox",
            "workspace-write",
            "--add-dir",
            str(self.run_workspace),
            "--ephemeral",
            "--ignore-user-config",
            "--skip-git-repo-check",
            "--output-last-message",
            str(output_path),
        ]
        for readonly_dir in self.readonly_dirs:
            command.extend(["--add-dir", str(readonly_dir)])
        command.append("-")
        self.last_execution_status = self.runner(command, prompt or question, output_path, self.timeout_seconds) or "answer_ready"
        if self.last_execution_status not in {"answer_ready", "answer_ready_with_timeout"}:
            self.last_failure_class = self.last_execution_status
            raise ProtocolError("Codex process failed")
        try:
            answer = output_path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise ProtocolError("Codex returned no readable Demo answer") from exc
        if not answer.strip() or len(answer) > 20000:
            raise ProtocolError("Codex returned an invalid Demo answer")
        return answer


def _run_codex_process(command: list[str], prompt: str, output_path: Path, timeout_seconds: float, codex_home: Path) -> str:
    stdout_path = output_path.with_suffix(".stdout.log")
    stderr_path = output_path.with_suffix(".stderr.log")
    diagnostic_path = output_path.with_suffix(".diagnostic.log")
    for path in (stdout_path, stderr_path, diagnostic_path):
        path.unlink(missing_ok=True)
    try:
        with (
            stdout_path.open("w", encoding="utf-8") as stdout_file,
            stderr_path.open("w", encoding="utf-8") as stderr_file,
        ):
            _restrict_file(stdout_path)
            _restrict_file(stderr_path)
            try:
                completed = subprocess.run(
                    command,
                    input=prompt,
                    text=True,
                    cwd=str(output_path.parent),
                    stdout=stdout_file,
                    stderr=stderr_file,
                    env={**os.environ, "CODEX_HOME": str(codex_home)},
                    timeout=timeout_seconds,
                    check=False,
                )
            except subprocess.TimeoutExpired as exc:
                stdout_file.flush()
                stderr_file.flush()
                _write_text(diagnostic_path, _safe_diagnostic(stdout_path, stderr_path, f"timeout after {exc.timeout} seconds"))
                try:
                    answer = output_path.read_text(encoding="utf-8")
                except (OSError, UnicodeError):
                    answer = ""
                if answer.strip():
                    return "answer_ready_with_timeout"
                return "timeout"
            except OSError as exc:
                stdout_file.flush()
                stderr_file.flush()
                _write_text(diagnostic_path, _safe_diagnostic(stdout_path, stderr_path, f"cli error: {type(exc).__name__}"))
                return "cli_failed"
    except subprocess.TimeoutExpired as exc:
        _write_text(diagnostic_path, _safe_diagnostic(stdout_path, stderr_path, f"timeout after {exc.timeout} seconds"))
        return "timeout"
    if completed.returncode != 0:
        diagnostic = _safe_diagnostic(stdout_path, stderr_path, f"exit code {completed.returncode}")
        _write_text(diagnostic_path, diagnostic)
        return _classify_failure(diagnostic)
    return "answer_ready"


def _safe_diagnostic(stdout_path: Path, stderr_path: Path, fallback: str) -> str:
    """Keep raw streams local while returning only a bounded safe summary."""

    try:
        stderr = stderr_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        stderr = ""
    try:
        stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        stdout = ""
    return (fallback + "\n" + stderr[-4000:] + "\n" + stdout[-1000:]).strip()


def _classify_failure(diagnostic: str) -> str:
    lowered = diagnostic.lower()
    if any(marker in lowered for marker in ("unauthorized", "not authenticated", "authentication", "login required", "401")):
        return "auth_failed"
    if any(marker in lowered for marker in (
        "connection", "network", "timed out", "dns", "failed to lookup", "nodename nor servname",
        "failed to connect", "websocket", "502", "503", "504",
    )):
        return "network_failed"
    return "provider_failed"


def _restrict_file(path: Path) -> None:
    try:
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
    except OSError:
        pass


def _write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")
    _restrict_file(path)


def run_demo_once(
    protocol: DemoRunProtocol,
    run_id: str,
    provider: DemoProvider | None = None,
    *,
    skill_bundle: Path | None = None,
    run_root: Path | None = None,
    provider_name: str = "scripted",
) -> str:
    claim = protocol.claim_agent_demo_run(run_id)
    if claim is None:
        return "no_claim"
    return _run_claimed_demo(protocol, claim, provider, skill_bundle=skill_bundle, run_root=run_root, provider_name=provider_name)


def _run_claimed_demo(
    protocol: DemoRunProtocol,
    claim: dict[str, Any],
    provider: DemoProvider | None,
    *,
    skill_bundle: Path | None,
    run_root: Path | None,
    provider_name: str,
) -> str:
    run_id = claim.get("run_id")
    if not isinstance(run_id, str) or not run_id.strip():
        raise ProtocolError("invalid demo run id")
    question = claim.get("question")
    if not isinstance(question, str) or not question.strip():
        raise ProtocolError("invalid demo question")
    prompt = claim.get("general_prompt")
    if prompt is not None and not isinstance(prompt, str):
        raise ProtocolError("invalid demo general prompt")
    workspace: Path | None = None
    try:
        skill_id = claim.get("skill_id")
        if skill_id is not None:
            if skill_id not in SKILL_IDS or skill_bundle is None or run_root is None:
                raise ProtocolError("skill runtime is not configured")
            root = Path(run_root)
            root.mkdir(parents=True, exist_ok=True)
            workspace = Path(tempfile.mkdtemp(prefix="agent-demo-", dir=str(root)))
            runtime = SkillRuntime(Path(skill_bundle), workspace)
            prompt = _build_skill_prompt(claim, runtime, skill_id, question)
        answer = (provider or ScriptedDemoProvider()).complete(question, prompt)
    finally:
        if workspace is not None:
            shutil.rmtree(workspace, ignore_errors=True)
    acknowledgement = protocol.complete_agent_demo_run(run_id, answer, provider_name)
    if acknowledgement.get("status") != "succeeded":
        raise ProtocolError("demo completion was not acknowledged")
    return "succeeded"


def run_agent_demo_once(
    protocol: DemoRunProtocol,
    run_id: str,
    *,
    bundle: Path,
    run_root: Path,
    provider: DemoProvider | None = None,
    provider_name: str | None = None,
    binary: str = "codex",
    timeout_seconds: float = CodexDemoProvider.DEFAULT_TIMEOUT_SECONDS,
) -> str:
    """Run exactly one authorized Demo request on the local machine."""

    protocol.heartbeat("idle", ["agent_demo"], datetime.now(timezone.utc).isoformat())
    root = Path(run_root)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    job_workspace = Path(tempfile.mkdtemp(prefix="agent-demo-job-", dir=str(root)))
    try:
        selected_provider = provider or CodexDemoProvider(
            job_workspace,
            binary=binary,
            timeout_seconds=timeout_seconds,
            readonly_dirs=(Path(bundle),),
        )
        selected_name = provider_name or ("codex_cli" if isinstance(selected_provider, CodexDemoProvider) else "scripted")
        return run_demo_once(
            protocol,
            run_id,
            selected_provider,
            skill_bundle=Path(bundle),
            run_root=job_workspace,
            provider_name=selected_name,
        )
    finally:
        shutil.rmtree(job_workspace, ignore_errors=True)


def run_agent_demo_worker_once(
    protocol: DemoRunProtocol,
    *,
    bundle: Path,
    run_root: Path,
    provider: DemoProvider | None = None,
    provider_name: str | None = None,
    binary: str = "codex",
    timeout_seconds: float = CodexDemoProvider.DEFAULT_TIMEOUT_SECONDS,
) -> str:
    """Poll once, claim at most one queued Demo run, and complete it."""

    protocol.heartbeat("idle", ["agent_demo"], datetime.now(timezone.utc).isoformat())
    run_id = protocol.next_agent_demo_run()
    if run_id is None:
        return "no_task"
    claim = protocol.claim_agent_demo_run(run_id)
    if claim is None:
        return "no_claim"
    root = Path(run_root)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    job_workspace = Path(tempfile.mkdtemp(prefix="agent-demo-job-", dir=str(root)))
    try:
        selected_provider = provider or CodexDemoProvider(
            job_workspace,
            binary=binary,
            timeout_seconds=timeout_seconds,
            readonly_dirs=(Path(bundle),),
        )
        selected_name = provider_name or ("codex_cli" if isinstance(selected_provider, CodexDemoProvider) else "scripted")
        return _run_claimed_demo(
            protocol,
            claim,
            selected_provider,
            skill_bundle=Path(bundle),
            run_root=job_workspace,
            provider_name=selected_name,
        )
    finally:
        shutil.rmtree(job_workspace, ignore_errors=True)


def _build_skill_prompt(claim: dict[str, Any], runtime: SkillRuntime, skill_id: str, question: str) -> str:
    history = claim.get("history", [])
    if not isinstance(history, list):
        raise ProtocolError("invalid demo history")
    history_lines: list[str] = []
    for message in history:
        if not isinstance(message, dict) or message.get("role") not in {"user", "assistant"} or not isinstance(message.get("content"), str):
            raise ProtocolError("invalid demo history")
        history_lines.append(f"{message['role']}: {message['content']}")
    history_text = "\n".join(history_lines) if history_lines else "（无历史消息）"
    return "\n\n".join(
        (
            f"冻结 Skill：{skill_id}",
            runtime.read_skill(skill_id),
            "当前对话历史：\n" + history_text,
            "当前用户问题：" + question,
        )
    )
