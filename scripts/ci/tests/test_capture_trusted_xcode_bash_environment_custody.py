#!/usr/bin/env python3
"""Regression for trusted Simulator runner Bash startup custody.

The trusted workflow streams an accepted Git blob into Bash. The Bash interpreter itself must also
cross a closed environment boundary so candidate-controlled BASH_ENV, ENV, shell functions, or
caller overrides cannot execute before the pinned producer bytes.
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
        """Keep the attack witness live so the environment boundary cannot become cargo cult."""
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
            self.assertTrue(marker.exists(), "BASH_ENV attack witness did not execute")
            self.assertEqual(marker.read_text(encoding="utf-8"), "poisoned\n")
            self.assertIn(b"pinned-stdin-ran", result.stdout)

    def test_authority_bash_interpreter_has_closed_environment(self) -> None:
        step = self._authority_step()
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', step)
        self.assertNotIn("run: scripts/ci/xcode27_simulator_capture.sh", step)

        vulnerable = re.compile(r"\|\s*/bin/bash\b", re.DOTALL)
        self.assertIsNone(
            vulnerable.search(step),
            "pinned Git bytes are piped into Bash inheriting candidate-controlled startup state",
        )
        closed_bash = re.compile(
            r"\|\s*(?:/usr/bin/)?env\s+-i\b(?:(?!^      - name: ).){0,1200}?/bin/bash\b",
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(
            closed_bash.search(step),
            "authority-producing Bash must run behind its own env -i boundary",
        )


if __name__ == "__main__":
    unittest.main()
