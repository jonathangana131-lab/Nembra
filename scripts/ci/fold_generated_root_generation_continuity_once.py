#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/ci/capture_accepted_build_input_snapshot.py"
TEST = ROOT / "scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py"

helper = HELPER.read_text(encoding="utf-8")
canonical_start = '''    root_fd = _open_repository_root(root)\n    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}\n    try:\n        for subject in GENERATED_SUBJECTS:\n            if subject in seen:\n'''
canonical_start_new = '''    root_fd = _open_repository_root(root)\n    root_admitted = os.fstat(root_fd)\n    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}\n    try:\n        for subject in GENERATED_SUBJECTS:\n            _assert_directory_generation(root_fd, root_admitted, Path("."))\n            if subject in seen:\n'''
if helper.count(canonical_start) != 1:
    raise SystemExit("canonical root-start anchor did not match exactly once")
helper = helper.replace(canonical_start, canonical_start_new, 1)

canonical_end = '''            finally:\n                os.close(descriptor)\n    finally:\n        _close_directory_cache(directory_cache)\n        os.close(root_fd)\n    payload = {\n'''
canonical_end_new = '''            finally:\n                os.close(descriptor)\n            _assert_directory_generation(root_fd, root_admitted, Path("."))\n    finally:\n        _close_directory_cache(directory_cache)\n        os.close(root_fd)\n    payload = {\n'''
if helper.count(canonical_end) != 1:
    raise SystemExit("canonical root-end anchor did not match exactly once")
helper = helper.replace(canonical_end, canonical_end_new, 1)

copy_start = '''    root_fd = _open_repository_root(source_root)\n    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}\n    try:\n        for subject in GENERATED_SUBJECTS:\n            descriptor, metadata, kind = _open_subject(root_fd, subject, directory_cache)\n'''
copy_start_new = '''    root_fd = _open_repository_root(source_root)\n    root_admitted = os.fstat(root_fd)\n    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}\n    try:\n        for subject in GENERATED_SUBJECTS:\n            _assert_directory_generation(root_fd, root_admitted, Path("."))\n            descriptor, metadata, kind = _open_subject(root_fd, subject, directory_cache)\n'''
if helper.count(copy_start) != 1:
    raise SystemExit("copy root-start anchor did not match exactly once")
helper = helper.replace(copy_start, copy_start_new, 1)

copy_end = '''            finally:\n                os.close(descriptor)\n    finally:\n        _close_directory_cache(directory_cache)\n        os.close(root_fd)\n\n\ndef stage_accepted_build_inputs(\n'''
copy_end_new = '''            finally:\n                os.close(descriptor)\n            _assert_directory_generation(root_fd, root_admitted, Path("."))\n    finally:\n        _close_directory_cache(directory_cache)\n        os.close(root_fd)\n\n\ndef stage_accepted_build_inputs(\n'''
if helper.count(copy_end) != 1:
    raise SystemExit("copy root-end anchor did not match exactly once")
helper = helper.replace(copy_end, copy_end_new, 1)
HELPER.write_text(helper, encoding="utf-8")

test = TEST.read_text(encoding="utf-8")
anchor = '''    def test_manifest_rejects_final_child_replacement_after_parent_revalidation(self) -> None:\n'''
if test.count(anchor) != 1:
    raise SystemExit("root regression insertion anchor did not match exactly once")
insert = '''    def test_manifest_rejects_root_sibling_generation_splice(self) -> None:\n        helper = load()\n        with tempfile.TemporaryDirectory(prefix="nembra-root-sibling-manifest-") as raw:\n            root = Path(raw)\n            seed_common(root)\n            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\\n", b"RUNTIME-A\\n")\n            generation_a.rename(root / "LocalSecrets")\n            lock_b = root / "Podfile.lock.B"\n            lock_b.write_bytes(b"PODS:\\n  - B\\n")\n            pods_b = root / "Pods.B"\n            pods_b.mkdir()\n            (pods_b / "SyntheticPod.swift").write_text("// pod B\\n", encoding="utf-8")\n            original_open = helper._open_subject\n            swapped = False\n\n            def splice_before_pods(root_fd: int, subject: Path, directory_cache=None):\n                nonlocal swapped\n                if subject == Path("Pods") and not swapped:\n                    (root / "Podfile.lock").rename(root / "Podfile.lock.A.attack")\n                    lock_b.rename(root / "Podfile.lock")\n                    (root / "Pods").rename(root / "Pods.A.attack")\n                    pods_b.rename(root / "Pods")\n                    swapped = True\n                return original_open(root_fd, subject, directory_cache)\n\n            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):\n                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):\n                    helper.canonical_generated_manifest(root, SOURCE_SHA)\n\n            self.assertTrue(swapped, "attack hook never reached later root sibling")\n\n    def test_copy_rejects_root_sibling_generation_splice(self) -> None:\n        helper = load()\n        with tempfile.TemporaryDirectory(prefix="nembra-root-sibling-copy-") as raw:\n            root = Path(raw) / "repo"\n            root.mkdir()\n            seed_common(root)\n            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\\n", b"RUNTIME-A\\n")\n            generation_a.rename(root / "LocalSecrets")\n            destination = Path(raw) / "stage"\n            destination.mkdir()\n            lock_b = root / "Podfile.lock.B"\n            lock_b.write_bytes(b"PODS:\\n  - B\\n")\n            pods_b = root / "Pods.B"\n            pods_b.mkdir()\n            (pods_b / "SyntheticPod.swift").write_text("// pod B\\n", encoding="utf-8")\n            original_open = helper._open_subject\n            swapped = False\n\n            def splice_before_pods(root_fd: int, subject: Path, directory_cache=None):\n                nonlocal swapped\n                if subject == Path("Pods") and not swapped:\n                    (root / "Podfile.lock").rename(root / "Podfile.lock.A.attack")\n                    lock_b.rename(root / "Podfile.lock")\n                    (root / "Pods").rename(root / "Pods.A.attack")\n                    pods_b.rename(root / "Pods")\n                    swapped = True\n                return original_open(root_fd, subject, directory_cache)\n\n            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):\n                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):\n                    helper._copy_generated_subjects(root, destination)\n\n            self.assertTrue(swapped, "attack hook never reached later root sibling")\n            copied_pod = destination / "Pods/SyntheticPod.swift"\n            if copied_pod.exists():\n                self.assertNotEqual(copied_pod.read_text(encoding="utf-8"), "// pod B\\n")\n\n'''
TEST.write_text(test.replace(anchor, insert + anchor, 1), encoding="utf-8")
