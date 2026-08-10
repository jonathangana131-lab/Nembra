#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"
CURRENT_PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"


class TodayResearchFieldCandidateWrapperTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_legacy_wrapper_is_explicitly_non_authoritative(self):
        self.assertIn("SUPERSEDED:", self.source)
        self.assertIn(CURRENT_PROCEDURE, self.source)
        self.assertIn("scripts/field/install_one_time_capture.command", self.source)
        self.assertIn("PHYSICAL NO-GO", self.source)
        self.assertIn("exit 64", self.source)
        self.assertNotIn("CANONICAL_PRODUCER=", self.source)
        self.assertNotIn('exec "$CANONICAL_PRODUCER"', self.source)
        self.assertNotIn("--nembra-today-research-build", self.source)
        self.assertNotIn("NembraES80TodayResearch.xcconfig", self.source)

    def test_wrapper_never_executes_a_sibling_legacy_producer(self):
        with tempfile.TemporaryDirectory(prefix="nembra-retired-today-wrapper-test-") as temporary:
            root = Path(temporary)
            wrapper = root / SCRIPT.name
            producer = root / "xcode27_signed_field_candidate.sh"
            producer_invoked = root / "producer-invoked"

            shutil.copy2(SCRIPT, wrapper)
            wrapper.chmod(0o755)
            producer.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    set -euo pipefail
                    /usr/bin/printf 'invoked\\n' > {str(producer_invoked)!r}
                    exit 0
                    """
                ),
                encoding="utf-8",
            )
            producer.chmod(0o755)

            env = os.environ.copy()
            env.update(
                {
                    "XCODE_XCCONFIG_FILE": "/tmp/hostile.xcconfig",
                    "OTHER_SWIFT_FLAGS": "-DHOSTILE",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "HOSTILE",
                }
            )
            completed = subprocess.run(
                [str(wrapper), "--sentinel", "value"],
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 64)
            self.assertFalse(producer_invoked.exists())
            self.assertIn("SUPERSEDED:", completed.stderr)
            self.assertIn(CURRENT_PROCEDURE, completed.stderr)
            self.assertIn("scripts/field/install_one_time_capture.command", completed.stderr)
            self.assertIn("PHYSICAL NO-GO", completed.stderr)
            self.assertEqual(completed.stdout, "")


if __name__ == "__main__":
    unittest.main()
