#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import types
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("private_review_final_go_current", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current private-review Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

REPOSITORY = Path(__file__).resolve().parents[3]
PARENT_TEST_PATH = "scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py"
PARENT_TEST_BLOB = "61c2a1bf4cc35203d763ed1b646a7a92358d84c3"


def _load_parent_tests() -> types.ModuleType:
    entry = MODULE._tree_entries(REPOSITORY, MODULE.PARENT_SOURCE).get(PARENT_TEST_PATH)
    if entry is None or entry[1] != PARENT_TEST_BLOB:
        raise RuntimeError("accepted #2873 private-review test blob is unavailable")
    payload = MODULE._object_git_bytes(REPOSITORY, "cat-file", "blob", PARENT_TEST_BLOB)
    if MODULE._blob_oid(payload, PARENT_TEST_BLOB) != PARENT_TEST_BLOB:
        raise RuntimeError("accepted #2873 private-review test bytes failed Git identity")
    parent = types.ModuleType("nembra_private_review_final_go_parent_tests_2873")
    parent.__file__ = str(Path(__file__).resolve())
    exec(compile(payload, f"git:{MODULE.PARENT_SOURCE}:{PARENT_TEST_PATH}", "exec", dont_inherit=True), parent.__dict__)
    return parent


_PARENT_TESTS = _load_parent_tests()


class ParentPrivateReviewContractTests(_PARENT_TESTS.PrivateReviewFinalGoCurrentTests):
    @unittest.skip("#2890 replaces the parent worktree-loader shape with an exact #2873 blob loader; covered below")
    def test_parent_loader_uses_accepted_git_blob_and_ignores_hidden_worktree_replacement(self):
        pass


class CandidateRawFilesystemAuthorityTests(unittest.TestCase):
    def _initialize_candidate(self, root: Path):
        base = MODULE.generated._load_base_module()
        tracked = {
            base.INSTALLER: (
                "#!/bin/bash\n"
                f'PROCEDURE_ID="{base.PROC}"\n'
                f'BUNDLE_ID="{base.BUNDLE}"\n'
                "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256\n"
                "hmac.compare_digest(actual_digest, expected_digest)\n"
            ),
            base.RUNBOOK: f"PROCEDURE_ID: `{base.PROC}`\n",
            base.IDENTITY: f'static let requiredFieldProcedureIdentifier = "{base.PROC}"\n',
            "NembraApp/App/NembraCaptureEntrypoint.swift": "// accepted app source\n",
        }
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
        for relative, text in tracked.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            if relative == base.INSTALLER:
                path.chmod(0o755)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip().lower()

        info = root / ".git" / "info"
        info.mkdir(parents=True, exist_ok=True)
        (info / "exclude").write_text(
            "LocalSecrets/\nPods/\nNembraCapture.xcworkspace/\nPodfile.lock\n",
            encoding="utf-8",
        )
        for relative in MODULE.FIELD_INPUT_DIRECTORIES:
            (root / relative).mkdir(parents=True, exist_ok=True)
        (root / "Podfile.lock").write_text("PODS:\n", encoding="utf-8")
        return base, source, tracked

    def _write_executable(self, path: Path, body: str) -> None:
        path.write_text("#!/bin/sh\nset -eu\n" + body, encoding="utf-8")
        path.chmod(0o755)
        self.assertTrue(path.stat().st_mode & stat.S_IXUSR)

    def test_child_executes_exact_2873_parent_blob(self):
        self.assertEqual(MODULE._parent.__nembra_accepted_control_source__, MODULE.PARENT_SOURCE)
        self.assertEqual(MODULE._parent.__nembra_accepted_control_blob__, MODULE.PARENT_MODULE_GIT_BLOB)
        self.assertIs(MODULE.review_v5, MODULE._parent.review_v5)
        self.assertIs(MODULE.candidate_private_authority, MODULE._parent.candidate_private_authority)

    def test_inherited_parent_candidate_runs_through_raw_authority(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-raw-parent-") as temporary:
            root = Path(temporary).resolve(strict=True)
            base, source, _ = self._initialize_candidate(root)
            original_git = base.git
            original_git_bytes = base.git_bytes
            with MODULE._candidate_git_custody(base, root, source):
                result = base.candidate(root, source)
                self.assertEqual(result["sourceCommitSHA"], source)
                self.assertEqual(base.git(root, "status", "--porcelain=v1", "--untracked-files=all"), "")
            self.assertIs(base.git, original_git)
            self.assertIs(base.git_bytes, original_git_bytes)

    def test_core_worktree_decoy_cannot_redirect_physical_candidate(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-core-worktree-") as temporary:
            outer = Path(temporary).resolve(strict=True)
            root = outer / "candidate"
            decoy = outer / "decoy"
            root.mkdir()
            decoy.mkdir()
            base, source, tracked = self._initialize_candidate(root)
            for relative in tracked:
                source_path = root / relative
                target = decoy / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if source_path.is_symlink():
                    os.symlink(os.readlink(source_path), target)
                else:
                    shutil.copy2(source_path, target)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "core.worktree", str(decoy)], check=True)
            attacked = root / "NembraApp/App/NembraCaptureEntrypoint.swift"
            attacked.write_text("// attacker-controlled physical source\n", encoding="utf-8")
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
                "fixture must prove ambient Git is describing the decoy worktree",
            )
            with self.assertRaises(MODULE.PrivateReviewGoError):
                with MODULE._candidate_git_custody(base, root, source):
                    self.fail("modified physical candidate was accepted")

    def test_local_fsmonitor_executes_under_ambient_status_but_never_under_candidate_custody(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-fsmonitor-") as temporary:
            root = Path(temporary).resolve(strict=True)
            base, source, _ = self._initialize_candidate(root)
            sentinel = root.parent / "fsmonitor-executed"
            hook = root / ".git" / "nembra-malicious-fsmonitor.sh"
            self._write_executable(hook, f"printf hit > {str(sentinel)!r}\nprintf '\\n'\n")
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "core.fsmonitor", str(hook)], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertTrue(sentinel.exists(), "fixture must prove ambient git status executes local fsmonitor")
            sentinel.unlink()
            with MODULE._candidate_git_custody(base, root, source):
                self.assertEqual(base.git(root, "status", "--porcelain=v1", "--untracked-files=all"), "")
                result = base.candidate(root, source)
                self.assertEqual(result["sourceCommitSHA"], source)
            self.assertFalse(sentinel.exists(), "candidate custody executed repository-local fsmonitor")

    def test_info_attributes_clean_filter_executes_ambiently_but_raw_audit_rejects_without_execution(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-filter-") as temporary:
            root = Path(temporary).resolve(strict=True)
            base, source, _ = self._initialize_candidate(root)
            sentinel = root.parent / "clean-filter-executed"
            helper = root / ".git" / "nembra-malicious-clean-filter.sh"
            self._write_executable(helper, f"printf hit > {str(sentinel)!r}\n/bin/cat\n")
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "filter.evil.clean", str(helper)], check=True)
            attributes = root / ".git" / "info" / "attributes"
            relative = "NembraApp/App/NembraCaptureEntrypoint.swift"
            attributes.write_text(relative + " filter=evil\n", encoding="utf-8")
            (root / relative).write_text("// attacker-controlled physical source\n", encoding="utf-8")
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertTrue(sentinel.exists(), "fixture must prove ambient status executes info/attributes clean filter")
            sentinel.unlink()
            with self.assertRaises(MODULE.PrivateReviewGoError):
                with MODULE._candidate_git_custody(base, root, source):
                    self.fail("filter-hidden physical mutation was accepted")
            self.assertFalse(sentinel.exists(), "raw candidate audit executed clean filter")

    def test_info_exclude_cannot_hide_untracked_physical_input(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-exclude-") as temporary:
            root = Path(temporary).resolve(strict=True)
            base, source, _ = self._initialize_candidate(root)
            hidden = root / "attacker-build-input.swift"
            hidden.write_text("// untracked build-visible input\n", encoding="utf-8")
            with (root / ".git" / "info" / "exclude").open("a", encoding="utf-8") as handle:
                handle.write("attacker-build-input.swift\n")
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
                "fixture must prove mutable info/exclude hides the untracked path from ambient status",
            )
            with self.assertRaises(MODULE.PrivateReviewGoError):
                with MODULE._candidate_git_custody(base, root, source):
                    self.fail("info/exclude-hidden untracked input was accepted")


if __name__ == "__main__":
    unittest.main(verbosity=2)
