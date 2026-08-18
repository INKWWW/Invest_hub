from __future__ import annotations

import unittest
from pathlib import Path
import tempfile
from unittest.mock import patch

import subprocess

from invest_hub_worker.agent_demo import CodexDemoProvider, ScriptedDemoProvider, run_agent_demo_once, run_agent_demo_worker_once, run_demo_once
from invest_hub_worker.errors import ProtocolError


class DemoProtocol:
    def __init__(self) -> None:
        self.claimed = False
        self.completed: tuple[str, str, str] | None = None

    def claim_agent_demo_run(self, run_id: str):
        if self.claimed:
            return None
        self.claimed = True
        return {"run_id": run_id, "question": "研究公开公司", "status": "running", "general_prompt": "general.v1 prompt"}

    def complete_agent_demo_run(self, run_id: str, content: str, provider: str):
        self.completed = (run_id, content, provider)
        return {"run_id": run_id, "status": "succeeded"}


class SkillDemoProtocol(DemoProtocol):
    def claim_agent_demo_run(self, run_id: str):
        return {
            "run_id": run_id,
            "question": "分析公开公司",
            "status": "running",
            "skill_id": "investment-research",
            "history": [],
        }


class OnlineDemoProtocol(DemoProtocol):
    def __init__(self) -> None:
        super().__init__()
        self.heartbeats: list[tuple[str, list[str]]] = []

    def heartbeat(self, status: str, capabilities: list[str], sent_at: str):
        self.heartbeats.append((status, capabilities))
        return {"status": "online"}


class PollingDemoProtocol(OnlineDemoProtocol):
    def next_agent_demo_run(self):
        return "run-1"


class AgentDemoTests(unittest.TestCase):
    def test_general_prompt_is_forwarded_to_the_provider_but_not_persisted(self) -> None:
        class CapturingProvider:
            prompt: str | None = None

            def complete(self, question: str, prompt: str | None = None) -> str:
                self.prompt = prompt
                return f"# {question}"

        provider = CapturingProvider()
        protocol = DemoProtocol()
        self.assertEqual(run_demo_once(protocol, "run-1", provider), "succeeded")
        self.assertEqual(provider.prompt, "general.v1 prompt")
        assert protocol.completed is not None
        self.assertNotIn("general.v1", protocol.completed[1])

    def test_scripted_provider_is_deterministic_and_markdown(self) -> None:
        provider = ScriptedDemoProvider()
        self.assertEqual(provider.complete("研究公开公司"), provider.complete("研究公开公司"))
        self.assertTrue(provider.complete("研究公开公司").startswith("# "))

    def test_run_once_claims_then_completes_without_raw_provider_payload(self) -> None:
        protocol = DemoProtocol()
        self.assertEqual(run_demo_once(protocol, "run-1"), "succeeded")
        assert protocol.completed is not None
        self.assertEqual(protocol.completed[0], "run-1")
        self.assertEqual(protocol.completed[2], "scripted")
        self.assertNotIn("Prompt", protocol.completed[1])

    def test_run_once_does_not_complete_when_no_run_is_claimed(self) -> None:
        protocol = DemoProtocol()
        protocol.claimed = True
        self.assertEqual(run_demo_once(protocol, "run-1"), "no_claim")
        self.assertIsNone(protocol.completed)

    def test_skill_claim_uses_frozen_skill_instructions_without_general_product_prompt(self) -> None:
        class CapturingProvider:
            prompt: str | None = None

            def complete(self, question: str, prompt: str | None = None) -> str:
                self.prompt = prompt
                return "# Skill result"

        provider = CapturingProvider()
        bundle = Path(__file__).resolve().parents[3] / "skills" / "upstream" / "d64751635308d1920bcdae234e6dd957fd79e736"
        with tempfile.TemporaryDirectory() as directory:
            protocol = SkillDemoProtocol()
            self.assertEqual(run_demo_once(protocol, "run-1", provider, skill_bundle=bundle, run_root=Path(directory)), "succeeded")

        assert provider.prompt is not None
        self.assertIn("当前用户问题：分析公开公司", provider.prompt)
        self.assertIn("investment-research", provider.prompt)
        self.assertNotIn("invest-hub.agent-demo.general.v1", provider.prompt)

    def test_codex_provider_returns_only_last_message_from_bounded_process(self) -> None:
        calls: list[tuple[list[str], str]] = []

        def runner(command: list[str], prompt: str, output_path: Path, timeout_seconds: float) -> None:
            calls.append((command, prompt))
            output_path.write_text("# 真实 Codex 结果\n", encoding="utf-8")

        with tempfile.TemporaryDirectory() as directory:
            provider = CodexDemoProvider(Path(directory), runner=runner)
            answer = provider.complete("研究公开公司", "受控 Prompt")

        self.assertEqual(answer, "# 真实 Codex 结果\n")
        self.assertEqual(calls[0][1], "受控 Prompt")
        self.assertEqual(calls[0][0][0:2], ["codex", "exec"])
        self.assertIn("--output-last-message", calls[0][0])

    def test_codex_provider_defaults_to_six_minutes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            provider = CodexDemoProvider(Path(directory))

        self.assertEqual(provider.timeout_seconds, 360.0)

    def test_timeout_after_last_message_preserves_the_answer(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            provider = CodexDemoProvider(workspace)

            def timed_out(*_args: object, **_kwargs: object) -> None:
                (workspace / "codex-last-message.md").write_text("# 已生成的回答\n", encoding="utf-8")
                raise subprocess.TimeoutExpired("codex", 360.0)

            with patch("invest_hub_worker.agent_demo.subprocess.run", side_effect=timed_out):
                answer = provider.complete("研究公开公司")

        self.assertEqual(answer, "# 已生成的回答\n")
        self.assertEqual(provider.last_execution_status, "answer_ready_with_timeout")

    def test_timeout_without_last_message_remains_a_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            provider = CodexDemoProvider(Path(directory))

            def timed_out(*_args: object, **_kwargs: object) -> None:
                raise subprocess.TimeoutExpired("codex", 360.0)

            with patch("invest_hub_worker.agent_demo.subprocess.run", side_effect=timed_out):
                with self.assertRaisesRegex(ProtocolError, "Codex process failed"):
                    provider.complete("研究公开公司")

    def test_cli_diagnostics_are_captured_locally_and_classified_safely(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            provider = CodexDemoProvider(workspace)

            def failed_process(*_args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
                stdout = kwargs["stdout"]
                stderr = kwargs["stderr"]
                assert hasattr(stdout, "write")
                assert hasattr(stderr, "write")
                stdout.write("normal progress\n")
                stderr.write("401 unauthorized: token=should-stay-local\n")
                return subprocess.CompletedProcess([], 1)

            with patch("invest_hub_worker.agent_demo.subprocess.run", side_effect=failed_process):
                with self.assertRaisesRegex(ProtocolError, "Codex process failed") as raised:
                    provider.complete("研究公开公司")

            self.assertEqual(provider.last_execution_status, "auth_failed")
            assert provider.last_diagnostic_path is not None
            self.assertTrue(provider.last_diagnostic_path.exists())
            self.assertIn("unauthorized", provider.last_diagnostic_path.read_text(encoding="utf-8"))
            self.assertNotIn("token=should-stay-local", str(raised.exception))
            self.assertEqual(provider.last_diagnostic_path.stat().st_mode & 0o777, 0o600)

    def test_cli_network_diagnostics_are_classified_without_exposing_details(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            provider = CodexDemoProvider(workspace)

            def failed_process(*_args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
                kwargs["stderr"].write("failed to lookup address information: nodename nor servname provided\n")
                return subprocess.CompletedProcess([], 1)

            with patch("invest_hub_worker.agent_demo.subprocess.run", side_effect=failed_process):
                with self.assertRaises(ProtocolError):
                    provider.complete("研究公开公司")

            self.assertEqual(provider.last_execution_status, "network_failed")

    def test_real_runner_advertises_online_and_cleans_the_run_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            protocol = OnlineDemoProtocol()
            self.assertEqual(
                run_agent_demo_once(
                    protocol,
                    "run-1",
                    bundle=root,
                    run_root=root,
                    provider=ScriptedDemoProvider(),
                ),
                "succeeded",
            )
            self.assertEqual(protocol.heartbeats, [("idle", ["agent_demo"])])
            self.assertEqual(list(root.iterdir()), [])
            assert protocol.completed is not None
            self.assertEqual(protocol.completed[2], "scripted")

    def test_polling_runner_discovers_and_completes_one_queued_run(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            protocol = PollingDemoProtocol()
            self.assertEqual(
                run_agent_demo_worker_once(
                    protocol,
                    bundle=Path(directory),
                    run_root=Path(directory),
                    provider=ScriptedDemoProvider(),
                ),
                "succeeded",
            )
            self.assertEqual(protocol.heartbeats, [("idle", ["agent_demo"])])
            assert protocol.completed is not None
            self.assertEqual(protocol.completed[0], "run-1")
