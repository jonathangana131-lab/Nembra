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


PRIVATE_READ_RELATIVE_SUBJECTS = (
    Path("LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),
    Path("LocalSecrets/TuyaSDK/Build"),
    Path("LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"),
    Path("LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"),
)


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
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease directory is unavailable: {path}"
        ) from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease ancestry is not one real directory: {path}"
        )
    return metadata


def _acl_text(principal: str, is_directory: bool, traversal_only: bool) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.-]+", principal) is None:
        raise SelectedXcodeBuildOrchestratorError("private read-lease principal is malformed")
    if traversal_only and not is_directory:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease traversal authority requires a directory"
        )
    if traversal_only:
        rights = ("search",)
    elif is_directory:
        rights = ("list", "search", "readattr", "readextattr", "readsecurity")
    else:
        rights = ("read", "readattr", "readextattr", "readsecurity")
    return f"user:{principal} allow {','.join(rights)}"


def _verify_symlink_target(candidate: Path, admitted_root: Path) -> None:
    try:
        target = candidate.resolve(strict=True)
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease symlink target is unavailable: {candidate}"
        ) from error
    try:
        target.relative_to(admitted_root)
    except ValueError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease symlink escaped its admitted subject: {candidate}"
        ) from error


def _add_subject_tree(planned: dict[Path, bool], subject: Path) -> None:
    try:
        metadata = subject.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease subject is unavailable: {subject}"
        ) from error
    if stat.S_ISLNK(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease subject root may not be a symlink: {subject}"
        )
    planned[subject] = False
    if stat.S_ISREG(metadata.st_mode):
        return
    if not stat.S_ISDIR(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease subject is not a regular file or directory: {subject}"
        )

    for current_raw, directories, files in os.walk(subject, topdown=True, followlinks=False):
        current = Path(current_raw)
        current_metadata = current.lstat()
        if stat.S_ISLNK(current_metadata.st_mode) or not stat.S_ISDIR(current_metadata.st_mode):
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease tree changed directory identity: {current}"
            )
        planned[current] = False

        kept_directories: list[str] = []
        for name in directories:
            candidate = current / name
            candidate_metadata = candidate.lstat()
            if stat.S_ISLNK(candidate_metadata.st_mode):
                _verify_symlink_target(candidate, subject)
                continue
            if not stat.S_ISDIR(candidate_metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease directory entry changed type: {candidate}"
                )
            planned[candidate] = False
            kept_directories.append(name)
        directories[:] = kept_directories

        for name in files:
            candidate = current / name
            candidate_metadata = candidate.lstat()
            if stat.S_ISLNK(candidate_metadata.st_mode):
                _verify_symlink_target(candidate, subject)
                continue
            if not stat.S_ISREG(candidate_metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease file entry is not regular: {candidate}"
                )
            planned[candidate] = False


def _lease_paths(
    subjects: Sequence[Path], repository: Path
) -> tuple[tuple[Path, bool], ...]:
    repository = Path(repository)
    if not repository.is_absolute():
        raise SelectedXcodeBuildOrchestratorError("private read-lease repository must be absolute")
    if not subjects:
        raise SelectedXcodeBuildOrchestratorError("private read lease requires at least one subject")

    ancestry = [repository, *repository.parents]
    for candidate in reversed(ancestry):
        _require_real_directory(candidate)

    planned: dict[Path, bool] = {}
    for host in repository.parents:
        if host == Path("/"):
            continue
        metadata = _require_real_directory(host)
        if not (metadata.st_mode & stat.S_IXOTH):
            planned[host] = True

    planned[repository] = False

    for raw_subject in subjects:
        subject = Path(raw_subject)
        if not subject.is_absolute():
            raise SelectedXcodeBuildOrchestratorError("private read-lease subject must be absolute")
        try:
            relative = subject.relative_to(repository)
        except ValueError as error:
            raise SelectedXcodeBuildOrchestratorError(
                "private read-lease subject escaped the repository"
            ) from error
        if not relative.parts:
            raise SelectedXcodeBuildOrchestratorError(
                "private read-lease subject may not be the repository root"
            )

        cursor = repository
        for component in relative.parts[:-1]:
            cursor = cursor / component
            _require_real_directory(cursor)
            planned[cursor] = False

        _add_subject_tree(planned, subject)

    return tuple(
        sorted(planned.items(), key=lambda item: (len(item[0].parts), str(item[0])))
    )


def _open_lease_descriptor(path: Path, traversal_only: bool) -> tuple[int, bool]:
    try:
        before = path.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease path disappeared before open: {path}"
        ) from error
    if stat.S_ISLNK(before.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease path became a symlink before open: {path}"
        )
    is_directory = stat.S_ISDIR(before.st_mode)
    if not is_directory and not stat.S_ISREG(before.st_mode):
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease path has unsupported type: {path}"
        )
    if traversal_only and not is_directory:
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease host traversal targeted a non-directory"
        )

    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    if is_directory:
        flags |= getattr(os, "O_DIRECTORY", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease path could not be descriptor-bound: {path}"
        ) from error

    try:
        opened = os.fstat(descriptor)
        before_identity = (before.st_dev, before.st_ino, stat.S_IFMT(before.st_mode))
        opened_identity = (opened.st_dev, opened.st_ino, stat.S_IFMT(opened.st_mode))
        if opened_identity != before_identity:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease path changed identity during descriptor admission: {path}"
            )
        return descriptor, is_directory
    except Exception:
        os.close(descriptor)
        raise


def _descriptor_path(descriptor: int) -> str:
    if descriptor < 0:
        raise SelectedXcodeBuildOrchestratorError("private read-lease descriptor is invalid")
    return f"/dev/fd/{descriptor}"


def _acl_listing(descriptor: int) -> str:
    completed = subprocess.run(
        ["/bin/ls", "-Hlde", _descriptor_path(descriptor)],
        pass_fds=(descriptor,),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise SelectedXcodeBuildOrchestratorError(
            "could not inspect descriptor-bound private read-lease ACL"
            + (f": {detail[-800:]}" if detail else "")
        )
    return completed.stdout


def _chmod_acl(descriptor: int, operation: str, acl: str) -> None:
    if operation not in ("+a", "-a"):
        raise SelectedXcodeBuildOrchestratorError(
            "private read-lease ACL mutation operation is invalid"
        )
    completed = subprocess.run(
        ["/bin/chmod", operation, acl, _descriptor_path(descriptor)],
        pass_fds=(descriptor,),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise SelectedXcodeBuildOrchestratorError(
            f"could not apply descriptor-bound private read-lease ACL {operation}"
            + (f": {detail[-800:]}" if detail else "")
        )


class _PrivateReadLease:
    """A reversible descriptor-held read/search lease for one dedicated build principal."""

    def __init__(self, subjects: Sequence[Path], repository: Path) -> None:
        self._subjects = tuple(Path(subject) for subject in subjects)
        self._repository = Path(repository)
        if not self._subjects:
            raise SelectedXcodeBuildOrchestratorError(
                "private read lease requires at least one subject"
            )
        self._opened: list[tuple[int, str, str]] = []
        self._principal = ""

    def _rollback(self, *, suppress_errors: bool) -> None:
        failures: list[str] = []
        for descriptor, before_acl, acl in reversed(self._opened):
            try:
                _chmod_acl(descriptor, "-a", acl)
                after_acl = _acl_listing(descriptor)
                if after_acl != before_acl:
                    raise SelectedXcodeBuildOrchestratorError(
                        "private read-lease rollback did not restore the exact prior ACL listing"
                    )
            except Exception as error:
                failures.append(str(error))
            finally:
                try:
                    os.close(descriptor)
                except OSError as error:
                    failures.append(f"could not close private read-lease descriptor: {error}")
        self._opened = []
        self._principal = ""
        if failures and not suppress_errors:
            raise SelectedXcodeBuildOrchestratorError(
                "private read lease could not be fully revoked: " + "; ".join(failures)
            )

    def grant(self, principal: str) -> None:
        if self._opened or self._principal:
            raise SelectedXcodeBuildOrchestratorError("private read lease is already granted")
        _acl_text(principal, True, True)

        try:
            for path, traversal_only in _lease_paths(self._subjects, self._repository):
                descriptor, is_directory = _open_lease_descriptor(path, traversal_only)
                before_acl = _acl_listing(descriptor)
                acl = _acl_text(principal, is_directory, traversal_only)
                try:
                    _chmod_acl(descriptor, "+a", acl)
                except Exception:
                    # A command-level failure does not prove the kernel left the ACL
                    # unchanged. Keep descriptor custody until we can classify the
                    # post-call vnode. If mutation is observable (or inspection itself
                    # fails), the outer rollback still owns this exact descriptor.
                    self._opened.append((descriptor, before_acl, acl))
                    try:
                        after_failed_acl = _acl_listing(descriptor)
                    except Exception:
                        raise
                    if after_failed_acl == before_acl:
                        self._opened.pop()
                        os.close(descriptor)
                    raise

                self._opened.append((descriptor, before_acl, acl))
                after_acl = _acl_listing(descriptor)
                if after_acl == before_acl:
                    raise SelectedXcodeBuildOrchestratorError(
                        "private read-lease ACL mutation was not observable on the admitted descriptor"
                    )

            self._principal = principal
        except Exception as error:
            try:
                self._rollback(suppress_errors=False)
            except Exception as rollback_error:
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease grant failed and rollback also failed: {rollback_error}"
                ) from error
            raise

    def revoke(self, *, suppress_errors: bool = False) -> None:
        self._rollback(suppress_errors=suppress_errors)


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

    repository = Path(os.getcwd())
    private_read_lease = _PrivateReadLease(
        tuple(repository / relative for relative in PRIVATE_READ_RELATIVE_SUBJECTS),
        repository,
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
        private_read_lease=private_read_lease,
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