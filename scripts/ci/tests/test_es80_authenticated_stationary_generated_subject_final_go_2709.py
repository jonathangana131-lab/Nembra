#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go_2709.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go_2709", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load #2709 generated-subject Final-GO adapter")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = "1" * 40
DIGEST = "ab" * 32
BLOB = "2" * 40


def git(root: Path, *args: str) -> str:
    process = subprocess.run(
        ["/usr/bin/git", "-C", str(root), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.returncode != 0:
        raise AssertionError(process.stderr)
    return process.stdout.strip()


class AdapterTests(unittest.TestCase):
    def test_selected_helper_executes_exact_source_blob_after_worktree_substitution(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-helper-exec-") as temporary:
            root = Path(temporary)
            git(root, "init", "-q")
            git(root, "config", "user.email", "nembra-test@example.invalid")
            git(root, "config", "user.name", "Nembra Test")
            helper = root / MODULE.GENERATED_HELPER_PATH
            helper.parent.mkdir(parents=True)
            accepted = (
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "expected = ['--lockfile', sys.argv[2], '--pods', sys.argv[4], '--workspace', sys.argv[6]]\n"
                "if sys.argv[1:] != expected:\n"
                "    raise SystemExit(9)\n"
                f"print('{DIGEST}')\n"
            )
            helper.write_text(accepted, encoding="utf-8")
            git(root, "add", MODULE.GENERATED_HELPER_PATH)
            git(root, "commit", "-qm", "accepted generated helper")
            source = git(root, "rev-parse", "HEAD")

            # Model #2771: all earlier worktree/blob prechecks have completed,
            # then the same-UID checkout pathname is replaced before derivation.
            attacker_digest = "cd" * 32
            helper.write_text(
                "#!/usr/bin/env python3\n"
                f"print('{attacker_digest}')\n",
                encoding="utf-8",
            )
            value = MODULE._current_generated_subject(root, source)
            self.assertEqual(value, DIGEST)
            self.assertNotEqual(value, attacker_digest)
            accepted_blob, raw = MODULE._accepted_helper_bytes(root, source)
            self.assertEqual(accepted_blob, git(root, "rev-parse", f"{source}:{MODULE.GENERATED_HELPER_PATH}"))
            self.assertEqual(raw.decode("utf-8"), accepted)

    def test_selected_helper_blob_reader_ignores_git_replace_objects(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-helper-replace-") as temporary:
            root = Path(temporary)
            git(root, "init", "-q")
            git(root, "config", "user.email", "nembra-test@example.invalid")
            git(root, "config", "user.name", "Nembra Test")
            helper = root / MODULE.GENERATED_HELPER_PATH
            helper.parent.mkdir(parents=True)
            helper.write_text(f"print('{DIGEST}')\n", encoding="utf-8")
            git(root, "add", MODULE.GENERATED_HELPER_PATH)
            git(root, "commit", "-qm", "accepted helper")
            source = git(root, "rev-parse", "HEAD")
            accepted_blob = git(root, "rev-parse", f"{source}:{MODULE.GENERATED_HELPER_PATH}")

            # A replacement ref for the helper blob would normally redirect
            # object lookup. The production reader explicitly sets
            # GIT_NO_REPLACE_OBJECTS=1, so accepted bytes remain authoritative.
            attacker_blob = subprocess.run(
                ["/usr/bin/git", "-C", str(root), "hash-object", "-w", "--stdin"],
                input=b"print('attacker')\n",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            ).stdout.decode().strip()
            replace_ref = root / ".git" / "refs" / "replace" / accepted_blob
            replace_ref.parent.mkdir(parents=True, exist_ok=True)
            replace_ref.write_text(attacker_blob + "\n", encoding="ascii")

            observed_blob, raw = MODULE._accepted_helper_bytes(root, source)
            self.assertEqual(observed_blob, accepted_blob)
            self.assertEqual(raw, f"print('{DIGEST}')\n".encode())

    def test_candidate_authority_matches_selected_helper_guard_and_domain(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-2709-") as temporary:
            root = Path(temporary)
            contents = {
                "Scripts/bootstrap_capture_tuya_sdk.sh": (
                    MODULE.core.GENERATED_ENV
                    + "\ncapture_cocoapods_generated_build_subject.py\n"
                ),
                MODULE.GENERATED_HELPER_PATH: MODULE.GENERATED_SCHEMA + "\n",
                "Scripts/capture_tuya_private_input_provenance.py": "provenance\n",
                "Scripts/capture_tuya_private_input_build_guard.py": (
                    "capture_cocoapods_generated_build_subject.py\n"
                    "_verify_accepted_generated_build_subject\n"
                    "require_accepted_generated_subject=True\n"
                ),
                "scripts/field/install_one_time_capture.command": (
                    "bootstrap_capture_tuya_sdk.sh\n"
                    "capture_tuya_private_input_build_guard.py\n"
                ),
            }
            for relative, content in contents.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")

            def fake_git(repo, *args):
                self.assertEqual(repo, root)
                if args == ("rev-parse", "HEAD"):
                    return SOURCE
                if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                    return ""
                if args[0] == "rev-parse" and args[1].startswith("HEAD:"):
                    return BLOB
                if args[:3] == ("hash-object", "--no-filters", "--"):
                    return BLOB
                raise AssertionError(args)

            base = SimpleNamespace(canon=MODULE.core._load_base_module().canon, git=fake_git)
            result = MODULE.candidate_generated_authority(
                root,
                SOURCE,
                DIGEST,
                base=base,
                derive_subject=lambda _root, _source: DIGEST,
            )
            self.assertEqual(result["implementation"], MODULE.GENERATED_HELPER_PATH)
            self.assertEqual(result[MODULE.core.GENERATED_KEY], DIGEST)
            self.assertEqual(set(result["gitBlobs"]), set(MODULE.GENERATED_AUTHORITY_PATHS))

            with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                MODULE.candidate_generated_authority(
                    root,
                    SOURCE,
                    DIGEST,
                    base=base,
                    derive_subject=lambda _root, _source: "cd" * 32,
                )

    def test_adapter_keeps_current_parent_sealed_installer_identity(self):
        parent = MODULE.core._load_base_module()
        sealed_installer = parent.installer
        original_environment = parent.installer_environment
        saved_candidate = MODULE.core.candidate_generated_authority
        saved_control = MODULE.core.generated_control_plane
        saved_build = MODULE.core.build

        def review_adapter(*args, **kwargs):
            del args, kwargs
            return {"authority": MODULE.core.REVIEW_AUTHORITY}

        with MODULE.core._parent_extensions(
            parent,
            accepted_generated_digest=DIGEST,
            review_adapter=review_adapter,
        ):
            self.assertIs(parent.installer, sealed_installer)
            self.assertIs(parent.installer.__globals__["installer_environment"], parent.installer_environment)
            self.assertIsNot(parent.installer_environment, original_environment)
            with MODULE._install_adapter():
                self.assertIs(parent.installer, sealed_installer)
                self.assertIs(MODULE.core.candidate_generated_authority, MODULE.candidate_generated_authority)
                self.assertIs(MODULE.core.generated_control_plane, MODULE.generated_control_plane)
                self.assertIs(MODULE.core.build, MODULE.build)
                self.assertIs(parent.installer.__globals__["installer_environment"], parent.installer_environment)

        self.assertIs(parent.installer, sealed_installer)
        self.assertIs(parent.installer_environment, original_environment)
        self.assertIs(MODULE.core.candidate_generated_authority, saved_candidate)
        self.assertIs(MODULE.core.generated_control_plane, saved_control)
        self.assertIs(MODULE.core.build, saved_build)

    def test_build_forces_source_bound_derive_subject_into_core_default_boundary(self):
        observed = {}

        def fake_core_build(*args, **kwargs):
            observed["args"] = args
            observed["kwargs"] = kwargs
            return {
                "generatedBuildSubjectCandidate": {
                    "implementation": MODULE.GENERATED_HELPER_PATH,
                }
            }

        with mock.patch.object(MODULE, "_ORIGINAL_BUILD", side_effect=fake_core_build):
            result = MODULE.build(example="value")
        self.assertIs(observed["kwargs"]["derive_subject"], MODULE._current_generated_subject)
        self.assertEqual(result["generatedBuildSubjectImplementation"], MODULE.GENERATED_HELPER_PATH)


if __name__ == "__main__":
    unittest.main(verbosity=2)
