#!/usr/bin/env python3
from pathlib import Path

helper = Path("Scripts/capture_tuya_private_input_provenance.py")
source = helper.read_text(encoding="utf-8")

tree_start = source.index("def _tree_identity_snapshot(")
record_start = source.index("\ndef _record_identity_snapshot(", tree_start)
old_tree = source[tree_start:record_start]
if "observed_states" in old_tree or "_directory_member_names" in old_tree:
    raise SystemExit("tree identity snapshot seam already changed")

new_tree = '''def _tree_identity_snapshot(root: Path) -> tuple[tuple[str, str, tuple[int, ...], str], ...]:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build directory is unavailable: {root.name}") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise ProvenanceError(f"required private build directory is not a real directory: {root.name}")

    root_resolved = root.resolve(strict=True)
    entries: list[tuple[str, str, tuple[int, ...], str]] = [
        (".", "D", _stat_identity(root_metadata), "")
    ]
    observed_states: list[tuple[Path, tuple[int, ...], str]] = [
        (root, _stat_identity(root_metadata), "D")
    ]
    observed_members: dict[Path, tuple[str, ...]] = {}

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        observed_members[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept_directories: list[str] = []
        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            try:
                metadata = path.lstat()
            except OSError as error:
                raise ProvenanceError("private build tree changed during record snapshot") from error
            identity = _stat_identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(path, root_resolved)
                observed_states.append((path, identity, "L"))
                entries.append((relative, "L", identity, target))
            elif stat.S_ISDIR(metadata.st_mode):
                observed_states.append((path, identity, "D"))
                entries.append((relative, "D", identity, ""))
                kept_directories.append(name)
            else:
                raise ProvenanceError("private build tree contains an unsupported directory entry")
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            try:
                metadata = path.lstat()
            except OSError as error:
                raise ProvenanceError("private build tree changed during record snapshot") from error
            identity = _stat_identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(path, root_resolved)
                observed_states.append((path, identity, "L"))
                entries.append((relative, "L", identity, target))
            elif stat.S_ISREG(metadata.st_mode):
                observed_states.append((path, identity, "F"))
                entries.append((relative, "F", identity, ""))
            else:
                raise ProvenanceError("private build tree contains an unsupported file entry")

    for path, identity, kind in observed_states:
        _assert_unchanged_tree_entry(path, identity, kind)
    for directory, members in observed_members.items():
        if _directory_member_names(directory) != members:
            raise ProvenanceError("private build tree changed during record snapshot")

    return tuple(sorted(entries, key=lambda entry: os.fsencode(entry[0])))

'''
source = source[:tree_start] + new_tree + source[record_start + 1:]

record_start = source.index("def _record_identity_snapshot(")
build_start = source.index("\ndef build_record(", record_start)
old_record = source[record_start:build_start]
if "standalone_authorities" in old_record:
    raise SystemExit("record identity snapshot seam already changed")

new_record = '''def _record_identity_snapshot(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> tuple[object, ...]:
    lockfile_snapshot = _regular_file_identity_snapshot(lockfile)
    security_podspec_snapshot = _regular_file_identity_snapshot(security_podspec)
    security_build_snapshot = _tree_identity_snapshot(security_build)
    identity_podspec_snapshot = _regular_file_identity_snapshot(identity_podspec)
    identity_sources_snapshot = _tree_identity_snapshot(identity_sources)

    standalone_authorities = (
        (lockfile, lockfile_snapshot),
        (security_podspec, security_podspec_snapshot),
        (identity_podspec, identity_podspec_snapshot),
    )

    # Both tree walks happen after earlier standalone identities were observed.
    # Revalidate those earlier authorities before this snapshot can become a
    # whole-record witness, closing mutate/restore during the tail tree walk.
    for path, expected in standalone_authorities:
        if _regular_file_identity_snapshot(path) != expected:
            raise ProvenanceError("private Tuya inputs changed during record snapshot revalidation")

    if _tree_identity_snapshot(security_build) != security_build_snapshot:
        raise ProvenanceError("private Tuya security tree changed during record snapshot revalidation")
    if _tree_identity_snapshot(identity_sources) != identity_sources_snapshot:
        raise ProvenanceError("private Tuya identity tree changed during record snapshot revalidation")

    # The final tree rewalks are nonzero work, so close the return boundary by
    # rechecking standalone generations one last time after both have completed.
    for path, expected in standalone_authorities:
        if _regular_file_identity_snapshot(path) != expected:
            raise ProvenanceError("private Tuya inputs changed during final record snapshot revalidation")

    return (
        ("lockfile", lockfile_snapshot),
        ("security_podspec", security_podspec_snapshot),
        ("security_build", security_build_snapshot),
        ("identity_podspec", identity_podspec_snapshot),
        ("identity_sources", identity_sources_snapshot),
    )

'''
source = source[:record_start] + new_record + source[build_start + 1:]
helper.write_text(source, encoding="utf-8")

regression = Path("scripts/ci/tests/test_capture_tuya_private_input_record_final_snapshot_coherence.py")
regression.write_text('''#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts" / "capture_tuya_private_input_provenance.py"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", HELPER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load provenance helper")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)


class FinalRecordSnapshotCoherenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.security = self.root / "security"
        self.identity = self.root / "identity"
        self.security.mkdir(); self.identity.mkdir()
        (self.security / "blob.bin").write_bytes(b"AAAA")
        (self.identity / "identity.swift").write_text("identity", encoding="utf-8")
        self.lockfile = self.root / "Podfile.lock"
        self.lockfile.write_text("lock-v1", encoding="utf-8")
        self.security_podspec = self.root / "security.podspec"
        self.security_podspec.write_text("security-podspec", encoding="utf-8")
        self.identity_podspec = self.root / "identity.podspec"
        self.identity_podspec.write_text("identity-podspec", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def arguments(self) -> dict[str, Path]:
        return {
            "lockfile": self.lockfile,
            "security_podspec": self.security_podspec,
            "security_build": self.security,
            "identity_podspec": self.identity_podspec,
            "identity_sources": self.identity,
        }

    def test_final_record_snapshot_revalidates_lockfile_after_tail_tree_walk(self) -> None:
        original_tree_snapshot = provenance._tree_identity_snapshot
        tree_calls = 0
        mutated = False

        def tree_snapshot_with_tail_mutation(path: Path):
            nonlocal tree_calls, mutated
            tree_calls += 1
            result = original_tree_snapshot(path)
            if tree_calls == 10:
                self.assertEqual(path, self.identity)
                self.lockfile.write_text("transient", encoding="utf-8")
                self.lockfile.write_text("lock-v1", encoding="utf-8")
                mutated = True
            return result

        with mock.patch.object(provenance, "_tree_identity_snapshot", side_effect=tree_snapshot_with_tail_mutation):
            with self.assertRaises(provenance.ProvenanceError):
                provenance.build_record(**self.arguments())

        self.assertTrue(mutated)
        self.assertEqual(tree_calls, 10)

    def test_record_snapshot_source_has_global_revalidation_before_return(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        start = source.index("def _record_identity_snapshot(")
        end = source.index("\\ndef build_record(", start)
        snapshot = source[start:end]
        self.assertIn("standalone_authorities", snapshot)
        self.assertGreaterEqual(snapshot.count("_regular_file_identity_snapshot(path) != expected"), 2)
        self.assertIn("_tree_identity_snapshot(security_build) != security_build_snapshot", snapshot)
        self.assertIn("_tree_identity_snapshot(identity_sources) != identity_sources_snapshot", snapshot)

    def test_tree_identity_snapshot_revalidates_pathnames_and_membership(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        start = source.index("def _tree_identity_snapshot(")
        end = source.index("\\ndef _record_identity_snapshot(", start)
        tree = source[start:end]
        self.assertIn("observed_states", tree)
        self.assertIn("observed_members", tree)
        self.assertIn("_assert_unchanged_tree_entry", tree)
        self.assertIn("_directory_member_names", tree)


if __name__ == "__main__":
    unittest.main()
''', encoding="utf-8")
