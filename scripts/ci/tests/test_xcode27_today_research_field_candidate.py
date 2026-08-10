#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"


class TodayResearchFieldCandidateRetirementTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_legacy_today_wrapper_is_hard_retired_and_cannot_delegate_authority(self):
        self.assertTrue(self.source.startswith("#!/bin/bash -p\n"))
        self.assertIn('PATH="/usr/bin:/bin:/usr/sbin:/sbin"', self.source)
        self.assertIn("unset BASH_ENV ENV", self.source)
        self.assertIn(
            "SUPERSEDED: the private TODAY ES80-FINGERPRINT-v1 Research candidate path is retired.",
            self.source,
        )
        self.assertIn(
            "Current Capture field procedure is ES80-AUTHENTICATED-STATIONARY-v1.",
            self.source,
        )
        self.assertIn("scripts/field/install_one_time_capture.command", self.source)
        self.assertIn(
            "PHYSICAL NO-GO: this legacy wrapper cannot authorize scanning or an ES80 experiment.",
            self.source,
        )
        self.assertIn("exit 64", self.source)

        for forbidden in (
            "--nembra-today-research-build",
            'exec "$CANONICAL_PRODUCER"',
            "xcodebuild",
            "XCODE_XCCONFIG_FILE=",
            "OTHER_SWIFT_FLAGS=",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=",
            "mktemp",
            "NembraES80TodayResearch.xcconfig",
        ):
            self.assertNotIn(forbidden, self.source)

    def test_execution_fails_closed_without_running_neighboring_producer(self):
        with tempfile.TemporaryDirectory(prefix="nembra-retired-today-wrapper-test-") as temporary:
            root = Path(temporary)
            wrapper = root / SCRIPT.name
            producer = root / "xcode27_signed_field_candidate.sh"
            producer_marker = root / "producer-ran"
            hostile_bash_env = root / "hostile-bash-env"

            shutil.copy2(SCRIPT, wrapper)
            wrapper.chmod(0o755)
            producer.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    /usr/bin/printf 'unexpected delegation\\n' > {str(producer_marker)!r}
                    exit 0
                    """
                ),
                encoding="utf-8",
            )
            producer.chmod(0o755)
            hostile_bash_env.write_text(
                f"/usr/bin/printf 'unexpected startup hook\\n' > {str(producer_marker)!r}\n",
                encoding="utf-8",
            )

            env = os.environ.copy()
            env.update(
                {
                    "BASH_ENV": str(hostile_bash_env),
                    "ENV": str(hostile_bash_env),
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

            self.assertEqual(completed.returncode, 64, completed.stderr)
            self.assertEqual(completed.stdout, "")
            self.assertIn("SUPERSEDED", completed.stderr)
            self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", completed.stderr)
            self.assertIn("PHYSICAL NO-GO", completed.stderr)
            self.assertFalse(producer_marker.exists())


if __name__ == "__main__":
    unittest.main()
