#!/usr/bin/env python3
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"


class TodayResearchFieldCandidateRetirementTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_wrapper_is_explicitly_retired_and_non_authoritative(self):
        self.assertEqual(self.source.splitlines()[0], "#!/bin/bash -p")
        self.assertIn("SUPERSEDED: the private TODAY ES80-FINGERPRINT-v1 Research candidate path is retired.", self.source)
        self.assertIn("Current Capture field procedure is ES80-AUTHENTICATED-STATIONARY-v1.", self.source)
        self.assertIn("PHYSICAL NO-GO", self.source)
        self.assertRegex(self.source, re.compile(r'(?m)^exit 64$'))

    def test_wrapper_cannot_delegate_to_signed_field_producer_or_compiler_overrides(self):
        for forbidden in (
            "CANONICAL_PRODUCER=",
            "--nembra-today-research-build",
            "XCODE_XCCONFIG_FILE",
            "OTHER_SWIFT_FLAGS",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
            "NEMBRA_ES80_TODAY_RESEARCH",
            "xcodebuild",
            "mktemp",
        ):
            self.assertNotIn(forbidden, self.source)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*(?:exec|source|\.)\s+'))

    def test_invocation_fails_closed_without_executing_caller_startup_authority(self):
        with tempfile.TemporaryDirectory(prefix="nembra-retired-today-field-wrapper-") as temporary:
            directory = Path(temporary)
            marker = directory / "caller-code-ran"
            hook = directory / "bash-env-hook.sh"
            hook.write_text(f"printf 'caller startup hook executed\\n' > {str(marker)!r}\n", encoding="utf-8")

            environment = os.environ.copy()
            environment["BASH_ENV"] = str(hook)
            environment.update(
                {
                    "XCODE_XCCONFIG_FILE": "/tmp/hostile.xcconfig",
                    "OTHER_SWIFT_FLAGS": "-DHOSTILE",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "HOSTILE",
                }
            )
            completed = subprocess.run(
                [str(SCRIPT), "--sentinel", "value"],
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 64)
            self.assertFalse(marker.exists(), "Caller BASH_ENV executed before retired wrapper fail-closed.")
            self.assertIn("SUPERSEDED", completed.stderr)
            self.assertIn("PHYSICAL NO-GO", completed.stderr)
            self.assertNotIn("hostile", completed.stdout.lower() + completed.stderr.lower())


if __name__ == "__main__":
    unittest.main()
