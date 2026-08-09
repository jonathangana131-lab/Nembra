#!/usr/bin/env python3
"""Regression for trusted Simulator runner Bash startup custody.

The trusted workflow may stream an accepted Git blob into Bash, but neither the Actions step shell
nor the Bash interpreter consuming that blob may inherit candidate-controlled startup environment
such as BASH_ENV from earlier workflow steps.
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
        """Keep the exploit witness: inherited BASH_ENV is executable startup authority."""
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
            self.assertTrue(marker.exists(), "BASH_ENV did not execute; regression witness is invalid")
            self.assertEqual(marker.read_text(encoding="utf-8"), "poisoned\n")
            self.assertIn(b"pinned-stdin-ran", result.stdout)

    def test_authority_step_shell_and_blob_interpreter_have_closed_environments(self) -> None:
        step = self._authority_step()
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', step)
        self.assertNotIn("run: scripts/ci/xcode27_simulator_capture.sh", step)

        self.assertRegex(
            step,
            r"(?m)^        shell: /usr/bin/env -i .*?/bin/bash --noprofile --norc .*?\{0\}$",
            "the Actions run-step shell itself must start behind env -i so inherited BASH_ENV cannot run before custody checks",
        )
        self.assertIn("BASH_ENV: /dev/null", step)
        self.assertIn("ENV: /dev/null", step)

        vulnerable = re.compile(r"\|\s*/bin/bash\b", re.DOTALL)
        self.assertIsNone(
            vulnerable.search(step),
            "pinned Git bytes are piped into Bash that inherits the step environment",
        )

        closed_bash = re.compile(
            r"\|\s*(?:/usr/bin/)?env\s+-i\b(?:(?!^      - name: ).){0,1800}?/bin/bash\s+--noprofile\s+--norc\b",
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(
            closed_bash.search(step),
            "authority-producing Bash must run behind a separate env -i boundary",
        )
        self.assertIn('GITHUB_RUN_ID="${{ github.run_id }}"', step)
        self.assertIn('GITHUB_RUN_ATTEMPT="${{ github.run_attempt }}"', step)
        self.assertIn('ARTIFACTS_DIR="${{ github.workspace }}/Artifacts/Xcode27Simulator"', step)
        self.assertIn('RUNNER_TEMP="${{ runner.temp }}"', step)
        self.assertIn('"${{ github.workspace }}/$producer_path"', step)


if __name__ == "__main__":
    unittest.main()
