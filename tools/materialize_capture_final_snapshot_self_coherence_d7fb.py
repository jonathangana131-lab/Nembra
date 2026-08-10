from pathlib import Path

PATH = Path("Scripts/capture_tuya_private_input_provenance.py")
source = PATH.read_text()

tree_start = source.index("def _tree_identity_snapshot(")
record_start = source.index("def _record_identity_snapshot(", tree_start)
old_tree = source[tree_start:record_start]
new_tree = '''def _tree_identity_snapshot(root: Path) -> tuple[tuple[str, tuple[int, ...]], ...]:
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

    # A record-level tree witness is not allowed to be a mixed traversal. Recheck
    # every collected pathname identity and each directory membership before return.
    for path, identity, kind in observed_states:
        _assert_unchanged_tree_entry(path, identity, kind)
    for directory, members in observed_directory_members.items():
        if _directory_member_names(directory) != members:
            raise ProvenanceError("private build tree changed while record identity was captured")

    return tuple(sorted(identities, key=lambda item: os.fsencode(item[0])))


'''
source = source[:tree_start] + new_tree + source[record_start:]

record_start = source.index("def _record_identity_snapshot(")
build_start = source.index("def build_record(", record_start)
old_record = source[record_start:build_start]
new_record = '''def _record_identity_snapshot(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> tuple[object, ...]:
    lockfile_identity = _regular_file_identity_snapshot(lockfile)
    security_podspec_identity = _regular_file_identity_snapshot(security_podspec)
    security_build_snapshot = _tree_identity_snapshot(security_build)
    identity_podspec_identity = _regular_file_identity_snapshot(identity_podspec)
    identity_sources_snapshot = _tree_identity_snapshot(identity_sources)

    # Collection above spans five independently mutable authorities. Revalidate
    # every collected tree generation first, then the standalone pathnames, before
    # returning a witness that build_record may compare across digest construction.
    if _tree_identity_snapshot(security_build) != security_build_snapshot:
        raise ProvenanceError("private build input set changed while record identity was captured")
    if _tree_identity_snapshot(identity_sources) != identity_sources_snapshot:
        raise ProvenanceError("private build input set changed while record identity was captured")
    if _regular_file_identity_snapshot(lockfile) != lockfile_identity:
        raise ProvenanceError("private build input set changed while record identity was captured")
    if _regular_file_identity_snapshot(security_podspec) != security_podspec_identity:
        raise ProvenanceError("private build input set changed while record identity was captured")
    if _regular_file_identity_snapshot(identity_podspec) != identity_podspec_identity:
        raise ProvenanceError("private build input set changed while record identity was captured")

    return (
        ("lockfile", lockfile_identity),
        ("security_podspec", security_podspec_identity),
        ("security_build", security_build_snapshot),
        ("identity_podspec", identity_podspec_identity),
        ("identity_sources", identity_sources_snapshot),
    )


'''
source = source[:record_start] + new_record + source[build_start:]

if "_stat_identity(current_path) != _stat_identity(after)" not in source:
    raise SystemExit("full pathname identity rendezvous regressed")
if "record_snapshot_confirmed = _record_identity_snapshot" not in source:
    raise SystemExit("whole-record outer confirmation fence regressed")
if old_tree == new_tree or old_record == new_record:
    raise SystemExit("materializer produced no effective self-coherence repair")

PATH.write_text(source)
