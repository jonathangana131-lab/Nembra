from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Scripts/capture_tuya_private_input_provenance.py"
TEST = ROOT / "scripts/ci/tests/test_capture_tuya_private_input_record_snapshot_coherence.py"

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

NEW_BLOCK = '''def _record_regular_file_generation(path: Path) -> tuple[int, ...]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build input is unavailable: {path.name}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ProvenanceError(f"required private build input is not a regular file: {path.name}")
    return _stat_identity(metadata)


def _record_tree_generation_snapshot(root: Path) -> tuple[tuple[str, str, tuple[int, ...]], ...]:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build directory is unavailable: {root.name}") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise ProvenanceError(f"required private build directory is not a real directory: {root.name}")

    rows: list[tuple[str, str, tuple[int, ...]]] = [(".", "D", _stat_identity(root_metadata))]
    observed_states: list[tuple[Path, tuple[int, ...], str]] = [
        (root, _stat_identity(root_metadata), "D")
    ]
    observed_directory_members: dict[Path, tuple[str, ...]] = {}

    def visit(directory: Path) -> None:
        members = _directory_member_names(directory)
        observed_directory_members[directory] = members
        for name in members:
            path = directory / name
            try:
                metadata = path.lstat()
            except OSError as error:
                raise ProvenanceError("private build tree changed while record identity was captured") from error

            if stat.S_ISLNK(metadata.st_mode):
                kind = "L"
            elif stat.S_ISDIR(metadata.st_mode):
                kind = "D"
            elif stat.S_ISREG(metadata.st_mode):
                kind = "F"
            else:
                raise ProvenanceError("private build tree contains an unsupported entry")

            identity = _stat_identity(metadata)
            relative = path.relative_to(root).as_posix()
            rows.append((relative, kind, identity))
            observed_states.append((path, identity, kind))
            if kind == "D":
                visit(path)

    visit(root)

    # Make each generation snapshot internally stable before it is used as the
    # outer record witness. Content reads are still owned by the existing
    # descriptor/tree fingerprint gates; this witness tracks pathname identity,
    # metadata generation, and membership across the whole record interval.
    for path, identity, kind in observed_states:
        _assert_unchanged_tree_entry(path, identity, kind)
    for directory, members in observed_directory_members.items():
        if _directory_member_names(directory) != members:
            raise ProvenanceError("private build tree changed while record identity was captured")

    return tuple(rows)


def _record_input_generation_snapshot(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> tuple[tuple[str, object], ...]:
    return (
        ("lockfile", _record_regular_file_generation(lockfile)),
        ("security_podspec", _record_regular_file_generation(security_podspec)),
        ("security_build", _record_tree_generation_snapshot(security_build)),
        ("identity_podspec", _record_regular_file_generation(identity_podspec)),
        ("identity_sources", _record_tree_generation_snapshot(identity_sources)),
    )


def _assert_record_snapshot_unchanged(
    expected: tuple[tuple[str, object], ...],
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> None:
    current = _record_input_generation_snapshot(
        lockfile=lockfile,
        security_podspec=security_podspec,
        security_build=security_build,
        identity_podspec=identity_podspec,
        identity_sources=identity_sources,
    )
    if current != expected:
        raise ProvenanceError(
            "private Tuya build inputs changed while the provenance record was constructed"
        )


def build_record(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> dict[str, str]:
    paths = {
        "lockfile": lockfile,
        "security_podspec": security_podspec,
        "security_build": security_build,
        "identity_podspec": identity_podspec,
        "identity_sources": identity_sources,
    }
    record_snapshot = _record_input_generation_snapshot(**paths)
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
    _assert_record_snapshot_unchanged(record_snapshot, **paths)
    return record
'''


def apply() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    if "def _record_input_generation_snapshot(" in source:
        raise SystemExit("record-level snapshot already exists; refresh live product")
    count = source.count(OLD_BUILD)
    if count != 1:
        raise SystemExit(f"build_record source changed: expected 1 block, found {count}")
    SOURCE.write_text(source.replace(OLD_BUILD, NEW_BLOCK, 1), encoding="utf-8")


def verify() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    required = (
        "def _record_tree_generation_snapshot(",
        "def _record_input_generation_snapshot(",
        "def _assert_record_snapshot_unchanged(",
        "record_snapshot = _record_input_generation_snapshot(**paths)",
        "_assert_record_snapshot_unchanged(record_snapshot, **paths)",
        "private Tuya build inputs changed while the provenance record was constructed",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"required record-coherence token missing: {token}")
    start = source.index("def build_record(")
    end = source.index("\ndef _record_text", start)
    build = source[start:end]
    if "    return {" in build:
        raise SystemExit("build_record still returns sequential fingerprints without an outer fence")
    if build.index("record_snapshot") > build.index("_read_stable_regular_file_sha256(lockfile)"):
        raise SystemExit("record snapshot begins after component fingerprinting")
    if build.rindex("_assert_record_snapshot_unchanged") < build.index("_tree_fingerprint(identity_sources)"):
        raise SystemExit("record snapshot is not revalidated after the final component")
    if not TEST.exists():
        raise SystemExit("record-coherence regression missing")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
