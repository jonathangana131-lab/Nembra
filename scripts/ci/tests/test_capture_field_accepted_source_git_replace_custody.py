import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
INSTALLER = REPO_ROOT / "scripts/field/install_one_time_capture.command"


class CaptureFieldAcceptedSourceGitReplaceCustodyTests(unittest.TestCase):
    def _git(self, root: Path, *args: str, env: dict[str, str] | None = None) -> str:
        completed = subprocess.run(
            ["/usr/bin/git", *args],
            cwd=root,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        return completed.stdout.strip()

    def _accepted_source_execution_functions(self) -> str:
        source = INSTALLER.read_text(encoding="utf-8")
        verifier_marker = "read_verified_accepted_git_blob() {\n"
        verifier_end_marker = "\n}\n\nSOURCE_SHA="
        runner_marker = "run_accepted_source_python() {\n"
        runner_end_marker = "\n}\nGIT_NO_REPLACE_OBJECTS="
        self.assertEqual(
            source.count(verifier_marker),
            1,
            "field installer must expose one verified accepted-Git payload reader",
        )
        self.assertEqual(
            source.count(runner_marker),
            1,
            "field installer must expose one accepted-source Python runner",
        )
        self.assertEqual(
            source.count(verifier_end_marker),
            1,
            "verified payload reader must have one stable authority boundary",
        )
        self.assertEqual(
            source.count(runner_end_marker),
            1,
            "accepted Python runner must have one stable authority boundary",
        )

        verifier_start = source.index(verifier_marker)
        verifier_end = source.index(verifier_end_marker, verifier_start) + len("\n}\n")
        runner_start = source.index(runner_marker)
        runner_end = source.index(runner_end_marker, runner_start) + len("\n}\n")
        self.assertLess(
            verifier_end,
            runner_start,
            "verified payload reader must be established before accepted Python execution",
        )
        verifier = source[verifier_start:verifier_end]
        runner = source[runner_start:runner_end]
        self.assertIn("sys.stdout.buffer.write(source)", verifier)
        self.assertIn('read_verified_accepted_git_blob "$relative_path" |', runner)
        return verifier + "\n" + runner

    def test_field_installer_has_no_removed_mutable_guard_variable(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertNotIn(
            "$TUYA_BUILD_WINDOW_GUARD\"",
            source,
            "field installer must not dereference the removed mutable build-guard path under set -u",
        )
        self.assertIn(
            'run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"',
            source,
            "field build guard must execute from exact accepted source bytes",
        )

    def test_field_runner_is_replacement_blind_for_exact_accepted_commit(self) -> None:
        execution_functions = self._accepted_source_execution_functions()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._git(root, "init", "-q")
            self._git(root, "config", "user.name", "Capture Authority Test")
            self._git(root, "config", "user.email", "capture-authority-test@example.invalid")

            helper = root / "scripts" / "helper.py"
            helper.parent.mkdir(parents=True)
            helper.write_text('print("accepted")\n', encoding="utf-8")
            self._git(root, "add", "scripts/helper.py")
            self._git(root, "commit", "-q", "-m", "accepted source")
            accepted_sha = self._git(root, "rev-parse", "HEAD")

            helper.write_text('print("attacker")\n', encoding="utf-8")
            self._git(root, "add", "scripts/helper.py")
            self._git(root, "commit", "-q", "-m", "replacement source")
            replacement_sha = self._git(root, "rev-parse", "HEAD")
            self._git(root, "replace", accepted_sha, replacement_sha)

            ambient = os.environ.copy()
            ambient.pop("GIT_NO_REPLACE_OBJECTS", None)
            self.assertIn(
                'print("attacker")',
                self._git(root, "show", f"{accepted_sha}:scripts/helper.py", env=ambient),
                "fixture must demonstrate that an ambient replacement ref substitutes accepted commit traversal",
            )
            replacement_blind = dict(ambient)
            replacement_blind["GIT_NO_REPLACE_OBJECTS"] = "1"
            self.assertIn(
                'print("accepted")',
                self._git(root, "show", f"{accepted_sha}:scripts/helper.py", env=replacement_blind),
                "fixture sanity check must prove replacement-blind Git traversal recovers accepted bytes",
            )

            harness = root / "run-field-helper.sh"
            harness.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "die() { printf '%s\\n' \"$*\" >&2; return 1; }\n"
                f"ROOT={shlex.quote(str(root))}\n"
                f"AUTHORITY_GIT_DIR={shlex.quote(str(root / '.git'))}\n"
                f"SOURCE_SHA={shlex.quote(accepted_sha)}\n"
                + execution_functions
                + 'run_accepted_source_python "scripts/helper.py"\n',
                encoding="utf-8",
            )
            harness.chmod(0o700)
            completed = subprocess.run(
                ["/bin/bash", str(harness)],
                cwd=root,
                env=ambient,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(completed.stdout.strip(), "accepted")
            self.assertNotIn("attacker", completed.stdout)


if __name__ == "__main__":
    unittest.main()
