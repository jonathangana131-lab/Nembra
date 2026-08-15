#!/usr/bin/env python3
"""Compose selected-Xcode, exact private-helper custody, and signed build-origin custody.

This root-only helper is itself executed from exact accepted Git-object bytes by the
field installer. It freezes the selected Xcode toolchain, materializes the accepted
private-input guard/provenance pair from the exact accepted Git tree, grants the fresh
dedicated build identity only a temporary descriptor-pinned read/search lease for the
canonical private Tuya inputs during the exec-bound build window, and then calls the
accepted build-origin helper.

It does not discover/install/launch a device, open Bluetooth, interpret Tuya traffic,
or create physical authority. Whole-source snapshot custody and Apple signing remain
independent gates.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Callable, Sequence


ACCEPTED_GUARD_RELATIVE = Path("Scripts/capture_tuya_private_input_build_guard.py")
ACCEPTED_PROVENANCE_RELATIVE = Path("Scripts/capture_tuya_private_input_provenance.py")
CANONICAL_SDK_RELATIVE = Path("LocalSecrets/TuyaSDK")
CANONICAL_RUNTIME_RELATIVE = Path("LocalSecrets/TuyaRuntime")


class SelectedXcodeBuildOrchestratorError(RuntimeError):
    pass


def _git_blob_oid(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def _decode_verified_git_blob(encoded: str, expected_blob: str, label: str) -> bytes:
    if re.fullmatch(r"[0-9a-f]{40}", expected_blob) is None:
        raise SelectedXcodeBuildOrchestratorError(f"{label} expected Git blob identity is malformed")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except Exception as error:
        raise SelectedXcodeBuildOrchestratorError(f"{label} transport is not strict base64") from error
    if _git_blob_oid(raw) != expected_blob:
        raise SelectedXcodeBuildOrchestratorError(f"{label} bytes do not match the accepted Git blob")
    return raw


def _load_namespace(raw: bytes, *, name: str, filename: str) -> dict[str, object]:
    namespace: dict[str, object] = {"__name__": name, "__file__": filename}
    try:
        exec(compile(raw, filename, "exec", dont_inherit=True), namespace)
    except Exception as error:
        raise SelectedXcodeBuildOrchestratorError(f"{name} could not be loaded") from error
    return namespace


def _require_callable(namespace: dict[str, object], name: str, label: str) -> Callable:
    value = namespace.get(name)
    if not callable(value):
        raise SelectedXcodeBuildOrchestratorError(f"{label} exposes no {name} callable")
    return value


def _require_frozen_tool(tools: dict[object, object], name: str, frozen_developer: Path) -> Path:
    value = tools.get(name)
    if not isinstance(value, Path) or not value.is_absolute():
        raise SelectedXcodeBuildOrchestratorError(f"selected-Xcode freeze exposes no absolute {name} path")
    expected_prefix = str(frozen_developer) + os.sep
    if not str(value).startswith(expected_prefix):
        raise SelectedXcodeBuildOrchestratorError(f"selected {name} escaped the frozen Developer tree")
    if "\t" in str(value) or "\n" in str(value):
        raise SelectedXcodeBuildOrchestratorError(f"selected {name} path contains an invalid separator")
    return value


def _replace_selected_xcode(
    command: Sequence[str],
    *,
    frozen_developer: Path,
    selected_xcodebuild: Path,
) -> list[str]:
    if not command:
        raise SelectedXcodeBuildOrchestratorError("guarded build command is empty")
    if not frozen_developer.is_absolute() or not selected_xcodebuild.is_absolute():
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode authority paths must be absolute")
    if not str(selected_xcodebuild).startswith(str(frozen_developer) + os.sep):
        raise SelectedXcodeBuildOrchestratorError("selected xcodebuild escaped the frozen Developer tree")
    if any(argument.startswith("DEVELOPER_DIR=") for argument in command):
        raise SelectedXcodeBuildOrchestratorError("caller supplied DEVELOPER_DIR authority is forbidden")
    matches = [index for index, argument in enumerate(command) if argument == "/usr/bin/xcodebuild"]
    if len(matches) != 1:
        raise SelectedXcodeBuildOrchestratorError(
            "guarded build must contain exactly one canonical xcodebuild replacement marker"
        )
    index = matches[0]
    return [
        *command[:index],
        "/usr/bin/env",
        f"DEVELOPER_DIR={frozen_developer}",
        str(selected_xcodebuild),
        *command[index + 1 :],
    ]


def _absolute_lexical(path: Path) -> Path:
    if not path.is_absolute():
        raise SelectedXcodeBuildOrchestratorError(f"authority path is not absolute: {path}")
    if "\t" in str(path) or "\n" in str(path):
        raise SelectedXcodeBuildOrchestratorError("authority path contains an invalid separator")
    return Path(os.path.abspath(str(path)))


def _require_real_directory(path: Path, label: str = "private read-lease path") -> os.stat_result:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(f"{label} is unavailable: {path}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(f"{label} is not one real directory: {path}")
    return metadata


def _metadata_signature(metadata: os.stat_result) -> tuple[int, int, int]:
    return metadata.st_dev, metadata.st_ino, stat.S_IFMT(metadata.st_mode)


def _validate_internal_symlink(link: Path, subject: Path) -> None:
    try:
        target = link.resolve(strict=True)
        target.relative_to(subject.resolve(strict=True))
    except (OSError, ValueError) as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease symlink escaped its admitted subject: {link}"
        ) from error


def _subject_entries(subject: Path, *, include_signatures: bool = False) -> tuple:
    try:
        root_metadata = subject.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease subject is unavailable: {subject}"
        ) from error
    if stat.S_ISLNK(root_metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError("private read-lease subject root may not be a symlink")
    if stat.S_ISREG(root_metadata.st_mode):
        entry = (subject, False, _metadata_signature(root_metadata))
        return (entry if include_signatures else entry[:2],)
    if not stat.S_ISDIR(root_metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease subject root has unsupported type: {subject}"
        )

    entries: list[tuple] = [
        (subject, True, _metadata_signature(root_metadata))
        if include_signatures
        else (subject, True)
    ]
    for current_raw, directory_names, file_names in os.walk(subject, topdown=True, followlinks=False):
        current = Path(current_raw)
        kept_directories: list[str] = []
        for name in directory_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                _validate_internal_symlink(candidate, subject)
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease directory entry changed type: {candidate}"
                )
            entry = (candidate, True, _metadata_signature(metadata))
            entries.append(entry if include_signatures else entry[:2])
            kept_directories.append(name)
        directory_names[:] = kept_directories
        for name in file_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                _validate_internal_symlink(candidate, subject)
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease file entry is not regular: {candidate}"
                )
            entry = (candidate, False, _metadata_signature(metadata))
            entries.append(entry if include_signatures else entry[:2])
    return tuple(entries)


def _held_entry_metadata(parent_descriptor: int, name: str) -> os.stat_result:
    if not name or name in (".", "..") or os.sep in name:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease held entry name is unsafe"
        )
    if os.stat not in os.supports_dir_fd or os.stat not in os.supports_follow_symlinks:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease held symlink policy requires descriptor-relative lstat support"
        )
    try:
        return os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease held entry is unavailable: {name}"
        ) from error


def _held_readlink(parent_descriptor: int, name: str) -> str:
    if os.readlink not in os.supports_dir_fd:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease held symlink policy requires descriptor-relative readlink support"
        )
    try:
        target = os.readlink(name, dir_fd=parent_descriptor)
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease held symlink could not be read: {name}"
        ) from error
    if not isinstance(target, str) or not target:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease held symlink has an invalid target: {name}"
        )
    return target


def _held_directory_generation(metadata: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        stat.S_IFMT(metadata.st_mode),
        int(metadata.st_ctime_ns),
        int(metadata.st_mtime_ns),
    )


def _held_symlink_generation(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        stat.S_IFMT(metadata.st_mode),
        int(metadata.st_ctime_ns),
        int(metadata.st_mtime_ns),
        int(metadata.st_size),
    )


def _normalize_held_symlink_target(
    link_parts: tuple[str, ...],
    raw_target: str,
    link_label: Path,
) -> tuple[str, ...]:
    target = Path(raw_target)
    if target.is_absolute():
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease symlink escaped its held subject: {link_label}"
        )
    normalized = list(link_parts[:-1])
    for component in target.parts:
        if component in ("", "."):
            continue
        if component == "..":
            if not normalized:
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease symlink escaped its held subject: {link_label}"
                )
            normalized.pop()
            continue
        if os.sep in component:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease symlink target has an unsafe component: {link_label}"
            )
        normalized.append(component)
    return tuple(normalized)


def _resolve_held_symlink_target(
    target_parts: tuple[str, ...],
    *,
    real_entries: dict[tuple[str, ...], bool],
    symlinks: dict[tuple[str, ...], str],
    subject: Path,
) -> None:
    pending = list(target_parts)
    resolved: list[str] = []
    hops = 0
    while pending:
        component = pending.pop(0)
        resolved.append(component)
        key = tuple(resolved)
        if key in symlinks:
            hops += 1
            if hops > 64:
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease held symlink chain is cyclic or too deep: {subject.joinpath(*key)}"
                )
            replacement = _normalize_held_symlink_target(
                key,
                symlinks[key],
                subject.joinpath(*key),
            )
            pending = [*replacement, *pending]
            resolved = []
            continue
        is_directory = real_entries.get(key)
        if is_directory is None:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held symlink target is unavailable inside its subject: {subject.joinpath(*key)}"
            )
        if pending and not is_directory:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held symlink traversed a non-directory target: {subject.joinpath(*key)}"
            )


def _subject_entries_from_descriptor(subject: Path, subject_descriptor: int) -> tuple:
    """Classify one private subject through its already-held generation."""
    root_metadata = os.fstat(subject_descriptor)
    root_signature = _descriptor_signature(subject_descriptor)
    if stat.S_ISREG(root_metadata.st_mode):
        return ((subject, False, root_signature),)
    if not stat.S_ISDIR(root_metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease held subject has unsupported type: {subject}"
        )
    if os.listdir not in os.supports_fd:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease held symlink policy requires descriptor directory enumeration"
        )

    entries: dict[tuple[str, ...], tuple[Path, bool, tuple[int, int, int]]] = {
        (): (subject, True, root_signature)
    }
    real_entries: dict[tuple[str, ...], bool] = {(): True}
    symlinks: dict[tuple[str, ...], str] = {}

    def scan(directory_descriptor: int, relative: tuple[str, ...]) -> None:
        before_directory = os.fstat(directory_descriptor)
        try:
            names = sorted(os.listdir(directory_descriptor))
        except OSError as error:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held directory could not be enumerated: {subject.joinpath(*relative)}"
            ) from error

        for name in names:
            before = _held_entry_metadata(directory_descriptor, name)
            child_relative = (*relative, name)
            child_path = subject.joinpath(*child_relative)
            if stat.S_ISLNK(before.st_mode):
                target = _held_readlink(directory_descriptor, name)
                after = _held_entry_metadata(directory_descriptor, name)
                if (
                    not stat.S_ISLNK(after.st_mode)
                    or _held_symlink_generation(before) != _held_symlink_generation(after)
                ):
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease held symlink changed while classifying: {child_path}"
                    )
                symlinks[child_relative] = target
                continue

            signature = _metadata_signature(before)
            if stat.S_ISDIR(before.st_mode):
                entries[child_relative] = (child_path, True, signature)
                real_entries[child_relative] = True
                child_descriptor = _open_pinned_child(
                    directory_descriptor,
                    name,
                    True,
                    signature,
                )
                try:
                    scan(child_descriptor, child_relative)
                finally:
                    os.close(child_descriptor)
                continue
            if stat.S_ISREG(before.st_mode):
                entries[child_relative] = (child_path, False, signature)
                real_entries[child_relative] = False
                continue
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held entry has unsupported type: {child_path}"
            )

        after_directory = os.fstat(directory_descriptor)
        if _held_directory_generation(before_directory) != _held_directory_generation(after_directory):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held directory changed during symlink classification: {subject.joinpath(*relative)}"
            )

    scan(subject_descriptor, ())
    for link_parts, raw_target in sorted(symlinks.items()):
        link_label = subject.joinpath(*link_parts)
        target_parts = _normalize_held_symlink_target(
            link_parts,
            raw_target,
            link_label,
        )
        _resolve_held_symlink_target(
            target_parts,
            real_entries=real_entries,
            symlinks=symlinks,
            subject=subject,
        )

    return tuple(
        entry
        for _relative, entry in sorted(entries.items(), key=lambda item: item[0])
    )

def _lease_paths(
    subjects: Sequence[Path],
    repo: Path,
    *,
    include_signatures: bool = False,
    include_descriptors: bool = False,
) -> tuple:
    """Plan exact ACL subjects; descriptor mode is the production object authority.

    The legacy/signature projections are diagnostic compatibility surfaces only.
    Production descriptor mode pins each admitted object immediately and holds every
    descriptor until grant/revoke. A final parent-child coherence pass proves that
    independently pinned descendants belong to the same held ancestry generation.
    """

    if include_signatures and include_descriptors:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease plan cannot request signatures and descriptors together"
        )

    repo = _absolute_lexical(repo)
    repo_metadata = _require_real_directory(repo, "repository root")
    if not subjects:
        raise SelectedXcodeBuildOrchestratorError("private read lease has no subjects")

    ordered: list[tuple] = []
    seen: set[Path] = set()

    def append_descriptor(path: Path, host_only: bool, is_directory: bool) -> None:
        descriptor = _open_pinned_path(path, is_directory)
        ordered.append(
            (path, host_only, _descriptor_signature(descriptor), descriptor)
        )

    def admit(path: Path, host_only: bool, metadata: os.stat_result) -> None:
        if path in seen:
            return
        is_directory = stat.S_ISDIR(metadata.st_mode)
        if not is_directory and not stat.S_ISREG(metadata.st_mode):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease plan targeted unsupported type: {path}"
            )
        if include_descriptors:
            append_descriptor(path, host_only, is_directory)
        else:
            signature = _metadata_signature(metadata)
            ordered.append(
                (path, host_only, signature)
                if include_signatures
                else (path, host_only)
            )
        seen.add(path)

    try:
        # Widen host traversal only until the first ancestor already searchable by all.
        current = repo.parent
        private_hosts: list[tuple[Path, os.stat_result]] = []
        while current != current.parent:
            metadata = _require_real_directory(current, "repository host ancestry")
            if metadata.st_mode & stat.S_IXOTH:
                break
            private_hosts.append((current, metadata))
            current = current.parent
        for path, metadata in reversed(private_hosts):
            admit(path, True, metadata)

        admit(repo, False, repo_metadata)

        for raw_subject in subjects:
            subject = _absolute_lexical(raw_subject)
            try:
                relative = subject.relative_to(repo)
            except ValueError as error:
                raise SelectedXcodeBuildOrchestratorError(
                    "private read-lease subject escaped the repository"
                ) from error
            if not relative.parts:
                raise SelectedXcodeBuildOrchestratorError(
                    "private read-lease subject may not be the repository root"
                )

            cursor = repo
            for component in relative.parts:
                if component in ("", ".", ".."):
                    raise SelectedXcodeBuildOrchestratorError(
                        "private read-lease subject has unsafe ancestry"
                    )
                cursor = cursor / component
                try:
                    metadata = cursor.lstat()
                except OSError as error:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease subject ancestry is unavailable: {cursor}"
                    ) from error
                if stat.S_ISLNK(metadata.st_mode):
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease subject ancestry contains a symlink: {cursor}"
                    )
                if cursor != subject and not stat.S_ISDIR(metadata.st_mode):
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease subject ancestry is not a directory: {cursor}"
                    )
                admit(cursor, False, metadata)

            if include_descriptors:
                subject_record = next(
                    (entry for entry in ordered if len(entry) == 4 and Path(entry[0]) == subject),
                    None,
                )
                if subject_record is None:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease held subject descriptor is unavailable: {subject}"
                    )
                subject_entries = _subject_entries_from_descriptor(
                    subject, int(subject_record[3])
                )
            else:
                subject_entries = _subject_entries(
                    subject, include_signatures=include_signatures
                )
            for entry in subject_entries:
                if include_signatures or include_descriptors:
                    path, is_directory, signature = entry
                else:
                    path, is_directory = entry
                    signature = None
                if path in seen:
                    continue
                if include_descriptors:
                    append_descriptor(path, False, is_directory)
                elif include_signatures:
                    ordered.append((path, False, signature))
                else:
                    ordered.append((path, False))
                seen.add(path)

        if include_descriptors:
            _verify_descriptor_plan(tuple(ordered))
        return tuple(ordered)
    except Exception:
        if include_descriptors:
            for entry in reversed(ordered):
                if len(entry) != 4:
                    continue
                try:
                    os.close(int(entry[3]))
                except OSError:
                    pass
        raise

def _acl_text(principal: str, is_directory: bool, host_only: bool) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.-]+", principal) is None:
        raise SelectedXcodeBuildOrchestratorError("build principal name is malformed")
    if host_only and not is_directory:
        raise SelectedXcodeBuildOrchestratorError("host traversal authority may target directories only")
    if is_directory:
        rights = "search" if host_only else "list,search,readattr,readextattr,readsecurity"
    else:
        rights = "read,readattr,readextattr,readsecurity"
    # Darwin chmod(1) ACL grammar requires the principal tag. Keeping it explicit
    # also makes the before/after classifier unambiguous.
    return f"user:{principal} allow {rights}"


def _path_signature(path: Path) -> tuple[int, int, int]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease path disappeared: {path}"
        ) from error
    if stat.S_ISLNK(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease path became a symlink: {path}"
        )
    return metadata.st_dev, metadata.st_ino, stat.S_IFMT(metadata.st_mode)


def _descriptor_signature(descriptor: int) -> tuple[int, int, int]:
    metadata = os.fstat(descriptor)
    return metadata.st_dev, metadata.st_ino, stat.S_IFMT(metadata.st_mode)


def _open_pinned_path(
    path: Path,
    is_directory: bool,
    expected_signature: tuple[int, int, int] | None = None,
) -> int:
    """Open an absolute lease subject without following any path component."""
    path = _absolute_lexical(path)
    parts = path.parts
    if len(parts) < 2 or parts[0] != os.sep:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease path has no admissible absolute component walk: {path}"
        )
    if os.open not in os.supports_dir_fd:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease component walk requires openat/dir_fd support"
        )
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    odirectory = getattr(os, "O_DIRECTORY", 0)
    if nofollow == 0 or odirectory == 0:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease component walk requires O_NOFOLLOW and O_DIRECTORY"
        )

    common = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | nofollow
    current = -1
    descriptor = -1
    try:
        current = os.open(
            os.sep,
            os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | odirectory,
        )
        for index, component in enumerate(parts[1:]):
            if component in ("", ".", "..") or os.sep in component:
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease path contains an unsafe component: {path}"
                )
            final = index == len(parts) - 2
            flags = common
            if not final or is_directory:
                flags |= odirectory
            try:
                next_descriptor = os.open(component, flags, dir_fd=current)
            except OSError as error:
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease component could not be pinned without following links: {path}"
                ) from error
            os.close(current)
            current = next_descriptor

        descriptor = current
        current = -1
        mode = os.fstat(descriptor).st_mode
        if is_directory != stat.S_ISDIR(mode):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease descriptor type disagrees with plan: {path}"
            )
        if not is_directory and not stat.S_ISREG(mode):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease file descriptor is not regular: {path}"
            )
        actual_signature = _descriptor_signature(descriptor)
        if expected_signature is not None and actual_signature != expected_signature:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease opened object disagrees with planned identity: {path}"
            )
        # Full-path lookup below is diagnostic only after anchored selection.
        if actual_signature != _path_signature(path):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease pathname changed during anchored component walk: {path}"
            )
        result = descriptor
        descriptor = -1
        return result
    except Exception:
        if current >= 0:
            os.close(current)
        if descriptor >= 0:
            os.close(descriptor)
        raise

def _open_pinned_child(
    parent_descriptor: int,
    name: str,
    is_directory: bool,
    expected_signature: tuple[int, int, int],
) -> int:
    """Re-open one held-plan child through its held parent directory."""
    if not name or name in (".", "..") or os.sep in name:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease child name is unsafe"
        )
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    odirectory = getattr(os, "O_DIRECTORY", 0)
    if nofollow == 0 or odirectory == 0 or os.open not in os.supports_dir_fd:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease child verification requires openat no-follow support"
        )
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | nofollow
    if is_directory:
        flags |= odirectory
    try:
        descriptor = os.open(name, flags, dir_fd=parent_descriptor)
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease child is no longer reachable from held parent: {name}"
        ) from error
    try:
        mode = os.fstat(descriptor).st_mode
        if is_directory != stat.S_ISDIR(mode):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held child changed type: {name}"
            )
        if not is_directory and not stat.S_ISREG(mode):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held child is not regular: {name}"
            )
        if _descriptor_signature(descriptor) != expected_signature:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held ancestry disagrees with pinned child: {name}"
            )
        result = descriptor
        descriptor = -1
        return result
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def _verify_descriptor_plan(
    plan: Sequence[tuple[Path, bool, tuple[int, int, int], int]],
) -> None:
    """Require one coherent held ancestry generation before any ACL mutation."""
    by_path = {Path(path): entry for entry in plan for path in (entry[0],)}
    if len(by_path) != len(plan):
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease descriptor plan contains duplicate paths"
        )
    for path_raw, host_only, signature, descriptor in plan:
        path = Path(path_raw)
        is_directory = stat.S_ISDIR(signature[2])
        if not is_directory and not stat.S_ISREG(signature[2]):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held descriptor has unsupported type: {path}"
            )
        if host_only and not is_directory:
            raise SelectedXcodeBuildOrchestratorError(
                "private read-lease host traversal plan targeted a file"
            )
        if _descriptor_signature(descriptor) != signature:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease held descriptor changed identity: {path}"
            )

        parent = by_path.get(path.parent)
        if parent is not None:
            parent_signature = parent[2]
            if not stat.S_ISDIR(parent_signature[2]):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease held parent is not a directory: {path.parent}"
                )
            diagnostic = _open_pinned_child(
                int(parent[3]), path.name, is_directory, signature
            )
        else:
            # Topmost admitted host path is still checked through the real
            # root-anchored component walker. All descendants are checked
            # through already-held parents, preventing mixed generations.
            diagnostic = _open_pinned_path(path, is_directory, signature)
        os.close(diagnostic)

def _descriptor_path(descriptor: int) -> str:
    if descriptor < 0:
        raise SelectedXcodeBuildOrchestratorError("read-lease descriptor is invalid")
    return f"/dev/fd/{descriptor}"


def _acl_listing(descriptor: int) -> str:
    # /dev/fd/<n> is a descriptor indirection; -H makes ls inspect the opened vnode,
    # while pass_fds ensures that exact descriptor survives the child exec.
    completed = subprocess.run(
        ["/bin/ls", "-Hlde", _descriptor_path(descriptor)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        pass_fds=(descriptor,),
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise SelectedXcodeBuildOrchestratorError(
            "could not inspect descriptor-pinned private read-lease ACL"
            + (f": {detail[-800:]}" if detail else "")
        )
    return completed.stdout


def _chmod_acl(descriptor: int, operation: str, acl: str) -> None:
    if operation not in ("+a", "-a"):
        raise SelectedXcodeBuildOrchestratorError("private read-lease ACL operation is invalid")
    completed = subprocess.run(
        ["/bin/chmod", operation, acl, _descriptor_path(descriptor)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        pass_fds=(descriptor,),
    )
    if completed.returncode != 0:
        detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
        raise SelectedXcodeBuildOrchestratorError(
            f"could not {operation} descriptor-pinned private read-lease ACL"
            + (f": {detail[-800:]}" if detail else "")
        )


def _principal_already_present(listing: str, principal: str) -> bool:
    pattern = re.compile(
        r"^\s*\d+:\s+(?:user:)?" + re.escape(principal) + r"(?:\s|:)" ,
        re.MULTILINE,
    )
    return pattern.search(listing) is not None


class _PrivateReadLease:
    """Temporary descriptor-pinned read/search authority for one build account."""

    def __init__(self, subjects: Sequence[Path], repo: Path) -> None:
        self._subjects = tuple(_absolute_lexical(Path(subject)) for subject in subjects)
        if not self._subjects:
            raise SelectedXcodeBuildOrchestratorError("private read lease requires at least one subject")
        self._repository = _absolute_lexical(repo)
        self._opened: list[dict[str, object]] = []
        self._principal = ""

    def grant(self, principal: str) -> None:
        if self._opened or self._principal:
            raise SelectedXcodeBuildOrchestratorError("private read lease is already active")
        if re.fullmatch(r"[A-Za-z0-9_.-]+", principal) is None:
            raise SelectedXcodeBuildOrchestratorError("build principal name is malformed")
        self._principal = principal
        try:
            pinned_plan = _lease_paths(
                self._subjects,
                self._repository,
                include_descriptors=True,
            )
            self._opened = [
                {
                    "descriptor": descriptor,
                    "path": path,
                    "before": "",
                    "acl": "",
                    "added": False,
                    "accepted_signature": accepted_signature,
                    "is_directory": stat.S_ISDIR(accepted_signature[2]),
                }
                for path, _host_only, accepted_signature, descriptor in pinned_plan
            ]

            for record, (path, host_only, accepted_signature, descriptor) in zip(
                self._opened, pinned_plan
            ):
                is_directory = bool(record["is_directory"])
                before = _acl_listing(descriptor)
                if _principal_already_present(before, principal):
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease principal already has ACL authority: {path}"
                    )
                acl = _acl_text(principal, is_directory, host_only)
                record["before"] = before
                record["acl"] = acl
                try:
                    _chmod_acl(descriptor, "+a", acl)
                except Exception:
                    # A command-level failure does not prove the kernel left the ACL
                    # unchanged. Classify while the exact held descriptor remains live.
                    try:
                        after_failed = _acl_listing(descriptor)
                    except Exception:
                        record["added"] = True
                    else:
                        record["added"] = after_failed != before
                    raise
                record["added"] = True
                after = _acl_listing(descriptor)
                if after == before or not _principal_already_present(after, principal):
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease ACL did not materialize exactly: {path}"
                    )
                if _descriptor_signature(descriptor) != accepted_signature:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease held descriptor changed after grant: {path}"
                    )
                diagnostic = _open_pinned_path(
                    path, is_directory, accepted_signature
                )
                os.close(diagnostic)
        except Exception as error:
            try:
                self.revoke()
            except Exception as rollback_error:
                raise SelectedXcodeBuildOrchestratorError(
                    "private read-lease admission failed and exact rollback also failed"
                ) from rollback_error
            raise error

    def revoke(self, *, suppress_errors: bool = False) -> None:
        failures: list[str] = []
        for record in reversed(self._opened):
            descriptor = int(record["descriptor"])
            path = Path(record["path"])
            try:
                if bool(record["added"]):
                    accepted_signature = record.get("accepted_signature")
                    is_directory = record.get("is_directory")
                    path_matches = False
                    if (
                        isinstance(accepted_signature, tuple)
                        and len(accepted_signature) == 3
                        and isinstance(is_directory, bool)
                    ):
                        try:
                            diagnostic = _open_pinned_path(
                                path, is_directory, accepted_signature
                            )
                        except Exception:
                            path_matches = False
                        else:
                            os.close(diagnostic)
                            path_matches = True
                    else:
                        try:
                            path_matches = (
                                _descriptor_signature(descriptor) == _path_signature(path)
                            )
                        except Exception:
                            path_matches = False
                    if not path_matches:
                        failures.append(
                            f"private read-lease pathname no longer identifies opened object: {path}"
                        )
                    _chmod_acl(descriptor, "-a", str(record["acl"]))
                    restored = _acl_listing(descriptor)
                    if restored != str(record["before"]):
                        failures.append(
                            f"private read-lease did not restore exact ACL listing: {path}"
                        )
            except Exception as error:
                failures.append(f"{path}: {error}")
            finally:
                try:
                    os.close(descriptor)
                except OSError as error:
                    failures.append(f"{path}: descriptor close failed: {error}")
        self._opened.clear()
        self._principal = ""
        if failures and not suppress_errors:
            raise SelectedXcodeBuildOrchestratorError(
                "private read-lease revocation failed: " + "; ".join(failures)
            )


def _git_read_environment() -> dict[str, str]:
    return {
        "HOME": "/var/empty",
        "PATH": "/usr/bin:/bin",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
    }


def _read_accepted_git_blob(repo: Path, source_sha: str, relative: Path) -> bytes:
    repo = _absolute_lexical(repo)
    _require_real_directory(repo, "repository root")
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise SelectedXcodeBuildOrchestratorError("accepted source SHA is malformed")
    if relative.is_absolute() or not relative.parts or any(part in ("", ".", "..") for part in relative.parts):
        raise SelectedXcodeBuildOrchestratorError("accepted Git subject path is malformed")
    environment = _git_read_environment()
    safe = f"safe.directory={repo}"
    resolved = subprocess.run(
        ["/usr/bin/git", "-c", safe, "-C", str(repo), "rev-parse", f"{source_sha}:{relative.as_posix()}"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    object_id = (resolved.stdout or "").strip().lower()
    if resolved.returncode != 0 or re.fullmatch(r"[0-9a-f]{40}", object_id) is None:
        raise SelectedXcodeBuildOrchestratorError(
            f"accepted Git object is unavailable for {relative.as_posix()}"
        )
    captured = subprocess.run(
        ["/usr/bin/git", "-c", safe, "-C", str(repo), "cat-file", "blob", object_id],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if captured.returncode != 0 or _git_blob_oid(captured.stdout) != object_id:
        raise SelectedXcodeBuildOrchestratorError(
            f"accepted Git blob bytes could not be proven for {relative.as_posix()}"
        )
    return bytes(captured.stdout)


def _remove_acl(path: Path) -> None:
    completed = subprocess.run(
        ["/bin/chmod", "-N", str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise SelectedXcodeBuildOrchestratorError(
            f"could not strip inherited ACL from accepted guard bundle: {path}"
            + (f": {detail[-600:]}" if detail else "")
        )


def _write_root_readonly(path: Path, raw: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o400)
    try:
        view = memoryview(raw)
        while view:
            written = os.write(descriptor, view)
            if written <= 0:
                raise SelectedXcodeBuildOrchestratorError(
                    "accepted guard bundle write made no progress"
                )
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chown(path, 0, 0)
    os.chmod(path, 0o444)
    _remove_acl(path)
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError("accepted guard bundle file changed type")
    if metadata.st_uid != 0 or metadata.st_gid != 0 or stat.S_IMODE(metadata.st_mode) != 0o444:
        raise SelectedXcodeBuildOrchestratorError(
            "accepted guard bundle file custody is not root read-only"
        )


def _materialize_accepted_guard_bundle(repo: Path, source_sha: str) -> tuple[Path, Path, Path]:
    guard_raw = _read_accepted_git_blob(repo, source_sha, ACCEPTED_GUARD_RELATIVE)
    provenance_raw = _read_accepted_git_blob(repo, source_sha, ACCEPTED_PROVENANCE_RELATIVE)
    private_tmp = Path("/private/tmp")
    _require_real_directory(private_tmp, "private temporary root")
    bundle = Path(tempfile.mkdtemp(prefix="nembra-accepted-private-guard.", dir=private_tmp))
    guard = bundle / ACCEPTED_GUARD_RELATIVE.name
    provenance = bundle / ACCEPTED_PROVENANCE_RELATIVE.name
    try:
        os.chown(bundle, 0, 0)
        os.chmod(bundle, 0o700)
        _remove_acl(bundle)
        _write_root_readonly(guard, guard_raw)
        _write_root_readonly(provenance, provenance_raw)
        os.chmod(bundle, 0o555)
        metadata = bundle.lstat()
        if metadata.st_uid != 0 or metadata.st_gid != 0 or stat.S_IMODE(metadata.st_mode) != 0o555:
            raise SelectedXcodeBuildOrchestratorError(
                "accepted guard bundle directory is not root read-only"
            )
        return bundle, guard, provenance
    except Exception:
        try:
            os.chmod(bundle, 0o700)
        except OSError:
            pass
        shutil.rmtree(bundle, ignore_errors=True)
        raise


def _destroy_guard_bundle(bundle: Path | None) -> None:
    if bundle is None:
        return
    try:
        os.chmod(bundle, 0o700)
    except OSError:
        pass
    shutil.rmtree(bundle, ignore_errors=True)


def _replace_live_guard(command: Sequence[str], *, live_guard: Path, accepted_guard: Path) -> list[str]:
    live_guard = _absolute_lexical(live_guard)
    accepted_guard = _absolute_lexical(accepted_guard)
    matches = [index for index, argument in enumerate(command) if argument == str(live_guard)]
    if len(matches) != 1:
        raise SelectedXcodeBuildOrchestratorError(
            "guarded build must execute exactly one canonical live private-input guard marker"
        )
    if any(argument == str(accepted_guard) for argument in command):
        raise SelectedXcodeBuildOrchestratorError(
            "caller supplied the accepted guard materialization path"
        )
    replaced = list(command)
    replaced[matches[0]] = str(accepted_guard)
    return replaced


def _flag_path(command: Sequence[str], flag: str) -> Path:
    matches = [index for index, value in enumerate(command) if value == flag]
    if len(matches) != 1 or matches[0] + 1 >= len(command):
        raise SelectedXcodeBuildOrchestratorError(
            f"private-input guard requires exactly one {flag}"
        )
    value = command[matches[0] + 1]
    if value == "--" or value.startswith("--"):
        raise SelectedXcodeBuildOrchestratorError(f"private-input guard {flag} has no path")
    return _absolute_lexical(Path(value))


def _private_read_subjects(command: Sequence[str], repo: Path) -> tuple[Path, ...]:
    repo = _absolute_lexical(repo)
    live_guard = repo / ACCEPTED_GUARD_RELATIVE
    guard_indices = [index for index, value in enumerate(command) if value == str(live_guard)]
    if len(guard_indices) != 1:
        raise SelectedXcodeBuildOrchestratorError(
            "canonical private-input guard invocation is missing"
        )
    guard_index = guard_indices[0]
    if guard_index < 2 or list(command[guard_index - 2 : guard_index]) != ["/usr/bin/python3", "-I"]:
        raise SelectedXcodeBuildOrchestratorError(
            "canonical private-input guard interpreter shape changed"
        )

    expected = {
        "--lockfile": repo / "Podfile.lock",
        "--security-podspec": repo / CANONICAL_SDK_RELATIVE / "ThingSmartCryption.podspec",
        "--security-build": repo / CANONICAL_SDK_RELATIVE / "Build",
        "--identity-podspec": repo / CANONICAL_RUNTIME_RELATIVE / "NembraTuyaPrivateConfig.podspec",
        "--identity-sources": repo / CANONICAL_RUNTIME_RELATIVE / "Sources/NembraTuyaPrivateConfig",
    }
    for flag, expected_path in expected.items():
        if _flag_path(command, flag) != _absolute_lexical(expected_path):
            raise SelectedXcodeBuildOrchestratorError(
                f"private-input guard {flag} escaped the canonical accepted field subject"
            )
    separators = [index for index, value in enumerate(command) if value == "--" and index > guard_index]
    if len(separators) != 1:
        raise SelectedXcodeBuildOrchestratorError(
            "private-input guard build separator is ambiguous"
        )
    return (
        expected["--security-podspec"],
        expected["--security-build"],
        expected["--identity-podspec"],
        expected["--identity-sources"],
    )


def _bind_private_read_lease(build_origin: dict[str, object], lease: _PrivateReadLease) -> None:
    original = _require_callable(build_origin, "_run_exec_bound_build", "signed build-origin helper")

    def leased_exec_bound_build(
        command: Sequence[str],
        *,
        name: str,
        uid: int,
        gid: int,
        baseline_groups: Sequence[int],
        environment: dict[str, str],
        cwd: Path,
    ):
        if not isinstance(name, str) or not name:
            raise SelectedXcodeBuildOrchestratorError(
                "build-origin helper exposed no exact build principal"
            )
        lease.grant(name)
        try:
            return original(
                command,
                name=name,
                uid=uid,
                gid=gid,
                baseline_groups=baseline_groups,
                environment=environment,
                cwd=cwd,
            )
        finally:
            lease.revoke()

    # Functions loaded by exec retain this namespace as globals; rebinding this one
    # accepted seam scopes private authority to the exact exec-bound compiler child.
    build_origin["_run_exec_bound_build"] = leased_exec_bound_build


def orchestrate(
    *,
    field_pid: int,
    source_sha: str,
    freeze_launcher_base64: str,
    freeze_launcher_blob: str,
    freeze_helper_base64: str,
    freeze_helper_blob: str,
    build_origin_base64: str,
    build_origin_blob: str,
    install_custody_base64: str,
    install_custody_blob: str,
    command: Sequence[str],
) -> tuple[Path, str]:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise SelectedXcodeBuildOrchestratorError(
            "selected-Xcode build composition requires root on macOS"
        )
    if field_pid <= 1:
        raise SelectedXcodeBuildOrchestratorError("field shell PID is invalid")
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise SelectedXcodeBuildOrchestratorError("accepted source SHA is malformed")

    repo = _absolute_lexical(Path(os.getcwd()))
    _require_real_directory(repo, "repository root")
    live_guard = repo / ACCEPTED_GUARD_RELATIVE
    private_subjects = _private_read_subjects(command, repo)

    launcher_raw = _decode_verified_git_blob(
        freeze_launcher_base64, freeze_launcher_blob, "selected-Xcode freeze launcher"
    )
    _decode_verified_git_blob(
        freeze_helper_base64, freeze_helper_blob, "selected-Xcode freeze helper"
    )
    build_origin_raw = _decode_verified_git_blob(
        build_origin_base64, build_origin_blob, "signed build-origin helper"
    )
    _decode_verified_git_blob(
        install_custody_base64, install_custody_blob, "signed install-custody helper"
    )

    bundle: Path | None = None
    lease: _PrivateReadLease | None = None
    try:
        bundle, accepted_guard, _accepted_provenance = _materialize_accepted_guard_bundle(
            repo, source_sha
        )
        guarded_command = _replace_live_guard(
            command, live_guard=live_guard, accepted_guard=accepted_guard
        )

        launcher = _load_namespace(
            launcher_raw,
            name="nembra_selected_xcode_freeze_launcher",
            filename="<accepted-selected-xcode-freeze-launcher>",
        )
        launcher_run = _require_callable(
            launcher, "run", "selected-Xcode freeze launcher"
        )
        freeze_result = launcher_run(
            field_pid, source_sha, freeze_helper_base64, freeze_helper_blob
        )
        if not isinstance(freeze_result, tuple) or len(freeze_result) != 4:
            raise SelectedXcodeBuildOrchestratorError(
                "selected-Xcode freeze launcher returned malformed authority"
            )
        _namespace, frozen_developer, tools, _janitor_pid = freeze_result
        if (
            not isinstance(frozen_developer, Path)
            or not frozen_developer.is_absolute()
            or not isinstance(tools, dict)
        ):
            raise SelectedXcodeBuildOrchestratorError(
                "selected-Xcode freeze launcher returned invalid paths"
            )
        if "\t" in str(frozen_developer) or "\n" in str(frozen_developer):
            raise SelectedXcodeBuildOrchestratorError(
                "frozen Developer path contains an invalid separator"
            )
        selected_xcodebuild = _require_frozen_tool(
            tools, "xcodebuild", frozen_developer
        )
        _require_frozen_tool(tools, "xctrace", frozen_developer)
        _require_frozen_tool(tools, "devicectl", frozen_developer)
        guarded_command = _replace_selected_xcode(
            guarded_command,
            frozen_developer=frozen_developer,
            selected_xcodebuild=selected_xcodebuild,
        )

        build_origin = _load_namespace(
            build_origin_raw,
            name="nembra_signed_app_build_origin_custody",
            filename="<accepted-build-origin-custody>",
        )
        lease = _PrivateReadLease(private_subjects, repo)
        _bind_private_read_lease(build_origin, lease)
        run_custodied_build = _require_callable(
            build_origin, "run_custodied_build", "signed build-origin helper"
        )
        result = run_custodied_build(
            guarded_command,
            app_relative=Path("Build/Products/Debug-iphoneos/Nembra Capture.app"),
            fingerprint_helper_base64=install_custody_base64,
        )
        if not isinstance(result, tuple) or len(result) != 2:
            raise SelectedXcodeBuildOrchestratorError(
                "signed build-origin helper returned malformed custody result"
            )
        stage_root, fingerprint = result
        if not isinstance(stage_root, Path) or not isinstance(fingerprint, str):
            raise SelectedXcodeBuildOrchestratorError(
                "signed build-origin helper returned invalid custody types"
            )
        if lease._opened or lease._principal:
            raise SelectedXcodeBuildOrchestratorError(
                "private read lease survived the guarded build window"
            )
        return stage_root, fingerprint
    finally:
        if lease is not None and (lease._opened or lease._principal):
            lease.revoke(suppress_errors=True)
        _destroy_guard_bundle(bundle)


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Freeze selected Xcode and run one signed Capture build inside exact compiler-output custody"
    )
    parser.add_argument("--field-pid", required=True, type=int)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--freeze-launcher-base64", required=True)
    parser.add_argument("--freeze-launcher-blob", required=True)
    parser.add_argument("--freeze-helper-base64", required=True)
    parser.add_argument("--freeze-helper-blob", required=True)
    parser.add_argument("--build-origin-base64", required=True)
    parser.add_argument("--build-origin-blob", required=True)
    parser.add_argument("--install-custody-base64", required=True)
    parser.add_argument("--install-custody-blob", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    return args


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parse(sys.argv[1:] if argv is None else argv)
        stage_root, fingerprint = orchestrate(
            field_pid=args.field_pid,
            source_sha=args.source_sha.lower(),
            freeze_launcher_base64=args.freeze_launcher_base64,
            freeze_launcher_blob=args.freeze_launcher_blob,
            freeze_helper_base64=args.freeze_helper_base64,
            freeze_helper_blob=args.freeze_helper_blob,
            build_origin_base64=args.build_origin_base64,
            build_origin_blob=args.build_origin_blob,
            install_custody_base64=args.install_custody_base64,
            install_custody_blob=args.install_custody_blob,
            command=args.command,
        )
        values = (str(stage_root), fingerprint)
        if any("\t" in value or "\n" in value for value in values):
            raise SelectedXcodeBuildOrchestratorError(
                "selected-Xcode build result contains malformed separators"
            )
        sys.stdout.write("\t".join(values) + "\n")
        return 0
    except Exception as error:
        print(
            f"ERROR: selected-Xcode signed-build composition failed: {error}",
            file=sys.stderr,
        )
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
