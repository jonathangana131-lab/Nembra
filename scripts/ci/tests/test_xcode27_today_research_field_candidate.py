#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"
EXPECTED_MODE = "--nembra-today-research-build"


class TodayResearchFieldCandidateWrapperTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_delegates_research_authority_as_explicit_producer_mode(self):
        self.assertIn(
            'unset SWIFT_ACTIVE_COMPILATION_CONDITIONS OTHER_SWIFT_FLAGS XCODE_XCCONFIG_FILE',
            self.source,
        )
        self.assertIn(
            'exec "$CANONICAL_PRODUCER" --nembra-today-research-build "$@"',
            self.source,
        )
        self.assertNotIn("export XCODE_XCCONFIG_FILE=", self.source)
        self.assertNotIn("export OTHER_SWIFT_FLAGS=", self.source)
        self.assertNotIn("export SWIFT_ACTIVE_COMPILATION_CONDITIONS=", self.source)
        self.assertNotIn("mktemp", self.source)
        self.assertNotIn("NembraES80TodayResearch.xcconfig", self.source)

    def test_executes_canonical_producer_with_mode_and_no_ambient_build_settings(self):
        with tempfile.TemporaryDirectory(prefix="nembra-today-wrapper-test-") as temporary:
            root = Path(temporary)
            wrapper = root / SCRIPT.name
            producer = root / "xcode27_signed_field_candidate.sh"
            captured_args = root / "captured-args"
            captured_environment = root / "captured-environment"

            shutil.copy2(SCRIPT, wrapper)
            wrapper.chmod(0o755)
            producer.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    set -euo pipefail
                    test -z "${{XCODE_XCCONFIG_FILE+x}}"
                    test -z "${{OTHER_SWIFT_FLAGS+x}}"
                    test -z "${{SWIFT_ACTIVE_COMPILATION_CONDITIONS+x}}"
                    /usr/bin/printf '%s\\n' "$@" > {str(captured_args)!r}
                    /usr/bin/printf 'clean\\n' > {str(captured_environment)!r}
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
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                captured_args.read_text(encoding="utf-8"),
                f"{EXPECTED_MODE}\n--sentinel\nvalue\n",
            )
            self.assertEqual(captured_environment.read_text(encoding="utf-8"), "clean\n")


if __name__ == "__main__":
    unittest.main()
