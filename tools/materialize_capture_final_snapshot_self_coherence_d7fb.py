from pathlib import Path

PATH = Path("Scripts/capture_tuya_private_input_provenance.py")
source = PATH.read_text()

old_path_rendezvous = '''        if (
            stat.S_ISLNK(current_path.st_mode)
            or not stat.S_ISREG(current_path.st_mode)
            or current_path.st_dev != after.st_dev
            or current_path.st_ino != after.st_ino
        ):
'''
new_path_rendezvous = '''        if (
            stat.S_ISLNK(current_path.st_mode)
            or not stat.S_ISREG(current_path.st_mode)
            or _stat_identity(current_path) != _stat_identity(after)
        ):
'''
if source.count(old_path_rendezvous) != 1:
    raise SystemExit(f"expected one regressed pathname rendezvous, found {source.count(old_path_rendezvous)}")
source = source.replace(old_path_rendezvous, new_path_rendezvous)

old_reader_signature = "def _read_stable_regular_file_sha256(path: Path) -> tuple[os.stat_result, str]:"
new_reader_signature = "def _read_stable_regular_file_sha256(\n    path: Path,\n    *,\n    expected_identity: tuple[int, ...] | None = None,\n) -> tuple[os.stat_result, str]:"
if source.count(old_reader_signature) != 1:
    raise SystemExit(f"expected one stable-reader signature, found {source.count(old_reader_signature)}")
source = source.replace(old_reader_signature, new_reader_signature)

old_regular_guard = '''        if not stat.S_ISREG(before.st_mode):
            raise ProvenanceError(f"required private build input is not a regular file: {path.name}")

        digest = hashlib.sha256()
'''
new_regular_guard = '''        if not stat.S_ISREG(before.st_mode):
            raise ProvenanceError(f"required private build input is not a regular file: {path.name}")
        if expected_identity is not None and _stat_identity(before) != expected_identity:
            raise ProvenanceError(
                f"private build input descriptor does not match enumerated identity: {path.name}"
            )

        digest = hashlib.sha256()
'''
if source.count(old_regular_guard) != 1:
    raise SystemExit(f"expected one stable-reader regular guard, found {source.count(old_regular_guard)}")
source = source.replace(old_regular_guard, new_regular_guard)

old_fingerprint = '''def _file_fingerprint(path: Path) -> str:
    metadata, content_sha256 = _read_stable_regular_file_sha256(path)
'''
new_fingerprint = '''def _file_fingerprint(
    path: Path,
    *,
    expected_identity: tuple[int, ...] | None = None,
) -> str:
    metadata, content_sha256 = _read_stable_regular_file_sha256(
        path,
        expected_identity=expected_identity,
    )
'''
if source.count(old_fingerprint) != 1:
    raise SystemExit(f"expected one file fingerprint definition, found {source.count(old_fingerprint)}")
source = source.replace(old_fingerprint, new_fingerprint)

old_tree_fingerprint_call = "                fingerprint = _file_fingerprint(path)"
new_tree_fingerprint_call = "                fingerprint = _file_fingerprint(path, expected_identity=identity)"
if source.count(old_tree_fingerprint_call) != 1:
    raise SystemExit(f"expected one tree file fingerprint call, found {source.count(old_tree_fingerprint_call)}")
source = source.replace(old_tree_fingerprint_call, new_tree_fingerprint_call)

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

required = [
    "_stat_identity(current_path) != _stat_identity(after)",
    "expected_identity: tuple[int, ...] | None = None",
    "private build input descriptor does not match enumerated identity",
    "_file_fingerprint(path, expected_identity=identity)",
    "record_snapshot_confirmed = _record_identity_snapshot",
]
missing = [item for item in required if item not in source]
if missing:
    raise SystemExit(f"provenance repair lost required existing/new fences: {missing}")
if old_tree == new_tree or old_record == new_record:
    raise SystemExit("materializer produced no effective self-coherence repair")

PATH.write_text(source)
