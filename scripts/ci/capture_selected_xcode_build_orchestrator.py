#!/usr/bin/env python3
"""Compose selected-Xcode custody with signed Capture build-origin custody.

This root-only helper is executed from exact accepted Git-object bytes by the field
installer. It keeps the selected-Xcode freeze and the dedicated-UID/APFS build in one
privileged process: the freeze launcher first revokes reusable field-user sudo authority,
then this helper substitutes only the launcher-returned frozen xcodebuild into the guarded
build command and calls the accepted build-origin helper directly.

The accepted freeze must also expose exact xctrace/devicectl subjects inside the same
root/no-write Developer tree. They are validated here even though the current installer ABI
continues to return only the protected stage and fingerprint; later device-tool migration
must re-earn its own exact-head boundary rather than smuggling new parent-shell authority
through this build result.

The helper does not discover/install/launch a device, open Bluetooth, interpret Tuya
traffic, or create physical authority. Accepted-source/private-input and Apple signing
boundaries remain independent gates.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Callable, Sequence


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
    expected_prefix = str(frozen_developer) + os.sep
    if not str(selected_xcodebuild).startswith(expected_prefix):
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


def _require_real_directory(path: Path) -> os.stat_result:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(f"private read-lease path is unavailable: {path}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(f"private read-lease ancestry is not one real directory: {path}")
    return metadata


def _acl_text(user: str, is_directory: bool, traversal_only: bool) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.-]+", user) is None:
        raise SelectedXcodeBuildOrchestratorError("private read-lease user name is malformed")
    if traversal_only and not is_directory:
        raise SelectedXcodeBuildOrchestratorError("private read-lease traversal authority requires a directory")
    if is_directory:
        permissions = ("search",) if traversal_only else (
            "list",
            "search",
            "readattr",
            "readextattr",
            "readsecurity",
        )
    else:
        permissions = ("read", "readattr", "readextattr", "readsecurity")
    return f"user:{user} allow {','.join(permissions)}"


def _lease_paths(subjects: Sequence[Path], repository: Path) -> tuple[tuple[Path, bool], ...]:
    if not repository.is_absolute():
        raise SelectedXcodeBuildOrchestratorError("private read-lease repository must be absolute")
    _require_real_directory(repository)

    ordered: list[tuple[Path, bool]] = []
    seen: set[Path] = set()

    # A private host ancestor is needed only until the first already-world-searchable
    # directory. Never broaden a 0711/0755 host path merely because it is above the repo.
    current = repository.parent
    private_hosts: list[Path] = []
    while current != current.parent:
        metadata = _require_real_directory(current)
        if metadata.st_mode & stat.S_IXOTH:
            break
        private_hosts.append(current)
        current = current.parent
    for path in reversed(private_hosts):
        if path not in seen:
            ordered.append((path, True))
            seen.add(path)

    if repository not in seen:
        ordered.append((repository, False))
        seen.add(repository)

    for raw_subject in subjects:
        subject = Path(raw_subject)
        if not subject.is_absolute():
            raise SelectedXcodeBuildOrchestratorError("private read-lease subject must be absolute")
        try:
            relative = subject.relative_to(repository)
        except ValueError as error:
            raise SelectedXcodeBuildOrchestratorError("private read-lease subject escaped the repository") from error
        if not relative.parts:
            raise SelectedXcodeBuildOrchestratorError("private read-lease subject may not be the repository root")
        cursor = repository
        for component in relative.parts:
            cursor = cursor / component
            metadata = cursor.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease subject ancestry contains a symlink: {cursor}"
                )
            if cursor != subject and not stat.S_ISDIR(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease subject ancestry is not a directory: {cursor}"
                )
            if cursor not in seen:
                ordered.append((cursor, False))
                seen.add(cursor)
    return tuple(ordered)


def _subject_entries(subject: Path) -> tuple[tuple[Path, bool], ...]:
    try:
        root_metadata = subject.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(f"private read-lease subject is unavailable: {subject}") from error
    if stat.S_ISLNK(root_metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError("private read-lease subject root may not be a symlink")
    if not stat.S_ISDIR(root_metadata.st_mode):
        return ((subject, False),)

    entries: list[tuple[Path, bool]] = [(subject, True)]
    for current_root, directories, files in os.walk(subject, topdown=True, followlinks=False):
        current = Path(current_root)
        kept_directories: list[str] = []
        for name in directories:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                target = candidate.resolve(strict=True)
                try:
                    target.relative_to(subject)
                except ValueError as error:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease symlink escaped its admitted subject: {candidate}"
                    ) from error
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease directory entry changed type: {candidate}"
                )
            entries.append((candidate, True))
            kept_directories.append(name)
        directories[:] = kept_directories
        for name in files:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                target = candidate.resolve(strict=True)
                try:
                    target.relative_to(subject)
                except ValueError as error:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease symlink escaped its admitted subject: {candidate}"
                    ) from error
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease file entry is not regular: {candidate}"
                )
            entries.append((candidate, False))
    return tuple(entries)


class _PrivateReadLease:
    """Temporarily admit one dedicated build account to exact private input bytes.

    Host ancestry receives search only. Repository/subject directories receive read/list/search
    metadata authority and regular subject files receive read-only data authority. Existing
    symlinks may be followed only when their resolved target remains inside the admitted
    subject; ACLs are never written to symlinks themselves.
    """

    def __init__(self, subjects: Sequence[Path], repository: Path) -> None:
        self._subjects = tuple(Path(subject) for subject in subjects)
        if not self._subjects:
            raise SelectedXcodeBuildOrchestratorError("private read lease requires at least one subject")
        self._repository = Path(repository)
        self._applied: list[tuple[Path, str, tuple[int, int, int]]] = []
        self._granted_user: str | None = None

    @staticmethod
    def _signature(path: Path) -> tuple[int, int, int]:
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            raise SelectedXcodeBuildOrchestratorError(f"private read-lease path became a symlink: {path}")
        return metadata.st_dev, metadata.st_ino, stat.S_IFMT(metadata.st_mode)

    def grant(self, user: str) -> None:
        if self._granted_user is not None or self._applied:
            raise SelectedXcodeBuildOrchestratorError("private read lease is already granted")

        plan: list[tuple[Path, bool, bool]] = []
        planned_paths: set[Path] = set()
        for path, host_traversal_only in _lease_paths(self._subjects, self._repository):
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(f"private read-lease path became a symlink: {path}")
            is_directory = stat.S_ISDIR(metadata.st_mode)
            if not is_directory and host_traversal_only:
                raise SelectedXcodeBuildOrchestratorError("host traversal lease targeted a non-directory")
            plan.append((path, is_directory, host_traversal_only))
            planned_paths.add(path)

        for subject in self._subjects:
            for path, is_directory in _subject_entries(subject):
                if path in planned_paths:
                    continue
                plan.append((path, is_directory, False))
                planned_paths.add(path)

        try:
            for path, is_directory, traversal_only in plan:
                before = self._signature(path)
                acl = _acl_text(user, is_directory, traversal_only)
                completed = subprocess.run(
                    ["/bin/chmod", "+a", acl, str(path)],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                )
                if completed.returncode != 0:
                    detail = (completed.stderr or "").strip()
                    raise SelectedXcodeBuildOrchestratorError(
                        f"could not grant private read lease on {path}"
                        + (f": {detail[-800:]}" if detail else "")
                    )
                if self._signature(path) != before:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease path changed identity while granting authority: {path}"
                    )
                self._applied.append((path, acl, before))
            self._granted_user = user
        except Exception:
            self.revoke(suppress_errors=True)
            raise

    def revoke(self, *, suppress_errors: bool = False) -> None:
        failures: list[str] = []
        for path, acl, expected in reversed(self._applied):
            try:
                if self._signature(path) != expected:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease path changed identity before revoke: {path}"
                    )
                completed = subprocess.run(
                    ["/bin/chmod", "-a", acl, str(path)],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                )
                if completed.returncode != 0:
                    detail = (completed.stderr or "").strip()
                    raise SelectedXcodeBuildOrchestratorError(
                        f"could not revoke private read lease on {path}"
                        + (f": {detail[-800:]}" if detail else "")
                    )
            except Exception as error:
                failures.append(str(error))
        self._applied.clear()
        self._granted_user = None
        if failures and not suppress_errors:
            raise SelectedXcodeBuildOrchestratorError(
                "private read lease could not be fully revoked: " + "; ".join(failures)
            )


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
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode build composition requires root on macOS")
    if field_pid <= 1:
        raise SelectedXcodeBuildOrchestratorError("field shell PID is invalid")
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise SelectedXcodeBuildOrchestratorError("accepted source SHA is malformed")

    launcher_raw = _decode_verified_git_blob(
        freeze_launcher_base64, freeze_launcher_blob, "selected-Xcode freeze launcher"
    )
    _decode_verified_git_blob(freeze_helper_base64, freeze_helper_blob, "selected-Xcode freeze helper")
    build_origin_raw = _decode_verified_git_blob(
        build_origin_base64, build_origin_blob, "signed build-origin helper"
    )
    _decode_verified_git_blob(install_custody_base64, install_custody_blob, "signed install-custody helper")

    launcher = _load_namespace(
        launcher_raw,
        name="nembra_selected_xcode_freeze_launcher",
        filename="<accepted-selected-xcode-freeze-launcher>",
    )
    launcher_run = _require_callable(launcher, "run", "selected-Xcode freeze launcher")
    freeze_result = launcher_run(field_pid, source_sha, freeze_helper_base64, freeze_helper_blob)
    if not isinstance(freeze_result, tuple) or len(freeze_result) != 4:
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode freeze launcher returned malformed authority")
    _namespace, frozen_developer, tools, _janitor_pid = freeze_result
    if not isinstance(frozen_developer, Path) or not frozen_developer.is_absolute() or not isinstance(tools, dict):
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode freeze launcher returned invalid paths")
    if "\t" in str(frozen_developer) or "\n" in str(frozen_developer):
        raise SelectedXcodeBuildOrchestratorError("frozen Developer path contains an invalid separator")
    selected_xcodebuild = _require_frozen_tool(tools, "xcodebuild", frozen_developer)
    _require_frozen_tool(tools, "xctrace", frozen_developer)
    _require_frozen_tool(tools, "devicectl", frozen_developer)

    guarded_command = _replace_selected_xcode(
        command,
        frozen_developer=frozen_developer,
        selected_xcodebuild=selected_xcodebuild,
    )

    build_origin = _load_namespace(
        build_origin_raw,
        name="nembra_signed_app_build_origin_custody",
        filename="<accepted-build-origin-custody>",
    )
    run_custodied_build = _require_callable(
        build_origin, "run_custodied_build", "signed build-origin helper"
    )
    result = run_custodied_build(
        guarded_command,
        app_relative=Path("Build/Products/Debug-iphoneos/Nembra Capture.app"),
        fingerprint_helper_base64=install_custody_base64,
    )
    if not isinstance(result, tuple) or len(result) != 2:
        raise SelectedXcodeBuildOrchestratorError("signed build-origin helper returned malformed custody result")
    stage_root, fingerprint = result
    if not isinstance(stage_root, Path) or not isinstance(fingerprint, str):
        raise SelectedXcodeBuildOrchestratorError("signed build-origin helper returned invalid custody types")
    return stage_root, fingerprint


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
            raise SelectedXcodeBuildOrchestratorError("selected-Xcode build result contains malformed separators")
        sys.stdout.write("\t".join(values) + "\n")
        return 0
    except Exception as error:
        print(f"ERROR: selected-Xcode signed-build composition failed: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
