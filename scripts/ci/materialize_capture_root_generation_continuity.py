#!/usr/bin/env python3
"""One-shot authoring transform for generated root-generation continuity."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/ci/capture_accepted_build_input_snapshot.py"
TEST = ROOT / "scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py"


def replace_exact(source: str, old: str, new: str, *, count: int, label: str) -> str:
    actual = source.count(old)
    if actual != count:
        raise SystemExit(f"{label}: expected {count} exact seams, found {actual}")
    return source.replace(old, new)


def patch_helper() -> None:
    source = HELPER.read_text(encoding="utf-8")

    source = replace_exact(
        source,
        """def _open_subject(\n    root_fd: int,\n    subject: Path,\n    directory_cache: dict[Path, tuple[int, os.stat_result]] | None = None,\n) -> tuple[int, os.stat_result, str]:\n""",
        """def _open_subject(\n    root_fd: int,\n    subject: Path,\n    directory_cache: dict[Path, tuple[int, os.stat_result]] | None = None,\n    root_generation: os.stat_result | None = None,\n) -> tuple[int, os.stat_result, str]:\n""",
        count=1,
        label="open-subject signature",
    )
    source = replace_exact(
        source,
        """    current = os.dup(root_fd)\n    selection_ancestors: list[tuple[int, os.stat_result, Path]] = []\n\n    def revalidate_selection_ancestors() -> None:\n""",
        """    current = os.dup(root_fd)\n    selection_ancestors: list[tuple[int, os.stat_result, Path]] = []\n    if root_generation is not None:\n        selection_ancestors.append((root_fd, root_generation, Path(".")))\n\n    def revalidate_selection_ancestors() -> None:\n""",
        count=1,
        label="root selection ancestor",
    )
    source = replace_exact(
        source,
        """    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}\n    try:\n""",
        """    root_generation = os.fstat(root_fd)\n    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}\n    try:\n""",
        count=2,
        label="operation root generation",
    )
    source = replace_exact(
        source,
        "_open_subject(root_fd, subject, directory_cache)",
        "_open_subject(root_fd, subject, directory_cache, root_generation)",
        count=2,
        label="operation subject admission",
    )
    source = replace_exact(
        source,
        """            finally:\n                os.close(descriptor)\n    finally:\n        _close_directory_cache(directory_cache)\n""",
        """            finally:\n                os.close(descriptor)\n        _assert_directory_generation(root_fd, root_generation, Path("."))\n    finally:\n        _close_directory_cache(directory_cache)\n""",
        count=2,
        label="operation final root revalidation",
    )

    HELPER.write_text(source, encoding="utf-8")


def patch_tests() -> None:
    source = TEST.read_text(encoding="utf-8")
    source = replace_exact(
        source,
        "def swap_before_runtime(root_fd: int, subject: Path, directory_cache=None):",
        "def swap_before_runtime(root_fd: int, subject: Path, directory_cache=None, root_generation=None):",
        count=2,
        label="whole-parent test wrapper signature",
    )
    source = replace_exact(
        source,
        "def splice_runtime_inside_parent(root_fd: int, subject: Path, directory_cache=None):",
        "def splice_runtime_inside_parent(root_fd: int, subject: Path, directory_cache=None, root_generation=None):",
        count=2,
        label="sibling test wrapper signature",
    )
    source = replace_exact(
        source,
        "return original_open(root_fd, subject, directory_cache)",
        "return original_open(root_fd, subject, directory_cache, root_generation)",
        count=4,
        label="existing wrapper forwarding",
    )

    marker = """    def test_cache_dup_failure_closes_newly_opened_child_descriptor(self) -> None:\n"""
    tests = r'''    def test_manifest_rejects_root_sibling_generation_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-sibling-manifest-reject-") as raw:
            root = Path(raw)
            seed_common(root)
            generation = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation.rename(root / "LocalSecrets")
            attack = root / "attacker"
            attack.mkdir()
            replacement_lock = attack / "Podfile.lock.B"
            replacement_lock.write_text("PODS:\n  - Replacement\n", encoding="utf-8")
            replacement_pods = attack / "Pods.B"
            replacement_pods.mkdir()
            (replacement_pods / "SyntheticPod.swift").write_text("// pod B\n", encoding="utf-8")
            original_open = helper._open_subject
            swapped = False

            def splice_before_pods(
                root_fd: int,
                subject: Path,
                directory_cache=None,
                root_generation=None,
            ):
                nonlocal swapped
                if subject == Path("Pods") and not swapped:
                    (root / "Podfile.lock").rename(attack / "Podfile.lock.A")
                    replacement_lock.rename(root / "Podfile.lock")
                    (root / "Pods").rename(attack / "Pods.A")
                    replacement_pods.rename(root / "Pods")
                    swapped = True
                return original_open(root_fd, subject, directory_cache, root_generation)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(swapped)

    def test_copy_rejects_root_sibling_generation_splice_before_new_subject_is_consumed(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-sibling-copy-reject-") as raw:
            root = Path(raw)
            seed_common(root)
            generation = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            attack = root / "attacker"
            attack.mkdir()
            replacement_lock = attack / "Podfile.lock.B"
            replacement_lock.write_text("PODS:\n  - Replacement\n", encoding="utf-8")
            replacement_pods = attack / "Pods.B"
            replacement_pods.mkdir()
            (replacement_pods / "SyntheticPod.swift").write_text("// pod B\n", encoding="utf-8")
            original_open = helper._open_subject
            swapped = False

            def splice_before_pods(
                root_fd: int,
                subject: Path,
                directory_cache=None,
                root_generation=None,
            ):
                nonlocal swapped
                if subject == Path("Pods") and not swapped:
                    (root / "Podfile.lock").rename(attack / "Podfile.lock.A")
                    replacement_lock.rename(root / "Podfile.lock")
                    (root / "Pods").rename(attack / "Pods.A")
                    replacement_pods.rename(root / "Pods")
                    swapped = True
                return original_open(root_fd, subject, directory_cache, root_generation)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper._copy_generated_subjects(root, destination)
            self.assertTrue(swapped)
            self.assertEqual(
                (destination / "Podfile.lock").read_text(encoding="utf-8"),
                "PODS:\n  - Synthetic\n",
            )
            self.assertFalse((destination / "Pods/SyntheticPod.swift").exists())


'''
    source = replace_exact(
        source,
        marker,
        tests + marker,
        count=1,
        label="root-sibling permanent regression insertion",
    )
    TEST.write_text(source, encoding="utf-8")


def main() -> int:
    patch_helper()
    patch_tests()
    for path in (HELPER, TEST):
        compile(path.read_bytes(), str(path), "exec", dont_inherit=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
