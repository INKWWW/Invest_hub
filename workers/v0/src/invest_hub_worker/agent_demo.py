"""Small local Demo runner seam.

The Demo deliberately accepts a run id supplied by the local test harness. It
does not start the production Runner, install a launch agent, or expose the
legacy Agent quota/trace/memory protocol.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

from .errors import ProtocolError
class DemoProvider(Protocol):
    def complete(self, question: str, prompt: str | None = None) -> str:
        raise NotImplementedError


class DemoRunProtocol(Protocol):
    def claim_agent_demo_run(self, run_id: str) -> dict[str, Any] | None:
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


def run_demo_once(protocol: DemoRunProtocol, run_id: str, provider: DemoProvider | None = None) -> str:
    claim = protocol.claim_agent_demo_run(run_id)
    if claim is None:
        return "no_claim"
    question = claim.get("question")
    if not isinstance(question, str) or not question.strip():
        raise ProtocolError("invalid demo question")
    prompt = claim.get("general_prompt")
    if prompt is not None and not isinstance(prompt, str):
        raise ProtocolError("invalid demo general prompt")
    answer = (provider or ScriptedDemoProvider()).complete(question, prompt)
    acknowledgement = protocol.complete_agent_demo_run(run_id, answer, "scripted")
    if acknowledgement.get("status") != "succeeded":
        raise ProtocolError("demo completion was not acknowledged")
    return "succeeded"
