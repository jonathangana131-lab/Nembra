#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"
EXPECTED_XCCONFIG = "OTHER_SWIFT_FLAGS = $(inherited) -DNEMBRA_ES80_TODAY_RESEARCH\n"


class TodayResearchFieldCandidateWrapperTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_uses_documented_all_target_xcode_settings_channel(self):
        self.assertIn('unset SWIFT_ACTIVE_COMPILATION_CONDITIONS OTHER_SWIFT_FLAGS XCODE_XCCONFIG_FILE', self.source)
        self.assertIn('export XCODE_XCCONFIG_FILE="$TODAY_XCCONFIG"', self.source)
        self.assertIn(EXPECTED_XCCONFIG.strip(), self.source)
        self.assertNotIn("export OTHER_SWIFT_FLAGS=", self.source)
        self.assertNotIn("export SWIFT_ACTIVE_COMPILATION_CONDITIONS=", self.source)
        self.assertIn('trap cleanup EXIT', self.source)
        self.assertIn('"$CANONICAL_PRODUCER" "$@"', self.source)

    def test_executes_canonical_producer_with_exact_overlay_and_cleans_it(self):
        with tempfile.TemporaryDirectory(prefix="nembra-today-wrapper-test-") as temporary:
            root = Path(temporary)
            wrapper = root / SCRIPT.name
            producer = root / "xcode27_signed_field_candidate.sh"
            captured = root / "captured-xcconfig"
            captured_path = root / "captured-xcconfig-path"
            captured_args = root / "captured-args"

            shutil.copy2(SCRIPT, wrapper)
            wrapper.chmod(0o755)
            producer.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    set -euo pipefail
                    test -n "${{XCODE_XCCONFIG_FILE:-}}"
                    test -f "$XCODE_XCCONFIG_FILE"
                    test ! -v OTHER_SWIFT_FLAGS 2>/dev/null || test -z "${{OTHER_SWIFT_FLAGS+x}}"
                    test ! -v SWIFT_ACTIVE_COMPILATION_CONDITIONS 2>/dev/null || test -z "${{SWIFT_ACTIVE_COMPILATION_CONDITIONS+x}}"
                    /bin/cat "$XCODE_XCCONFIG_FILE" > {str(captured)!r}
                    /usr/bin/printf '%s' "$XCODE_XCCONFIG_FILE" > {str(captured_path)!r}
                    /usr/bin/printf '%s\\n' "$@" > {str(captured_args)!r}
                    """
                ),
                encoding="utf-8",
            )
            producer.chmod(0o755)

            env = os.environ.copy()
            env.update(
                {
                    "RUNNER_TEMP": str(root),
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
            self.assertEqual(captured.read_text(encoding="utf-8"), EXPECTED_XCCONFIG)
            self.assertEqual(captured_args.read_text(encoding="utf-8"), "--sentinel\nvalue\n")

            ephemeral = Path(captured_path.read_text(encoding="utf-8"))
            self.assertFalse(ephemeral.exists(), "TODAY xcconfig must be removed after producer exit")
            self.assertFalse(ephemeral.parent.exists(), "TODAY settings directory must be removed after producer exit")


if __name__ == "__main__":
    unittest.main()
