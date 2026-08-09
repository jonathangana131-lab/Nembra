#!/usr/bin/env python3
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
TODAY_WRAPPER = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"
CLOSED_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"


class SignedFieldCandidateProcessStartupCustodyTests(unittest.TestCase):
    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_shell_starts_in_privileged_mode_before_bash_env_can_execute(self):
        self.assertEqual(
            self.source.splitlines()[0],
            "#!/bin/bash -p",
            "Direct release invocation must suppress BASH_ENV/ENV and inherited shell startup authority before producer line 1 executes.",
        )

    def test_malicious_bash_env_cannot_execute_before_producer_body(self):
        with tempfile.TemporaryDirectory(prefix="nembra-producer-startup-custody-") as temporary:
            directory = Path(temporary)
            marker = directory / "bash-env-ran"
            hook = directory / "malicious-bash-env.sh"
            hook.write_text('printf "caller startup hook executed\\n" > "$NEMBRA_BASH_ENV_MARKER"\n')

            environment = os.environ.copy()
            environment["BASH_ENV"] = str(hook)
            environment["NEMBRA_BASH_ENV_MARKER"] = str(marker)
            completed = subprocess.run(
                [str(PRODUCER)],
                cwd=PRODUCER.parents[2],
                env=environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertFalse(
                marker.exists(),
                "Caller BASH_ENV executed before the producer established its release authority boundary.",
            )

    def test_closed_path_is_established_immediately_after_shell_options(self):
        expected = (
            'set -euo pipefail\n'
            f'PATH="{CLOSED_PATH}"\n'
            'export PATH\n'
        )
        self.assertIn(expected, self.source)

        path_index = self.source.index(f'PATH="{CLOSED_PATH}"')
        root_index = self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"')
        uname_index = self.source.index('if [[ "$(uname -s)" != "Darwin" ]]')
        self.assertLess(path_index, root_index)
        self.assertLess(path_index, uname_index)

    def test_caller_path_cannot_be_restored_by_plain_or_export_assignment(self):
        assignments = re.findall(r'(?m)^\s*(?:export\s+)?PATH\s*=', self.source)
        self.assertEqual(assignments, ["PATH="])
        self.assertNotRegex(
            self.source,
            re.compile(r'(?m)^\s*(?:export\s+)?PATH\s*=.*\$\{?PATH\}?'),
        )

    def test_closed_path_components_are_custody_checked_before_unqualified_children(self):
        validation = self.source.index('for SYSTEM_PATH_COMPONENT in /usr/bin /bin /usr/sbin /sbin; do')
        root = self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"')
        self.assertLess(validation, root)
        self.assertIn('validate_root_custodied_path "$SYSTEM_PATH_COMPONENT" directory', self.source)

    def test_python_remains_pinned_and_isolated(self):
        self.assertIn('PYTHON3="/usr/bin/python3"', self.source)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*python3(?:\s|$)'))

        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations)
        for invocation in invocations:
            self.assertRegex(invocation, re.compile(r'"\$PYTHON3"\s+-I(?:\s|$)'))


class TodayResearchFieldCandidateProcessStartupCustodyTests(unittest.TestCase):
    def setUp(self):
        self.source = TODAY_WRAPPER.read_text()

    def test_shell_starts_privileged_and_closes_path_before_directory_resolution(self):
        self.assertEqual(self.source.splitlines()[0], "#!/bin/bash -p")
        expected = (
            'set -euo pipefail\n'
            f'PATH="{CLOSED_PATH}"\n'
            'export PATH\n'
            'unset BASH_ENV ENV\n'
        )
        self.assertIn(expected, self.source)

        path_index = self.source.index(f'PATH="{CLOSED_PATH}"')
        script_dir_index = self.source.index('SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"')
        producer_index = self.source.index('CANONICAL_PRODUCER="$SCRIPT_DIR/xcode27_signed_field_candidate.sh"')
        self.assertLess(path_index, script_dir_index)
        self.assertLess(path_index, producer_index)

    def test_hostile_caller_path_cannot_redirect_canonical_producer_resolution(self):
        with tempfile.TemporaryDirectory(prefix="nembra-today-wrapper-path-custody-") as temporary:
            directory = Path(temporary)
            hostile_bin = directory / "bin"
            hostile_producer_dir = directory / "producer"
            hostile_bin.mkdir()
            hostile_producer_dir.mkdir()

            dirname_marker = directory / "hostile-dirname-ran"
            producer_marker = directory / "hostile-producer-ran"
            hostile_dirname = hostile_bin / "dirname"
            hostile_dirname.write_text(
                "#!/bin/sh\n"
                f"printf 'hostile dirname executed\\n' > '{dirname_marker}'\n"
                f"printf '%s\\n' '{hostile_producer_dir}'\n"
            )
            hostile_dirname.chmod(0o755)

            hostile_producer = hostile_producer_dir / "xcode27_signed_field_candidate.sh"
            hostile_producer.write_text(
                "#!/bin/sh\n"
                f"printf 'hostile producer executed\\n' > '{producer_marker}'\n"
                "exit 0\n"
            )
            hostile_producer.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{hostile_bin}:{environment.get('PATH', '')}"
            completed = subprocess.run(
                [str(TODAY_WRAPPER)],
                cwd=TODAY_WRAPPER.parents[2],
                env=environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )

            self.assertNotEqual(
                completed.returncode,
                0,
                "The real canonical producer should fail closed in this non-field test environment.",
            )
            self.assertFalse(dirname_marker.exists(), "Caller PATH selected a hostile dirname before custody closed.")
            self.assertFalse(producer_marker.exists(), "Caller PATH redirected the TODAY wrapper to a hostile producer.")

    def test_wrapper_never_restores_caller_path(self):
        assignments = re.findall(r'(?m)^\s*(?:export\s+)?PATH\s*=', self.source)
        self.assertEqual(assignments, ["PATH="])
        self.assertNotRegex(
            self.source,
            re.compile(r'(?m)^\s*(?:export\s+)?PATH\s*=.*\$\{?PATH\}?'),
        )


if __name__ == "__main__":
    unittest.main()
