import os
import tempfile
import unittest
from pathlib import Path

from spike_02.cli import main


FIXTURE_PATH = "spikes/spike_02/fixtures/public_small.json"


class CLITests(unittest.TestCase):
    def test_mock_cli_requires_fixture_and_evidence_dir(self):
        self.assertEqual(main(["mock"]), 2)

    def test_glm_cli_requires_runtime_environment(self):
        old = {
            name: os.environ.pop(name, None)
            for name in (
                "SPIKE02_GLM_API_KEY",
                "SPIKE02_GLM_ENDPOINT",
                "SPIKE02_GLM_MODEL",
            )
        }
        try:
            with tempfile.TemporaryDirectory() as directory:
                code = main(
                    [
                        "glm",
                        "--fixture",
                        FIXTURE_PATH,
                        "--evidence-dir",
                        directory,
                    ]
                )
            self.assertEqual(code, 2)
        finally:
            for name, value in old.items():
                if value is not None:
                    os.environ[name] = value

    def test_mock_cli_runs_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            code = main(
                [
                    "mock",
                    "--fixture",
                    FIXTURE_PATH,
                    "--evidence-dir",
                    directory,
                    "--chunk-size",
                    "3",
                ]
            )
            self.assertEqual(code, 0)
            self.assertTrue((Path(directory) / "metrics.json").exists())


if __name__ == "__main__":
    unittest.main()
