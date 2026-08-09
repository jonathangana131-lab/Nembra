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

    def test_today_entry_point_closes_caller_git_source_redirection(self):
        for variable in (
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_COMMON_DIR",
            "GIT_INDEX_FILE",
            "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_NAMESPACE",
            "GIT_SHALLOW_FILE",
            "GIT_GRAFT_FILE",
            "GIT_CEILING_DIRECTORIES",
            "GIT_DISCOVERY_ACROSS_FILESYSTEM",
            "GIT_CONFIG",
            "GIT_CONFIG_SYSTEM",
            "GIT_CONFIG_COUNT",
            "GIT_CONFIG_PARAMETERS",
        ):
            self.assertIn(f'-u {variable}', self.source)

        for assignment in (
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
            "GIT_NO_REPLACE_OBJECTS=1",
            "GIT_ATTR_NOSYSTEM=1",
        ):
            self.assertIn(assignment, self.source)

        self.assertLess(self.source.index('/usr/bin/env \\\n'), self.source.rindex('"$CANONICAL_PRODUCER" "$@"'))

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
                    test -z "${{GIT_DIR+x}}"
                    test -z "${{GIT_WORK_TREE+x}}"
                    test -z "${{GIT_COMMON_DIR+x}}"
                    test -z "${{GIT_INDEX_FILE+x}}"
                    test -z "${{GIT_OBJECT_DIRECTORY+x}}"
                    test -z "${{GIT_ALTERNATE_OBJECT_DIRECTORIES+x}}"
                    test -z "${{GIT_NAMESPACE+x}}"
                    test -z "${{GIT_SHALLOW_FILE+x}}"
                    test -z "${{GIT_GRAFT_FILE+x}}"
                    test -z "${{GIT_CEILING_DIRECTORIES+x}}"
                    test -z "${{GIT_DISCOVERY_ACROSS_FILESYSTEM+x}}"
                    test -z "${{GIT_CONFIG+x}}"
                    test -z "${{GIT_CONFIG_SYSTEM+x}}"
                    test -z "${{GIT_CONFIG_COUNT+x}}"
                    test -z "${{GIT_CONFIG_PARAMETERS+x}}"
                    test "${{GIT_CONFIG_NOSYSTEM:-}}" = "1"
                    test "${{GIT_CONFIG_GLOBAL:-}}" = "/dev/null"
                    test "${{GIT_NO_REPLACE_OBJECTS:-}}" = "1"
                    test "${{GIT_ATTR_NOSYSTEM:-}}" = "1"
                    test "${{NEMBRA_SIGNING_SENTINEL:-}}" = "preserved"
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
                    "GIT_DIR": "/tmp/hostile.git",
                    "GIT_WORK_TREE": "/tmp/hostile-worktree",
                    "GIT_COMMON_DIR": "/tmp/hostile-common",
                    "GIT_INDEX_FILE": "/tmp/hostile-index",
                    "GIT_OBJECT_DIRECTORY": "/tmp/hostile-objects",
                    "GIT_ALTERNATE_OBJECT_DIRECTORIES": "/tmp/hostile-alternates",
                    "GIT_NAMESPACE": "hostile",
                    "GIT_SHALLOW_FILE": "/tmp/hostile-shallow",
                    "GIT_GRAFT_FILE": "/tmp/hostile-grafts",
                    "GIT_CEILING_DIRECTORIES": "/tmp",
                    "GIT_DISCOVERY_ACROSS_FILESYSTEM": "1",
                    "GIT_CONFIG": "/tmp/hostile-gitconfig",
                    "GIT_CONFIG_SYSTEM": "/tmp/hostile-system-gitconfig",
                    "GIT_CONFIG_COUNT": "1",
                    "GIT_CONFIG_KEY_0": "core.worktree",
                    "GIT_CONFIG_VALUE_0": "/tmp/hostile-worktree-from-config",
                    "GIT_CONFIG_PARAMETERS": "'core.worktree'='/tmp/hostile-parameters-worktree'",
                    "GIT_CONFIG_NOSYSTEM": "0",
                    "GIT_CONFIG_GLOBAL": "/tmp/hostile-global-gitconfig",
                    "GIT_NO_REPLACE_OBJECTS": "0",
                    "GIT_ATTR_NOSYSTEM": "0",
                    "NEMBRA_SIGNING_SENTINEL": "preserved",
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
