from pathlib import Path

PATH = Path("Scripts/capture_tuya_private_input_provenance.py")
source = PATH.read_text()

old_path_rendezvous = """        if (
            stat.S_ISLNK(current_path.st_mode)
            or not stat.S_ISREG(current_path.st_mode)
            or current_path.st_dev != after.st_dev
            or current_path.st_ino != after.st_ino
        ):
"""
new_path_rendezvous = """        if (
            stat.S_ISLNK(current_path.st_mode)
            or not stat.S_ISREG(current_path.st_mode)
            or _stat_identity(current_path) != _stat_identity(after)
        ):
"""
if source.count(old_path_rendezvous) != 1:
    raise SystemExit(f"expected one pathname rendezvous, found {source.count(old_path_rendezvous)}")
source = source.replace(old_path_rendezvous, new_path_rendezvous)

helper_anchor = "\n\ndef build_record(\n"
if source.count(helper_anchor) != 1:
    raise SystemExit(f"expected one build_record anchor, found {source.count(helper_anchor)}")
helpers = r'''

def _regular_file_generation_witness(path: Path) -> tuple[int, ...]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build input is unavailable: {path.name}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ProvenanceError(f"required private build input is not a real regular file: {path.name}")
    return _stat_identity(metadata)


def _tree_generation_witness(
    root: Path,
) -> tuple[tuple[str, str, tuple[int, ...], str], ...]:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build directory is unavailable: {root.name}") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise ProvenanceError(f"required private build directory is not a real directory: {root.name}")

    root_resolved = root.resolve(strict=True)
    records: list[tuple[str, str, tuple[int, ...], str]] = [
        ("D", ".", _stat_identity(root_metadata), "")
    ]
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
                target = _assert_internal_symlink(path, root_resolved)
                observed_states.append((path, identity, "L"))
                records.append(("L", relative, identity, target))
            elif stat.S_ISDIR(metadata.st_mode):
                observed_states.append((path, identity, "D"))
                records.append(("D", relative, identity, ""))
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
                target = _assert_internal_symlink(path, root_resolved)
                observed_states.append((path, identity, "L"))
                records.append(("L", relative, identity, target))
            elif stat.S_ISREG(metadata.st_mode):
                observed_states.append((path, identity, "F"))
                records.append(("F", relative, identity, ""))
            else:
                raise ProvenanceError("private build tree contains an unsupported file entry")

    for path, identity, kind in observed_states:
        _assert_unchanged_tree_entry(path, identity, kind)
    for directory, members in observed_directory_members.items():
        if _directory_member_names(directory) != members:
            raise ProvenanceError("private build tree changed while its generation was captured")

    return tuple(sorted(records, key=lambda item: os.fsencode(item[1])))


def _record_generation_witness(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> tuple[tuple[str, object], ...]:
    return (
        ("lockfile", _regular_file_generation_witness(lockfile)),
        ("security_podspec", _regular_file_generation_witness(security_podspec)),
        ("security_build", _tree_generation_witness(security_build)),
        ("identity_podspec", _regular_file_generation_witness(identity_podspec)),
        ("identity_sources", _tree_generation_witness(identity_sources)),
    )
'''
source = source.replace(helper_anchor, helpers + helper_anchor)

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
    witness_arguments = {
        "lockfile": lockfile,
        "security_podspec": security_podspec,
        "security_build": security_build,
        "identity_podspec": identity_podspec,
        "identity_sources": identity_sources,
    }
    before_generation = _record_generation_witness(**witness_arguments)
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
    after_generation = _record_generation_witness(**witness_arguments)
    if before_generation != after_generation:
        raise ProvenanceError("private build input set changed while provenance record was built")
    return record
'''
if source.count(old_build) != 1:
    raise SystemExit(f"expected one direct-return build_record implementation, found {source.count(old_build)}")
source = source.replace(old_build, new_build)

PATH.write_text(source)
