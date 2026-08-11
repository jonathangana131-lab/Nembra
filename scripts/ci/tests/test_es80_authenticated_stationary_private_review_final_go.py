#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
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
PREDECESSOR_TEST_PATH = "scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py"
PREDECESSOR_TEST_BLOB = "bb7626e2fda947d55a323ef732d48f4c2a1ee619"


def _load_predecessor_tests() -> types.ModuleType:
    entry = MODULE._tree_entries(REPOSITORY, MODULE.PREDECESSOR_SOURCE).get(PREDECESSOR_TEST_PATH)
    if entry is None or entry[1] != PREDECESSOR_TEST_BLOB:
        raise RuntimeError("exact #2890 Final-GO predecessor test blob is unavailable")
    payload = MODULE._object_git_bytes(REPOSITORY, "cat-file", "blob", PREDECESSOR_TEST_BLOB)
    if MODULE._blob_oid(payload, PREDECESSOR_TEST_BLOB) != PREDECESSOR_TEST_BLOB:
        raise RuntimeError("exact #2890 Final-GO predecessor test bytes failed Git identity")
    predecessor = types.ModuleType("nembra_final_go_raw_tree_predecessor_tests_2890")
    predecessor.__file__ = str(Path(__file__).resolve())
    exec(
        compile(payload, f"git:{MODULE.PREDECESSOR_SOURCE}:{PREDECESSOR_TEST_PATH}", "exec", dont_inherit=True),
        predecessor.__dict__,
    )
    return predecessor


_PREDECESSOR_TESTS = _load_predecessor_tests()


class ParentPrivateReviewContractTests(_PREDECESSOR_TESTS.ParentPrivateReviewContractTests):
    pass


class CandidateRawFilesystemAuthorityTests(_PREDECESSOR_TESTS.CandidateRawFilesystemAuthorityTests):
    def _initialize_generated_candidate(self, root: Path, *, current_vnode: bool):
        base = MODULE.generated._load_base_module()
        vnode_path = MODULE.CURRENT_VNODE_WORKFLOW_PATH if current_vnode else MODULE.RETIRED_VNODE_WORKFLOW_PATH
        vnode_name = MODULE.CURRENT_VNODE_WORKFLOW if current_vnode else MODULE.RETIRED_VNODE_WORKFLOW
        paths = tuple(
            vnode_path if item == MODULE.RETIRED_VNODE_WORKFLOW_PATH else item
            for item in MODULE.generated.GENERATED_AUTHORITY_PATHS
        )
        texts = {relative: relative + "\n" for relative in paths}
        texts["Scripts/bootstrap_capture_tuya_sdk.sh"] = (
            MODULE.generated.GENERATED_ENV + "\n"
            "capture_cocoapods_generated_build_subject.py\n"
        )
        texts[MODULE.generated.GENERATED_HELPER_PATH] = MODULE.generated.GENERATED_SCHEMA + "\n"
        texts["Scripts/capture_tuya_private_input_build_guard.py"] = (
            "capture_cocoapods_generated_build_subject.py\n"
            "_verify_accepted_generated_build_subject\n"
            "require_accepted_generated_subject=True\n"
            "_require_real_checkout_ancestry\n"
            "_ensure_fd_budget\n"
            "KQ_NOTE_ATTRIB\n"
        )
        texts["scripts/field/install_one_time_capture.command"] = (
            "bootstrap_capture_tuya_sdk.sh\n"
            "capture_tuya_private_input_build_guard.py\n"
        )
        texts[MODULE.generated.GENERATED_BUILD_WORKFLOW_PATH] = (
            "name: Capture CocoaPods Build Subject Authority\n"
            "Require exact generated CocoaPods build authority\n"
            "test_capture_private_input_ancestor_retarget.py\n"
        )
        texts[vnode_path] = (
            f"name: {vnode_name}\n"
            "Real macOS chmod vnode evidence\n"
            "macos-15\n"
        )

        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
        for relative, text in texts.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "generated authority fixture"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip().lower()
        return base, source

    def test_recovery_executes_exact_2890_predecessor_blob(self):
        self.assertEqual(MODULE._predecessor.__nembra_accepted_control_source__, MODULE.PREDECESSOR_SOURCE)
        self.assertEqual(MODULE._predecessor.__nembra_accepted_control_blob__, MODULE.PREDECESSOR_MODULE_GIT_BLOB)
        self.assertIs(MODULE._predecessor._read_physical_payload, MODULE._read_physical_payload)

    def test_descriptor_bound_read_rejects_leaf_swap_even_when_replacement_bytes_match(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-leaf-swap-") as temporary:
            root = Path(temporary).resolve(strict=True)
            _, source, _ = self._initialize_candidate(root)
            relative = "NembraApp/App/NembraCaptureEntrypoint.swift"
            mode, accepted_oid = MODULE._candidate_relative_oid(root, source, relative)
            accepted = root / relative
            replacement = root.parent / "same-bytes-replacement.swift"
            replacement.write_bytes(accepted.read_bytes())
            replacement.chmod(accepted.stat().st_mode & 0o777)
            self.assertEqual(MODULE._blob_oid(replacement.read_bytes(), accepted_oid), accepted_oid)

            original_open = MODULE.os.open
            swapped = False
            leaf = Path(relative).name

            def racing_open(path, flags, mode_arg=0o777, *, dir_fd=None):
                nonlocal swapped
                if not swapped and path == leaf and dir_fd is not None and not (flags & os.O_DIRECTORY):
                    os.replace(replacement, accepted)
                    swapped = True
                if dir_fd is None:
                    return original_open(path, flags, mode_arg)
                return original_open(path, flags, mode_arg, dir_fd=dir_fd)

            MODULE.os.open = racing_open
            try:
                with self.assertRaisesRegex(RuntimeError, "identity changed before descriptor bind"):
                    MODULE._read_physical_payload(root, relative, mode)
            finally:
                MODULE.os.open = original_open
            self.assertTrue(swapped, "fixture did not exercise the leaf-swap window")

    def test_current_vnode_contract_admits_current_and_rejects_retired_only_candidate(self):
        digest = "ab" * 32
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-vnode-current-") as temporary:
            current_root = Path(temporary).resolve(strict=True)
            current_base, current_source = self._initialize_generated_candidate(current_root, current_vnode=True)
            with MODULE._current_generated_authority_contract():
                result = MODULE._candidate_generated_authority_current(
                    current_root,
                    current_source,
                    digest,
                    base=current_base,
                    derive_subject=lambda *_args: digest,
                )
                self.assertIn(MODULE.CURRENT_VNODE_WORKFLOW, result["requiredCandidateWorkflows"])
                self.assertNotIn(MODULE.RETIRED_VNODE_WORKFLOW, result["requiredCandidateWorkflows"])
                self.assertIn(MODULE.CURRENT_VNODE_WORKFLOW_PATH, result["gitBlobs"])
                self.assertNotIn(MODULE.RETIRED_VNODE_WORKFLOW_PATH, result["gitBlobs"])

        with tempfile.TemporaryDirectory(prefix="nembra-final-go-vnode-retired-") as temporary:
            retired_root = Path(temporary).resolve(strict=True)
            retired_base, retired_source = self._initialize_generated_candidate(retired_root, current_vnode=False)
            with MODULE._current_generated_authority_contract():
                with self.assertRaises(MODULE.generated.GeneratedSubjectGoError):
                    MODULE._candidate_generated_authority_current(
                        retired_root,
                        retired_source,
                        digest,
                        base=retired_base,
                        derive_subject=lambda *_args: digest,
                    )

    def test_current_vnode_contract_restores_exact_parent_globals(self):
        original = (
            MODULE.generated.VNODE_WORKFLOW,
            MODULE.generated.VNODE_WORKFLOW_PATH,
            MODULE.generated.GENERATED_ACCEPTANCE_WORKFLOWS,
            MODULE.generated.GENERATED_AUTHORITY_PATHS,
            MODULE.generated.candidate_generated_authority,
        )
        with MODULE._current_generated_authority_contract():
            self.assertEqual(MODULE.generated.VNODE_WORKFLOW, MODULE.CURRENT_VNODE_WORKFLOW)
            self.assertEqual(MODULE.generated.VNODE_WORKFLOW_PATH, MODULE.CURRENT_VNODE_WORKFLOW_PATH)
            self.assertIs(MODULE.generated.candidate_generated_authority, MODULE._candidate_generated_authority_current)
        self.assertEqual(MODULE.generated.VNODE_WORKFLOW, original[0])
        self.assertEqual(MODULE.generated.VNODE_WORKFLOW_PATH, original[1])
        self.assertEqual(MODULE.generated.GENERATED_ACCEPTANCE_WORKFLOWS, original[2])
        self.assertEqual(MODULE.generated.GENERATED_AUTHORITY_PATHS, original[3])
        self.assertIs(MODULE.generated.candidate_generated_authority, original[4])


if __name__ == "__main__":
    unittest.main(verbosity=2)
