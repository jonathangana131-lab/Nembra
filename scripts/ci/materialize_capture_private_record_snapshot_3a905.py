from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "Scripts/capture_tuya_private_input_provenance.py"

INSERT_MARKER = "\ndef build_record(\n"
OLD_BUILD = '''def build_record(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> dict[str, str]:
    return {
        "schema": SCHEMA,
        "podfile_lock_sha256": _read_stable_regular_file_sha256(lockfile)[1],
        "thing_smart_home_kit": THING_SMART_HOME_KIT_VERSION,
        "thing_smart_business_extension_kit": THING_SMART_BUSINESS_EXTENSION_KIT_VERSION,
        "thing_smart_cryption_podspec_sha256": _file_fingerprint(security_podspec),
        "thing_smart_cryption_build_tree_sha256": _tree_fingerprint(security_build),
        "private_identity_podspec_sha256": _file_fingerprint(identity_podspec),
        "private_identity_sources_tree_sha256": _tree_fingerprint(identity_sources),
    }
'''

GENERATION_HELPERS = r'''
def _regular_file_generation_identity(path: Path) -> tuple[int, ...]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build input is unavailable: {path.name}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ProvenanceError(f"required private build input is not a regular file: {path.name}")
    return _stat_identity(metadata)


def _tree_generation_snapshot(root: Path) -> tuple[tuple[object, ...], ...]:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build directory is unavailable: {root.name}") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise ProvenanceError(f"required private build directory is not a real directory: {root.name}")

    root_resolved = root.resolve(strict=True)
    observed_states: list[tuple[Path, tuple[int, ...], str]] = []
    observed_members: dict[Path, tuple[str, ...]] = {}
    snapshot_entries: list[tuple[object, ...]] = []

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        try:
            current_metadata = current.lstat()
        except OSError as error:
            raise ProvenanceError("private build tree changed during record snapshot") from error
        if stat.S_ISLNK(current_metadata.st_mode) or not stat.S_ISDIR(current_metadata.st_mode):
            raise ProvenanceError("private build tree changed during record snapshot")

        current_relative = "." if current == root else current.relative_to(root).as_posix()
        current_identity = _stat_identity(current_metadata)
        observed_states.append((current, current_identity, "D"))
        members = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        observed_members[current] = members
        snapshot_entries.append(("D", current_relative, current_identity, members))

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
                snapshot_entries.append(("L", relative, identity, target))
            elif stat.S_ISDIR(metadata.st_mode):
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
                snapshot_entries.append(("L", relative, identity, target))
            elif stat.S_ISREG(metadata.st_mode):
                observed_states.append((path, identity, "F"))
                snapshot_entries.append(("F", relative, identity))
            else:
                raise ProvenanceError("private build tree contains an unsupported file entry")

    # The generation witness itself must describe one stable traversal rather than a mixed walk.
    for path, identity, kind in observed_states:
        _assert_unchanged_tree_entry(path, identity, kind)
    for directory, members in observed_members.items():
        if _directory_member_names(directory) != members:
            raise ProvenanceError("private build tree changed during record snapshot")

    return tuple(sorted(snapshot_entries, key=lambda item: (item[0], os.fsencode(str(item[1])))))


def _record_input_generation_snapshot(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> tuple[tuple[str, object], ...]:
    return (
        ("lockfile", _regular_file_generation_identity(lockfile)),
        ("security_podspec", _regular_file_generation_identity(security_podspec)),
        ("security_build", _tree_generation_snapshot(security_build)),
        ("identity_podspec", _regular_file_generation_identity(identity_podspec)),
        ("identity_sources", _tree_generation_snapshot(identity_sources)),
    )
'''

NEW_BUILD = '''def build_record(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> dict[str, str]:
    generation_arguments = {
        "lockfile": lockfile,
        "security_podspec": security_podspec,
        "security_build": security_build,
        "identity_podspec": identity_podspec,
        "identity_sources": identity_sources,
    }
    record_snapshot_before = _record_input_generation_snapshot(**generation_arguments)

    record = {
        "schema": SCHEMA,
        "podfile_lock_sha256": _read_stable_regular_file_sha256(lockfile)[1],
        "thing_smart_home_kit": THING_SMART_HOME_KIT_VERSION,
        "thing_smart_business_extension_kit": THING_SMART_BUSINESS_EXTENSION_KIT_VERSION,
        "thing_smart_cryption_podspec_sha256": _file_fingerprint(security_podspec),
        "thing_smart_cryption_build_tree_sha256": _tree_fingerprint(security_build),
        "private_identity_podspec_sha256": _file_fingerprint(identity_podspec),
        "private_identity_sources_tree_sha256": _tree_fingerprint(identity_sources),
    }

    record_snapshot_after = _record_input_generation_snapshot(**generation_arguments)
    if record_snapshot_before != record_snapshot_after:
        raise ProvenanceError(
            "private Tuya build inputs changed while the whole provenance record was assembled"
        )
    return record
'''


def apply() -> None:
    source = HELPER.read_text(encoding="utf-8")
    if "def _record_input_generation_snapshot(" in source:
        raise SystemExit("whole-record generation fence already present")
    if source.count(INSERT_MARKER) != 1:
        raise SystemExit(f"build_record insertion marker count changed: {source.count(INSERT_MARKER)}")
    if source.count(OLD_BUILD) != 1:
        raise SystemExit(f"build_record exact body count changed: {source.count(OLD_BUILD)}")
    source = source.replace(INSERT_MARKER, "\n" + GENERATION_HELPERS + INSERT_MARKER, 1)
    source = source.replace(OLD_BUILD, NEW_BUILD, 1)
    HELPER.write_text(source, encoding="utf-8")


def verify() -> None:
    source = HELPER.read_text(encoding="utf-8")
    required = (
        "def _record_input_generation_snapshot(",
        "def _tree_generation_snapshot(",
        "record_snapshot_before = _record_input_generation_snapshot",
        "record_snapshot_after = _record_input_generation_snapshot",
        "if record_snapshot_before != record_snapshot_after:",
        "private Tuya build inputs changed while the whole provenance record was assembled",
        "_assert_unchanged_tree_entry(path, identity, kind)",
        "_directory_member_names(directory) != members",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"record snapshot contract missing: {token}")
    start = source.index("def build_record(")
    end = source.index("\ndef _record_text", start)
    body = source[start:end]
    if "    return {" in body:
        raise SystemExit("build_record still returns five sequential fingerprints directly")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    arguments = parser.parse_args()
    apply() if arguments.mode == "apply" else verify()
