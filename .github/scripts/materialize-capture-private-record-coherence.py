from pathlib import Path

path = Path("Scripts/capture_tuya_private_input_provenance.py")
source = path.read_text(encoding="utf-8")

marker = "\ndef build_record(\n"
helpers = r'''
def _generation_identity(path: Path, *, expected_kind: str) -> tuple[int, ...]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ProvenanceError("private build input changed during whole-record admission") from error
    if expected_kind == "F":
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise ProvenanceError("private build input changed during whole-record admission")
    elif expected_kind == "D":
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ProvenanceError("private build input changed during whole-record admission")
    else:
        raise ProvenanceError("unsupported private build input generation kind")
    return _stat_identity(metadata)


def _tree_generation_snapshot(root: Path) -> tuple[tuple[str, str, tuple[int, ...], str | None], ...]:
    root_resolved = root.resolve(strict=True)
    snapshot: list[tuple[str, str, tuple[int, ...], str | None]] = [
        (".", "D", _generation_identity(root, expected_kind="D"), None)
    ]
    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        kept_directories: list[str] = []
        for name in sorted(directory_names, key=os.fsencode):
            child = current / name
            relative = child.relative_to(root).as_posix()
            metadata = child.lstat()
            identity = _stat_identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(child, root_resolved)
                snapshot.append((relative, "L", identity, target))
            elif stat.S_ISDIR(metadata.st_mode):
                snapshot.append((relative, "D", identity, None))
                kept_directories.append(name)
            else:
                raise ProvenanceError("private build tree contains an unsupported directory entry")
        directory_names[:] = kept_directories
        for name in sorted(file_names, key=os.fsencode):
            child = current / name
            relative = child.relative_to(root).as_posix()
            metadata = child.lstat()
            identity = _stat_identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(child, root_resolved)
                snapshot.append((relative, "L", identity, target))
            elif stat.S_ISREG(metadata.st_mode):
                snapshot.append((relative, "F", identity, None))
            else:
                raise ProvenanceError("private build tree contains an unsupported file entry")
    return tuple(sorted(snapshot, key=lambda item: os.fsencode(item[0])))


def _record_generation_snapshot(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> tuple[object, ...]:
    # This witness is deliberately metadata/identity based, not digest-only.  A
    # mutate-and-restore race can restore final bytes while ctime/mtime changes;
    # the whole-record fence must still reject that mixed-generation record.
    return (
        ("lockfile", _generation_identity(lockfile, expected_kind="F")),
        ("security_podspec", _generation_identity(security_podspec, expected_kind="F")),
        ("security_build", _tree_generation_snapshot(security_build)),
        ("identity_podspec", _generation_identity(identity_podspec, expected_kind="F")),
        ("identity_sources", _tree_generation_snapshot(identity_sources)),
    )
'''
if source.count(marker) != 1:
    raise SystemExit("build_record insertion marker did not match exactly once")
source = source.replace(marker, "\n" + helpers + marker, 1)

start = source.index("def build_record(\n")
end = source.index("\ndef _record_text", start)
old = source[start:end]
new = r'''def build_record(
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
    record_snapshot_before = _record_generation_snapshot(**paths)
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
    record_snapshot_after = _record_generation_snapshot(**paths)
    if record_snapshot_before != record_snapshot_after:
        raise ProvenanceError(
            "private Tuya build inputs changed while the whole provenance record was constructed"
        )
    return record
'''
source = source[:start] + new + source[end:]
path.write_text(source, encoding="utf-8")

final = path.read_text(encoding="utf-8")
section = final[final.index("def build_record("):final.index("\ndef _record_text", final.index("def build_record("))]
assert "record_snapshot_before" in section
assert "record_snapshot_after" in section
assert "record_snapshot_before != record_snapshot_after" in section
assert "    return {" not in section
assert "_record_generation_snapshot" in final
assert "_tree_generation_snapshot" in final
print("whole-record private-input coherence materialized")
