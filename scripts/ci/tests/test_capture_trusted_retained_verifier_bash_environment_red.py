#!/usr/bin/env python3
"""Expected-red V14 regression for post-build retained-evidence shell custody.

The trusted Simulator producer may run behind a clean Bash boundary while a candidate-written
BASH_ENV remains persisted for later Actions `run:` steps. The retained-evidence verifier is part of
the trusted Xcode subject, so it must not be possible for startup code to exit successfully before
that verifier body executes.
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
VERIFIER_NAME = "Verify retained Capture evidence against trusted resolver authority"


class TrustedRetainedVerifierBashEnvironmentRedTests(unittest.TestCase):
    def _verifier_step(self) -> str:
        source = WORKFLOW.read_text(encoding="utf-8")
        match = re.search(
            rf"(?ms)^      - name: {re.escape(VERIFIER_NAME)}\n(?P<body>.*?)(?=^      - name: |\Z)",
            source,
        )
        self.assertIsNotNone(match, "trusted retained-evidence verifier step is missing")
        return match.group("body")

    def test_bash_env_exit_zero_can_false_green_an_ordinary_verifier_shell(self) -> None:
        """Executable witness for why verifier startup custody is authority-relevant."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            startup = root / "startup.sh"
            marker = root / "verifier-body-ran"
            body = root / "verifier.sh"

            startup.write_text("exit 0\n", encoding="utf-8")
            body.write_text(
                f"printf 'ran\\n' > {str(marker)!r}\nexit 97\n",
                encoding="utf-8",
            )

            environment = os.environ.copy()
            environment["BASH_ENV"] = str(startup)
            result = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", str(body)],
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(
                result.returncode,
                0,
                "witness no longer demonstrates false-success Bash startup semantics",
            )
            self.assertFalse(
                marker.exists(),
                "verifier body unexpectedly executed after BASH_ENV exit 0",
            )

    def test_retained_evidence_verifier_starts_behind_closed_shell_environment(self) -> None:
        step = self._verifier_step()
        self.assertIn("/usr/bin/python3 -I - <<'PY'", step)
        self.assertRegex(
            step,
            r"(?m)^        shell: /usr/bin/env -i .*?/bin/bash --noprofile --norc .*?\{0\}$",
            "retained-evidence verifier is authority-bearing and must not inherit candidate BASH_ENV before its body",
        )
        self.assertIn("BASH_ENV: /dev/null", step)
        self.assertIn("ENV: /dev/null", step)
        self.assertRegex(
            step,
            r'(?m)^          EXPECTED_HEAD_SHA: \$\{\{ needs\.resolve\.outputs\.head_sha \}\}\s*$',
        )


if __name__ == "__main__":
    unittest.main()
