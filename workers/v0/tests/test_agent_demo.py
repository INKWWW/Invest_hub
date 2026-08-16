from __future__ import annotations

import unittest

from invest_hub_worker.agent_demo import ScriptedDemoProvider, run_demo_once


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
