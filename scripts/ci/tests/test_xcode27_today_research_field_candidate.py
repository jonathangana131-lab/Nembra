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
        self.assertIn('exec 6< "$TODAY_XCCONFIG"', self.source)
        self.assertIn('/bin/rm -f "$TODAY_XCCONFIG"', self.source)
        self.assertIn('/bin/rmdir "$TODAY_SETTINGS_ROOT"', self.source)
        self.assertIn('/usr/bin/python3 -I - 6', self.source)
        self.assertIn('os.pread(fd, len(expected) + 1, 0)', self.source)
        self.assertIn('export XCODE_XCCONFIG_FILE="/dev/fd/6"', self.source)
        self.assertIn(EXPECTED_XCCONFIG.strip(), self.source)
        self.assertNotIn("export OTHER_SWIFT_FLAGS=", self.source)
        self.assertNotIn("export SWIFT_ACTIVE_COMPILATION_CONDITIONS=", self.source)
        self.assertIn('trap cleanup EXIT', self.source)
        self.assertIn('"$CANONICAL_PRODUCER" "$@"', self.source)

    def test_executes_canonical_producer_with_unlinked_exact_overlay(self):
        with tempfile.TemporaryDirectory(prefix="nembra-today-wrapper-test-") as temporary:
            root = Path(temporary)
            wrapper = root / SCRIPT.name
            producer = root / "xcode27_signed_field_candidate.sh"
            captured = root / "captured-xcconfig"
            captured_path = root / "captured-xcconfig-path"
            captured_args = root / "captured-args"
            leaked_path_flag = root / "leaked-path"

            shutil.copy2(SCRIPT, wrapper)
            wrapper.chmod(0o755)
            producer.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    set -euo pipefail
                    test -n "${{XCODE_XCCONFIG_FILE:-}}"
                    test "$XCODE_XCCONFIG_FILE" = "/dev/fd/6"
                    test -r "$XCODE_XCCONFIG_FILE"
                    test ! -v OTHER_SWIFT_FLAGS 2>/dev/null || test -z "${{OTHER_SWIFT_FLAGS+x}}"
                    test ! -v SWIFT_ACTIVE_COMPILATION_CONDITIONS 2>/dev/null || test -z "${{SWIFT_ACTIVE_COMPILATION_CONDITIONS+x}}"
                    if /usr/bin/find "$RUNNER_TEMP" -maxdepth 1 -name 'NembraES80TodayResearch.*' -print -quit | /usr/bin/grep -q .; then
                      /usr/bin/touch {str(leaked_path_flag)!r}
                      exit 91
                    fi
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
            self.assertFalse(leaked_path_flag.exists(), "producer must start after mutable xcconfig pathname removal")
            self.assertEqual(captured.read_text(encoding="utf-8"), EXPECTED_XCCONFIG)
            self.assertEqual(captured_path.read_text(encoding="utf-8"), "/dev/fd/6")
            self.assertEqual(captured_args.read_text(encoding="utf-8"), "--sentinel\nvalue\n")
            self.assertEqual(
                list(root.glob("NembraES80TodayResearch.*")),
                [],
                "TODAY settings pathname must stay absent after producer exit",
            )

    def test_rejects_noncanonical_opened_overlay_before_producer(self):
        with tempfile.TemporaryDirectory(prefix="nembra-today-wrapper-substitution-") as temporary:
            root = Path(temporary)
            wrapper = root / SCRIPT.name
            producer = root / "xcode27_signed_field_candidate.sh"
            producer_ran = root / "producer-ran"

            source = self.source.replace(
                EXPECTED_XCCONFIG,
                "MALICIOUS_BUILD_SETTING = 1\n",
                1,
            )
            self.assertNotEqual(source, self.source, "test must mutate the generated overlay bytes")
            self.assertIn(EXPECTED_XCCONFIG.strip(), source, "descriptor verifier must retain canonical expected bytes")
            wrapper.write_text(source, encoding="utf-8")
            wrapper.chmod(0o755)

            producer.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    set -euo pipefail
                    /usr/bin/touch {str(producer_ran)!r}
                    exit 0
                    """
                ),
                encoding="utf-8",
            )
            producer.chmod(0o755)

            env = os.environ.copy()
            env["RUNNER_TEMP"] = str(root)
            completed = subprocess.run(
                [str(wrapper)],
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 3, completed.stderr)
            self.assertFalse(producer_ran.exists(), "noncanonical descriptor must fail before producer delegation")
            self.assertIn("descriptor failed exact opened-subject verification", completed.stderr)
            self.assertEqual(
                list(root.glob("NembraES80TodayResearch.*")),
                [],
                "failed verification must not leave a mutable TODAY settings pathname",
            )


if __name__ == "__main__":
    unittest.main()