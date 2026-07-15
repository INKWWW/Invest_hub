import unittest
from unittest.mock import patch

from spike_01.preflight import PreflightError, check_opencli


class PreflightTests(unittest.TestCase):
    @patch("spike_01.preflight.subprocess.run")
    def test_missing_executable_is_reported(self, run):
        run.side_effect = FileNotFoundError("opencli not found")
        with self.assertRaisesRegex(PreflightError, "executable not found"):
            check_opencli("opencli")

    @patch("spike_01.preflight.subprocess.run")
    def test_version_is_returned(self, run):
        run.return_value.stdout = "opencli 1.2.3\n"
        run.return_value.stderr = ""
        run.return_value.returncode = 0
        result = check_opencli("opencli")
        self.assertEqual(result.executable, "opencli")
        self.assertEqual(result.version, "opencli 1.2.3")


if __name__ == "__main__":
    unittest.main()
