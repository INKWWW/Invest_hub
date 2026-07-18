from __future__ import annotations

import unittest

from invest_hub_worker.cli import build_parser


class WorkerCliTests(unittest.TestCase):
    def test_run_once_requires_private_runtime_inputs_as_cli_arguments(self) -> None:
        parser = build_parser()
        args = parser.parse_args(
            [
                "run-once",
                "--config", "/private/config.toml",
                "--credential", "/private/credentials.json",
                "--opencli-contract", "/private/contract.json",
                "--prompt-path", "/private/prompt.md",
                "--evidence-dir", "/private/evidence",
            ]
        )
        self.assertEqual(args.command, "run-once")
        self.assertEqual(args.prompt_path, "/private/prompt.md")


if __name__ == "__main__":
    unittest.main()
