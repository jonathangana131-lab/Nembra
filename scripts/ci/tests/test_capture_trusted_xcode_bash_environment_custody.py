#!/usr/bin/env python3
"""Expected-red regression for trusted Simulator runner Bash startup custody.

The trusted workflow may stream an accepted Git blob into Bash, but the Bash interpreter itself
must not inherit candidate-controlled startup environment such as BASH_ENV from earlier workflow
steps. This test is validation-only until the production workflow closes that boundary.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"


class TrustedRunnerBashEnvironmentCustodyTests(unittest.TestCase):
    def _authority_step(self) -> str:
        source = WORKFLOW.read_text(encoding="utf-8")
        match = re.search(
            r"(?ms)^      - name: Build, test, and capture Simulator states\n(?P<body>.*?)(?=^      - name: |\Z)",
            source,
        )
        self.assertIsNotNone(match, "trusted authority-producing Simulator step is missing")
        return match.group("body")

    def test_noninteractive_bash_executes_inherited_bash_env_before_pinned_stdin(self) -> None:
        """Prove the environment variable is executable startup authority, not inert metadata."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / "bash-env-ran"
            startup = root / "startup.sh"
            startup.write_text(f"printf 'poisoned\\n' > {str(marker)!r}\n", encoding="utf-8")

            environment = os.environ.copy()
            environment["BASH_ENV"] = str(startup)
            result = subprocess.run(
                ["/bin/bash", "-c", "source /dev/stdin", "trusted-runner"],
                input=b"printf 'pinned-stdin-ran\\n'\n",
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertTrue(marker.exists(), "BASH_ENV did not execute; validation witness is invalid")
            self.assertEqual(marker.read_text(encoding="utf-8"), "poisoned\n")
            self.assertIn(b"pinned-stdin-ran", result.stdout)

    def test_authority_bash_interpreter_has_closed_environment(self) -> None:
        """The interpreter consuming the pinned blob must cross its own env-i boundary."""
        step = self._authority_step()
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', step)
        self.assertNotIn("run: scripts/ci/xcode27_simulator_capture.sh", step)

        vulnerable = re.compile(r"\|\s*/bin/bash\b", re.DOTALL)
        self.assertIsNone(
            vulnerable.search(step),
            "pinned Git bytes are piped into Bash that inherits the job environment; BASH_ENV can execute before /dev/stdin",
        )

        closed_bash = re.compile(
            r"\|\s*(?:/usr/bin/)?env\s+-i\b(?:(?!^      - name: ).){0,1200}?/bin/bash\b",
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(
            closed_bash.search(step),
            "authority-producing Bash must run behind a separate env -i boundary so BASH_ENV, ENV, shell functions, and caller overrides are absent",
        )


if __name__ == "__main__":
    unittest.main()
