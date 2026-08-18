from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from invest_hub_worker.agent_demo import run_demo_once
from invest_hub_worker.skill_runtime import SkillRuntime, SkillRuntimeError


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
FROZEN_BUNDLE = (
    REPOSITORY_ROOT
    / "skills"
    / "upstream"
    / "d64751635308d1920bcdae234e6dd957fd79e736"
)


class SkillRuntimeTests(unittest.TestCase):
    def test_claimed_investment_research_run_uses_full_frozen_skill_prompt(self) -> None:
        class CapturingProvider:
            prompt: str | None = None

            def complete(self, question: str, prompt: str | None = None) -> str:
                self.prompt = prompt
                return "# 合成测试回答"

        class ClaimProtocol:
            def __init__(self) -> None:
                self.completed: tuple[str, str, str] | None = None

            def claim_agent_demo_run(self, run_id: str) -> dict[str, object]:
                return {
                    "run_id": run_id,
                    "question": "请分析一家公开上市公司的长期竞争优势，区分事实、判断和待核实项。",
                    "invocation_mode": "explicit",
                    "skill_id": "investment-research",
                }

            def complete_agent_demo_run(self, run_id: str, content: str, provider: str) -> dict[str, object]:
                self.completed = (run_id, content, provider)
                return {"status": "succeeded"}

        provider = CapturingProvider()
        protocol = ClaimProtocol()
        expected_skill = (FROZEN_BUNDLE / "investment-research" / "SKILL.md").read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(
                run_demo_once(protocol, "run-research", provider, skill_bundle=FROZEN_BUNDLE, run_root=Path(directory)),
                "succeeded",
            )

        self.assertIsNotNone(protocol.completed)
        self.assertIsNotNone(provider.prompt)
        assert provider.prompt is not None
        self.assertIn(expected_skill, provider.prompt)
        self.assertIn("当前用户问题：请分析一家公开上市公司的长期竞争优势，区分事实、判断和待核实项。", provider.prompt)

    def test_loads_only_the_three_frozen_skills_and_explicit_tools(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime = SkillRuntime(FROZEN_BUNDLE, Path(directory) / "run")

            for skill_id in (
                "investment-research",
                "portfolio-review",
                "investment-checklist",
            ):
                content = runtime.read_skill(skill_id)
                self.assertIn(f"name: {skill_id}", content)

            self.assertTrue(runtime.tool_path("financial_rigor.py").is_file())
            self.assertTrue(runtime.tool_path("report_audit.py").is_file())
            with self.assertRaises(SkillRuntimeError):
                runtime.read_skill("unknown-skill")
            with self.assertRaises(SkillRuntimeError):
                runtime.tool_path("arbitrary.py")

    def test_writes_are_confined_to_the_run_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / "run"
            runtime = SkillRuntime(FROZEN_BUNDLE, run)

            report = runtime.write_run_text("reports/result.md", "# report")

            self.assertEqual(report, runtime.run_workspace / "reports" / "result.md")
            self.assertEqual(report.read_text(encoding="utf-8"), "# report")
            self.assertFalse((root / "reports" / "result.md").exists())

            for path in ("/tmp/escape.md", "../escape.md", "reports/../../escape.md"):
                with self.subTest(path=path), self.assertRaises(SkillRuntimeError):
                    runtime.write_run_text(path, "must not write")

    def test_explicit_helpers_run_from_the_current_run_without_writing_shared_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime = SkillRuntime(FROZEN_BUNDLE, Path(directory) / "run")
            for tool_name in ("financial_rigor.py", "report_audit.py"):
                result = runtime.run_tool(tool_name, ("--help",))
                self.assertEqual(result.returncode, 0)
                self.assertTrue(result.stdout)
            self.assertEqual(list(Path(directory).glob("*.md")), [])
            with self.assertRaises(SkillRuntimeError):
                runtime.write_run_text(
                    runtime.bundle_root / "investment-research" / "SKILL.md",
                    "must not write",
                )

    def test_rejects_symlinked_run_root_parents_and_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = SkillRuntime(FROZEN_BUNDLE, root / "run")

            outside = root / "outside"
            outside.mkdir()
            parent_link = runtime.run_workspace / "linked"
            parent_link.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(SkillRuntimeError):
                runtime.write_run_text("linked/escape.md", "must not write")
            self.assertFalse((outside / "escape.md").exists())

            safe = runtime.write_run_text("safe.md", "original")
            target = root / "target.md"
            safe.unlink()
            safe.symlink_to(target)
            with self.assertRaises(SkillRuntimeError):
                runtime.write_run_text("safe.md", "must not follow")
            self.assertFalse(target.exists())

    def test_rejects_symlinked_bundle_entries_and_symlinked_run_root(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run_target = root / "real-run"
            run_target.mkdir()
            run_link = root / "run-link"
            run_link.symlink_to(run_target, target_is_directory=True)
            with self.assertRaises(SkillRuntimeError):
                SkillRuntime(FROZEN_BUNDLE, run_link)

            copied_bundle = root / "bundle"
            copied_bundle.mkdir()
            skill_dir = copied_bundle / "investment-research"
            skill_dir.mkdir()
            (skill_dir / "SKILL.md").symlink_to(
                FROZEN_BUNDLE / "investment-research" / "SKILL.md"
            )
            for skill_id in ("portfolio-review", "investment-checklist"):
                target_dir = copied_bundle / skill_id
                target_dir.mkdir()
                (target_dir / "SKILL.md").write_text(
                    f"---\nname: {skill_id}\n---\n", encoding="utf-8"
                )
            tools = copied_bundle / "tools"
            tools.mkdir()
            for tool_name in ("financial_rigor.py", "report_audit.py"):
                (tools / tool_name).write_text("# tool\n", encoding="utf-8")
            (copied_bundle / "provenance.json").write_text(
                (FROZEN_BUNDLE / "provenance.json").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            with self.assertRaises(SkillRuntimeError):
                SkillRuntime(copied_bundle, run_target)


if __name__ == "__main__":
    unittest.main()
