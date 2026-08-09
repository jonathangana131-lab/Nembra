#!/usr/bin/env python3
"""Regression for trusted Capture Bash startup and cross-step environment custody.

The trusted workflow streams an accepted Git blob into Bash. Both the GitHub-created authority step
shell and the inner Bash interpreter must cross explicit startup boundaries so candidate-controlled
BASH_ENV, ENV, exported shell functions, or GITHUB_PATH command substitution cannot run before the
pinned producer or its retained-evidence verifier. The clean inner environment must still receive
the trusted GitHub run identity that the frozen producer records as retained provenance.
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
TRUSTED_PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
TRUSTED_PRODUCER_BLOB_SHA = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"
PRIVILEGED_SHELL = 'shell: "/bin/bash --noprofile --norc -p -e -o pipefail {0}"'


class TrustedRunnerBashEnvironmentCustodyTests(unittest.TestCase):
    def _step(self, name: str) -> str:
        source = WORKFLOW.read_text(encoding="utf-8")
        match = re.search(
            rf"(?ms)^      - name: {re.escape(name)}\n(?P<body>.*?)(?=^      - name: |\Z)",
            source,
        )
        self.assertIsNotNone(match, f"trusted workflow step is missing: {name}")
        return match.group("body")

    def test_noninteractive_bash_executes_inherited_bash_env_before_pinned_stdin(self) -> None:
        """Keep the attack witness live so the startup boundary cannot become cargo cult."""
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

    def test_privileged_bash_ignores_inherited_bash_env(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / "privileged-bash-env-ran"
            startup = root / "startup.sh"
            startup.write_text(f"printf 'poisoned\\n' > {str(marker)!r}\n", encoding="utf-8")

            environment = os.environ.copy()
            environment["BASH_ENV"] = str(startup)
            result = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-p", "-c", "printf 'trusted-body-ran\\n'"],
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertFalse(marker.exists(), "privileged Bash processed inherited BASH_ENV")
            self.assertEqual(result.stdout, b"trusted-body-ran\n")

    def test_authority_step_shell_is_privileged_and_inner_interpreter_is_closed(self) -> None:
        step = self._step("Build, test, and capture Simulator states")
        self.assertIn(PRIVILEGED_SHELL, step)
        self.assertIn('BASH_ENV: ""', step)
        self.assertIn('ENV: ""', step)
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', step)
        self.assertIn('/usr/bin/env -i', step)
        self.assertNotIn("run: scripts/ci/xcode27_simulator_capture.sh", step)

        vulnerable = re.compile(r"\|\s*/bin/bash\b", re.DOTALL)
        self.assertIsNone(
            vulnerable.search(step),
            "pinned Git bytes are piped into Bash inheriting candidate-controlled startup state",
        )
        closed_bash = re.compile(
            r"builtin printf '%s' \"\$producer_bytes\" \|\s*/usr/bin/env\s+-i\b"
            r"(?:(?!builtin printf).)*?GITHUB_RUN_ID=\"\$\{\{ github\.run_id \}\}\""
            r"(?:(?!builtin printf).)*?/bin/bash\s+--noprofile\s+--norc\s+-p\s+-c\s+"
            r"'source /dev/stdin'",
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(
            closed_bash.search(step),
            "authority-producing Bash must consume pinned producer bytes behind the closed env -i boundary",
        )

    def test_clean_inner_environment_preserves_trusted_run_identity_for_pinned_producer(self) -> None:
        custody_step = self._step("Verify trusted Simulator evidence-producer custody")
        build_step = self._step("Build, test, and capture Simulator states")
        expected_path = f'producer_path="{TRUSTED_PRODUCER_PATH}"'
        expected_blob = f'expected_blob="{TRUSTED_PRODUCER_BLOB_SHA}"'

        # Bind this regression to the producer object the trusted workflow actually admits. The
        # default-branch worktree copy is not the Capture candidate and can legitimately be a
        # different blob, so reading it here would test the wrong authority subject.
        self.assertIn(expected_path, custody_step)
        self.assertIn(expected_blob, custody_step)
        self.assertIn('/usr/bin/git rev-parse --verify "HEAD:${producer_path}"', custody_step)
        self.assertIn('test "$actual_blob" = "$expected_blob"', custody_step)

        self.assertIn(expected_path, build_step)
        self.assertIn(expected_blob, build_step)
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', build_step)
        self.assertIn('test "$materialized_blob" = "$expected_blob"', build_step)
        self.assertIn('GITHUB_RUN_ID="${{ github.run_id }}"', build_step)
        self.assertIn('GITHUB_RUN_ATTEMPT="${{ github.run_attempt }}"', build_step)
        self.assertNotIn('GITHUB_RUN_ID="$GITHUB_RUN_ID"', build_step)
        self.assertNotIn('GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT"', build_step)

    def test_retained_evidence_step_cannot_reopen_candidate_bash_startup_authority(self) -> None:
        step = self._step("Verify retained Capture evidence against trusted resolver authority")
        self.assertIn(PRIVILEGED_SHELL, step)
        self.assertIn('BASH_ENV: ""', step)
        self.assertIn('ENV: ""', step)
        self.assertIn("/usr/bin/python3 -I - <<'PY'", step)


if __name__ == "__main__":
    unittest.main()
