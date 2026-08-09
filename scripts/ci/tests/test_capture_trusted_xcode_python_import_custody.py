#!/usr/bin/env python3
"""Adversarial contract for trusted Capture Python import custody.

The default-branch authority runner executes Python both in its own inline fences and indirectly
through the pinned Simulator producer. Candidate checkout bytes must never become Python import
sources after the one-time raw-worktree audit. GitHub run identity retained by the producer must
also come from the trusted workflow context and be verified as part of retained provenance.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github" / "workflows" / "capture-xcode27-trusted-command.yml"


class TrustedXcodePythonImportCustodyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def _step(self, name: str) -> str:
        match = re.search(
            rf"(?ms)^      - name: {re.escape(name)}\n(?P<body>.*?)(?=^      - name: |\Z)",
            self.workflow,
        )
        self.assertIsNotNone(match, f"trusted workflow step is missing: {name}")
        return match.group("body")

    def test_attack_witness_plain_python_imports_candidate_working_directory(self) -> None:
        """Prove why env -i alone is not an import boundary."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / "candidate-hashlib-imported"
            (root / "hashlib.py").write_text(
                f"from pathlib import Path\nPath({str(marker)!r}).write_text('executed')\n",
                encoding="utf-8",
            )
            environment = {"PATH": "/usr/bin:/bin", "HOME": "/tmp", "LC_ALL": "C"}

            plain = subprocess.run(
                ["/usr/bin/python3", "-c", "import hashlib"],
                cwd=root,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(plain.returncode, 0, plain.stderr.decode(errors="replace"))
            self.assertTrue(marker.exists(), "plain Python did not reproduce candidate import execution")

            marker.unlink()
            isolated = subprocess.run(
                ["/usr/bin/python3", "-I", "-c", "import hashlib"],
                cwd=root,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(isolated.returncode, 0, isolated.stderr.decode(errors="replace"))
            self.assertFalse(marker.exists(), "isolated Python still imported candidate working-directory code")

    def test_inline_build_graph_verifier_uses_isolated_python(self) -> None:
        step = self._step("Verify trusted build graph custody")
        self.assertIn("/usr/bin/env -i", step)
        self.assertIn("/usr/bin/python3 -I - <<'PY'", step)
        self.assertNotIn("/usr/bin/python3 - <<'PY'", step)

    def test_pinned_producer_forces_every_python_child_through_isolated_interpreter(self) -> None:
        step = self._step("Build, test, and capture Simulator states")
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', step)
        self.assertIn('test "$materialized_blob" = "$expected_blob"', step)
        self.assertIn('python3() { /usr/bin/python3 -I "$@"; }', step)
        self.assertIn("readonly -f python3", step)
        function_at = step.index('python3() { /usr/bin/python3 -I "$@"; }')
        source_at = step.index("source /dev/stdin")
        self.assertLess(function_at, source_at)

    def test_clean_producer_environment_receives_only_trusted_github_run_identity(self) -> None:
        step = self._step("Build, test, and capture Simulator states")
        self.assertIn('GITHUB_RUN_ID="${{ github.run_id }}"', step)
        self.assertIn('GITHUB_RUN_ATTEMPT="${{ github.run_attempt }}"', step)
        self.assertNotIn('GITHUB_RUN_ID="$GITHUB_RUN_ID"', step)
        self.assertNotIn('GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT"', step)

    def test_retained_verifier_authenticates_runner_metadata_against_trusted_context(self) -> None:
        step = self._step("Verify retained Capture evidence against trusted resolver authority")
        self.assertIn('EXPECTED_GITHUB_RUN_ID: ${{ github.run_id }}', step)
        self.assertIn('EXPECTED_GITHUB_RUN_ATTEMPT: ${{ github.run_attempt }}', step)
        self.assertIn('runner_metadata_path = root / "capture-runner-metadata.json"', step)
        self.assertIn('"githubRunID"', step)
        self.assertIn('"githubRunAttempt"', step)
        self.assertIn('"externalBuildRecordSHA256"', step)
        self.assertIn("hashlib.sha256(record_path.read_bytes()).hexdigest()", step)


if __name__ == "__main__":
    unittest.main()
