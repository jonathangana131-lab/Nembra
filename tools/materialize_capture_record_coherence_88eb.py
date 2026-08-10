from pathlib import Path

PATH = Path("Scripts/capture_tuya_private_input_provenance.py")
source = PATH.read_text()

build_anchor = "\n\ndef build_record(\n"
if source.count(build_anchor) != 1:
    raise SystemExit(f"expected one build_record anchor, found {source.count(build_anchor)}")
if "def _record_identity_snapshot(" in source:
    raise SystemExit("whole-record identity snapshot unexpectedly already exists")

helpers = r'''

def _record_file_identity_snapshot(path: Path) -> tuple[int, ...]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build input is unavailable: {path.name}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ProvenanceError(f"required private build input is not a regular file: {path.name}")
    return _stat_identity(metadata)


def _record_tree_identity_snapshot(root: Path) -> tuple[tuple[str, tuple[int, ...]], ...]:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build directory is unavailable: {root.name}") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise ProvenanceError(f"required private build directory is not a real directory: {root.name}")

    identities: list[tuple[str, tuple[int, ...]]] = [(".", _stat_identity(root_metadata))]
    root_resolved = root.resolve(strict=True)
    observed_states: list[tuple[Path, tuple[int, ...], str]] = [
        (root, _stat_identity(root_metadata), "D")
    ]
    observed_directory_members: dict[Path, tuple[str, ...]] = {}

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        observed_directory_members[current] = tuple(
            sorted((*directory_names, *file_names), key=os.fsencode)
        )
        kept_directories: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _stat_identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                _assert_internal_symlink(path, root_resolved)
                observed_states.append((path, identity, "L"))
                identities.append((relative, identity))
            elif stat.S_ISDIR(metadata.st_mode):
                observed_states.append((path, identity, "D"))
                identities.append((relative, identity))
                kept_directories.append(name)
            else:
                raise ProvenanceError("private build tree contains an unsupported directory entry")
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _stat_identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                _assert_internal_symlink(path, root_resolved)
                observed_states.append((path, identity, "L"))
                identities.append((relative, identity))
            elif stat.S_ISREG(metadata.st_mode):
                observed_states.append((path, identity, "F"))
                identities.append((relative, identity))
            else:
                raise ProvenanceError("private build tree contains an unsupported file entry")

    # The record-level witness must itself be a finite tree generation: reject
    # pathname identity or directory membership changes during snapshot capture.
    for path, identity, kind in observed_states:
        _assert_unchanged_tree_entry(path, identity, kind)
    for directory, members in observed_directory_members.items():
        if _directory_member_names(directory) != members:
            raise ProvenanceError("private build tree changed while its record identity was captured")

    return tuple(sorted(identities, key=lambda item: os.fsencode(item[0])))


def _record_identity_snapshot(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> tuple[object, ...]:
    return (
        ("lockfile", _record_file_identity_snapshot(lockfile)),
        ("security_podspec", _record_file_identity_snapshot(security_podspec)),
        ("security_build", _record_tree_identity_snapshot(security_build)),
        ("identity_podspec", _record_file_identity_snapshot(identity_podspec)),
        ("identity_sources", _record_tree_identity_snapshot(identity_sources)),
    )
'''
source = source.replace(build_anchor, helpers + build_anchor)

old_build = '''def build_record(
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
new_build = '''def build_record(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> dict[str, str]:
    snapshot_arguments = {
        "lockfile": lockfile,
        "security_podspec": security_podspec,
        "security_build": security_build,
        "identity_podspec": identity_podspec,
        "identity_sources": identity_sources,
    }
    record_identity_before = _record_identity_snapshot(**snapshot_arguments)
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
    record_identity_after = _record_identity_snapshot(**snapshot_arguments)
    if record_identity_before != record_identity_after:
        raise ProvenanceError(
            "private Tuya build inputs changed while the complete provenance record was constructed"
        )
    return record
'''
if source.count(old_build) != 1:
    raise SystemExit(f"expected one direct-return build_record implementation, found {source.count(old_build)}")
source = source.replace(old_build, new_build)

# Preserve the already-landed per-file pathname identity rendezvous. The
# record-level repair must layer on top rather than regress it.
required_path_rendezvous = "_stat_identity(current_path) != _stat_identity(after)"
if required_path_rendezvous not in source:
    raise SystemExit("current full pathname identity rendezvous is missing")

PATH.write_text(source)
