#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/xcode27_simulator_capture.sh")
source = path.read_text(encoding="utf-8")
marker = 'VISUAL_EVIDENCE_MANIFEST="$ARTIFACTS_DIR/NembraCaptureSimulatorVisualEvidence.json"'
marker_index = source.index(marker)
heredoc_start = source.index("<<'PY'\n", marker_index) + len("<<'PY'\n")
entries_end = source.index("screenshot_entries = [", heredoc_start)

replacement = '''import hashlib
import json
import os
import stat
import sys
from pathlib import Path

(
    manifest_path_text,
    artifacts_root_text,
    build_identifier,
    build_instance_id,
    source_commit_sha,
    external_build_record_sha256,
) = sys.argv[1:]

artifacts_root = Path(artifacts_root_text).resolve()
manifest_path = Path(manifest_path_text).resolve()

if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
    raise SystemExit("platform cannot enforce no-follow visual-evidence descriptor custody")

_DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
_FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW
if hasattr(os, "O_CLOEXEC"):
    _DIRECTORY_FLAGS |= os.O_CLOEXEC
    _FILE_FLAGS |= os.O_CLOEXEC


def stable_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def hash_regular_file(parent_fd: int, name: str) -> tuple[int, str]:
    try:
        descriptor = os.open(name, _FILE_FLAGS, dir_fd=parent_fd)
    except OSError as exc:
        raise SystemExit(f"could not open retained visual evidence without following links: {name}") from exc

    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size <= 0:
            raise SystemExit(f"visual evidence must be one non-empty regular file: {name}")

        digest = hashlib.sha256()
        byte_count = 0
        with os.fdopen(os.dup(descriptor), "rb", closefd=True) as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
                byte_count += len(chunk)

        after = os.fstat(descriptor)
        if stable_identity(before) != stable_identity(after) or byte_count != before.st_size:
            raise SystemExit(f"visual evidence changed while descriptor-bound bytes were hashed: {name}")
        return byte_count, digest.hexdigest()
    finally:
        os.close(descriptor)


def collect_directory(
    parent_fd: int,
    name: str,
    relative_prefix: str,
    artifact_kind: str,
) -> list[dict[str, object]]:
    try:
        directory_fd = os.open(name, _DIRECTORY_FLAGS, dir_fd=parent_fd)
    except FileNotFoundError:
        return []
    except OSError as exc:
        raise SystemExit(f"could not open retained visual-evidence directory safely: {relative_prefix}") from exc

    try:
        before = os.fstat(directory_fd)
        if not stat.S_ISDIR(before.st_mode):
            raise SystemExit(f"visual-evidence ancestry is not a directory: {relative_prefix}")

        records: list[dict[str, object]] = []
        for entry_name in sorted(os.listdir(directory_fd)):
            try:
                entry_metadata = os.stat(
                    entry_name,
                    dir_fd=directory_fd,
                    follow_symlinks=False,
                )
            except OSError as exc:
                raise SystemExit(f"could not inspect retained visual evidence: {relative_prefix}/{entry_name}") from exc

            relative_path = f"{relative_prefix}/{entry_name}"
            if stat.S_ISLNK(entry_metadata.st_mode):
                raise SystemExit(f"visual evidence must not contain symlinks: {relative_path}")
            if stat.S_ISDIR(entry_metadata.st_mode):
                records.extend(
                    collect_directory(
                        directory_fd,
                        entry_name,
                        relative_path,
                        artifact_kind,
                    )
                )
                continue
            if not stat.S_ISREG(entry_metadata.st_mode):
                raise SystemExit(f"visual evidence contains unsupported file type: {relative_path}")

            byte_count, digest = hash_regular_file(directory_fd, entry_name)
            records.append(
                {
                    "artifactKind": artifact_kind,
                    "relativePath": relative_path,
                    "byteCount": byte_count,
                    "sha256": digest,
                }
            )

        after = os.fstat(directory_fd)
        if stable_identity(before) != stable_identity(after):
            raise SystemExit(f"visual-evidence directory changed during enumeration: {relative_prefix}")
        return records
    finally:
        os.close(directory_fd)


try:
    artifacts_fd = os.open(artifacts_root, _DIRECTORY_FLAGS)
except OSError as exc:
    raise SystemExit("could not open exact Simulator artifact root without following links") from exc

entries = []
try:
    root_before = os.fstat(artifacts_fd)
    if not stat.S_ISDIR(root_before.st_mode):
        raise SystemExit("Simulator artifact root is not one directory")

    for artifact_kind, relative_root in (
        ("simulatorScreenshot", "screenshots"),
        ("xctestAttachment", "test-attachments"),
    ):
        entries.extend(
            collect_directory(
                artifacts_fd,
                relative_root,
                relative_root,
                artifact_kind,
            )
        )

    root_after = os.fstat(artifacts_fd)
    if stable_identity(root_before) != stable_identity(root_after):
        raise SystemExit("Simulator artifact root changed during visual-evidence enumeration")
finally:
    os.close(artifacts_fd)

entries.sort(key=lambda entry: (str(entry["relativePath"]), str(entry["artifactKind"])))

'''

source = source[:heredoc_start] + replacement + source[entries_end:]
path.write_text(source, encoding="utf-8")

visual = source[source.index(marker):]
required_tokens = (
    "import os",
    "os.open(",
    "O_NOFOLLOW",
    "O_DIRECTORY",
    "dir_fd=",
    "os.fstat(",
    "os.fdopen(os.dup(",
)
for token in required_tokens:
    if token not in visual:
        raise SystemExit(f"descriptor-bound visual-evidence repair missing {token!r}")
for token in ('path.stat().st_size', 'path.open("rb")'):
    if token in visual:
        raise SystemExit(f"mutable pathname measurement survived repair: {token!r}")
if visual.count("os.fstat(") < 2:
    raise SystemExit("descriptor state is not re-proven after hashing")

print("descriptor-bound visual evidence repair staged: PASS")
