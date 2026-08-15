#!/usr/bin/env python3
"""Compose selected-Xcode, private-input read custody, and signed build-origin custody.

This root-only helper is itself executed from exact accepted Git-object bytes by the
field installer. It freezes the selected Xcode toolchain, materializes the accepted
private-input guard/provenance pair from the exact accepted Git tree, grants the fresh
dedicated build identity only the minimum read/search ACL needed for the canonical
private Tuya trees during the exec-bound build window, and then calls the accepted
build-origin helper.

The helper does not discover/install/launch a device, open Bluetooth, interpret Tuya
traffic, or create physical authority. Accepted whole-source snapshot custody and Apple
signing/provisioning remain independent gates.
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


def _absolute_lexical(path: Path) -> Path:
    if not path.is_absolute():
        raise SelectedXcodeBuildOrchestratorError(f"authority path is not absolute: {path}")
    if "\t" in str(path) or "\n" in str(path):
        raise SelectedXcodeBuildOrchestratorError("authority path contains an invalid separator")
    return Path(os.path.abspath(str(path)))


def _require_real_directory(path: Path, label: str) -> os.stat_result:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(f"{label} is unavailable: {path}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(f"{label} is not one real directory: {path}")
    return metadata


def _require_real_subject(path: Path) -> os.stat_result:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise SelectedXcodeBuildOrchestratorError(f"private read-lease subject is unavailable: {path}") from error
    if stat.S_ISLNK(metadata.st_mode):
        raise SelectedXcodeBuildOrchestratorError(f"private read-lease subject is a symlink: {path}")
    if not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
        raise SelectedXcodeBuildOrchestratorError(f"private read-lease subject changed type: {path}")
    return metadata


def _lexical_chain(root: Path, leaf: Path) -> tuple[Path, ...]:
    try:
        relative = leaf.relative_to(root)
    except ValueError as error:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease subject escaped repository root: {leaf}"
        ) from error
    chain = [root]
    current = root
    for part in relative.parts:
        if part in ("", ".", ".."):
            raise SelectedXcodeBuildOrchestratorError("private read-lease subject has unsafe ancestry")
        current = current / part
        chain.append(current)
    return tuple(chain)


def _tree_real_subjects(root: Path) -> tuple[Path, ...]:
    metadata = _require_real_subject(root)
    if stat.S_ISREG(metadata.st_mode):
        return (root,)
    paths: list[Path] = [root]
    for current_raw, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_raw)
        _require_real_directory(current, "private read-lease tree directory")
        for name in list(directory_names):
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                directory_names.remove(name)
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease tree entry changed type: {candidate}"
                )
            paths.append(candidate)
        for name in file_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease tree file changed type: {candidate}"
                )
            paths.append(candidate)
    return tuple(paths)


def _lease_paths(subjects: Sequence[Path], repo: Path) -> tuple[tuple[Path, bool], ...]:
    """Return exact ACL subjects; True means host-ancestor traversal-only authority."""

    repo = _absolute_lexical(repo)
    _require_real_directory(repo, "repository root")
    if not subjects:
        raise SelectedXcodeBuildOrchestratorError("private read lease has no subjects")

    ordered: dict[Path, bool] = {}

    # Validate every lexical host ancestor. A private host directory receives only
    # `search`; already world-searchable ancestors receive no new authority.
    host_chain: list[Path] = []
    current = repo.parent
    while current != current.parent:
        host_chain.append(current)
        current = current.parent
    host_chain.append(current)
    for path in reversed(host_chain):
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise SelectedXcodeBuildOrchestratorError(
                f"repository host ancestry is not one real directory chain: {path}"
            )
        if path == repo:
            continue
        if not (metadata.st_mode & stat.S_IXOTH):
            ordered[path] = True

    ordered[repo] = False
    for raw_subject in subjects:
        subject = _absolute_lexical(raw_subject)
        chain = _lexical_chain(repo, subject)
        for ancestor in chain:
            metadata = ancestor.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease ancestry contains a symlink: {ancestor}"
                )
            if ancestor != subject and not stat.S_ISDIR(metadata.st_mode):
                raise SelectedXcodeBuildOrchestratorError(
                    f"private read-lease ancestry is not a directory: {ancestor}"
                )
            ordered[ancestor] = False
        for tree_path in _tree_real_subjects(subject):
            ordered[tree_path] = False

    return tuple(ordered.items())


def _acl_text(principal: str, is_directory: bool, host_only: bool) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.-]+", principal) is None:
        raise SelectedXcodeBuildOrchestratorError("build principal name is malformed")
    if host_only:
        if not is_directory:
            raise SelectedXcodeBuildOrchestratorError("host traversal authority may target directories only")
        rights = "search"
    elif is_directory:
        rights = "list,search,readattr,readextattr,readsecurity"
    else:
        rights = "read,readattr,readextattr,readsecurity"
    return f"{principal} allow {rights}"


def _open_lease_subject(path: Path) -> tuple[int, bool]:
    before = path.lstat()
    if stat.S_ISLNK(before.st_mode):
        raise SelectedXcodeBuildOrchestratorError(f"read-lease subject became a symlink: {path}")
    is_directory = stat.S_ISDIR(before.st_mode)
    if not (is_directory or stat.S_ISREG(before.st_mode)):
        raise SelectedXcodeBuildOrchestratorError(f"read-lease subject changed type: {path}")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    after = os.fstat(descriptor)
    identity_before = (before.st_dev, before.st_ino, stat.S_IFMT(before.st_mode))
    identity_after = (after.st_dev, after.st_ino, stat.S_IFMT(after.st_mode))
    if identity_before != identity_after:
        os.close(descriptor)
        raise SelectedXcodeBuildOrchestratorError(f"read-lease subject changed during admission: {path}")
    return descriptor, is_directory


def _descriptor_path(descriptor: int) -> str:
    if descriptor < 0:
        raise SelectedXcodeBuildOrchestratorError("read-lease descriptor is invalid")
    return f"/dev/fd/{descriptor}"


def _acl_listing(descriptor: int) -> str:
    completed = subprocess.run(
        ["/bin/ls", "-lde", _descriptor_path(descriptor)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise SelectedXcodeBuildOrchestratorError(
            "could not inspect private read-lease ACL"
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
    )
    if completed.returncode != 0:
        detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
        raise SelectedXcodeBuildOrchestratorError(
            f"could not {operation} private read-lease ACL"
            + (f": {detail[-800:]}" if detail else "")
        )


class _PrivateReadLease:
    """Reversible descriptor-bound ACL lease for one ephemeral dedicated build user."""

    def __init__(self, subjects: Sequence[Path], repo: Path) -> None:
        self._paths = _lease_paths(subjects, repo)
        self._opened: list[dict[str, object]] = []
        self._principal = ""

    def grant(self, principal: str) -> None:
        if self._opened or self._principal:
            raise SelectedXcodeBuildOrchestratorError("private read lease is already active")
        if re.fullmatch(r"[A-Za-z0-9_.-]+", principal) is None:
            raise SelectedXcodeBuildOrchestratorError("build principal name is malformed")
        self._principal = principal
        try:
            for path, host_only in self._paths:
                descriptor, is_directory = _open_lease_subject(path)
                record: dict[str, object] = {
                    "descriptor": descriptor,
                    "path": path,
                    "before": "",
                    "acl": _acl_text(principal, is_directory, host_only),
                    "added": False,
                }
                self._opened.append(record)
                before = _acl_listing(descriptor)
                record["before"] = before
                _chmod_acl(descriptor, "+a", str(record["acl"]))
                record["added"] = True
                after = _acl_listing(descriptor)
                if after == before or principal not in after:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease ACL did not materialize exactly: {path}"
                    )
        except Exception:
            try:
                self.revoke()
            except Exception as cleanup_error:
                raise SelectedXcodeBuildOrchestratorError(
                    "private read-lease admission failed and exact rollback also failed"
                ) from cleanup_error
            raise

    def revoke(self, *, suppress_errors: bool = False) -> None:
        failures: list[str] = []
        for record in reversed(self._opened):
            descriptor = int(record["descriptor"])
            path = Path(record["path"])
            try:
                if bool(record["added"]):
                    _chmod_acl(descriptor, "-a", str(record["acl"]))
                    restored = _acl_listing(descriptor)
                    if restored != str(record["before"]):
                        raise SelectedXcodeBuildOrchestratorError(
                            f"private read-lease ACL did not restore exact prior state: {path}"
                        )
            except Exception as error:
                failures.append(f"{path}: {error}")
            finally:
                try:
                    os.close(descriptor)
                except OSError as error:
                    failures.append(f"{path}: descriptor close failed: {error}")
        self._opened = []
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
                raise SelectedXcodeBuildOrchestratorError("accepted guard bundle write made no progress")
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
        raise SelectedXcodeBuildOrchestratorError("accepted guard bundle file custody is not root read-only")


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
            raise SelectedXcodeBuildOrchestratorError("accepted guard bundle directory is not root read-only")
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
        raise SelectedXcodeBuildOrchestratorError("caller supplied the accepted guard materialization path")
    replaced = list(command)
    replaced[matches[0]] = str(accepted_guard)
    return replaced


def _flag_path(command: Sequence[str], flag: str) -> Path:
    matches = [index for index, value in enumerate(command) if value == flag]
    if len(matches) != 1 or matches[0] + 1 >= len(command):
        raise SelectedXcodeBuildOrchestratorError(f"private-input guard requires exactly one {flag}")
    value = command[matches[0] + 1]
    if value == "--" or value.startswith("--"):
        raise SelectedXcodeBuildOrchestratorError(f"private-input guard {flag} has no path")
    return _absolute_lexical(Path(value))


def _private_read_subjects(command: Sequence[str], repo: Path) -> tuple[Path, Path]:
    repo = _absolute_lexical(repo)
    live_guard = repo / ACCEPTED_GUARD_RELATIVE
    guard_indices = [index for index, value in enumerate(command) if value == str(live_guard)]
    if len(guard_indices) != 1:
        raise SelectedXcodeBuildOrchestratorError("canonical private-input guard invocation is missing")
    guard_index = guard_indices[0]
    if guard_index < 2 or list(command[guard_index - 2 : guard_index]) != ["/usr/bin/python3", "-I"]:
        raise SelectedXcodeBuildOrchestratorError("canonical private-input guard interpreter shape changed")

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
        raise SelectedXcodeBuildOrchestratorError("private-input guard build separator is ambiguous")
    return repo / CANONICAL_SDK_RELATIVE, repo / CANONICAL_RUNTIME_RELATIVE


def _bind_private_read_lease(build_origin: dict[str, object], lease: _PrivateReadLease) -> None:
    original = _require_callable(
        build_origin, "_run_exec_bound_build", "signed build-origin helper"
    )

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
            raise SelectedXcodeBuildOrchestratorError("build-origin helper exposed no exact build principal")
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

    # Functions loaded by exec keep this namespace as their globals. Rebinding only
    # this accepted internal execution seam composes the lease around the exact
    # dedicated-identity exec without changing caller-selected compiler authority.
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
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode build composition requires root on macOS")
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
    _decode_verified_git_blob(freeze_helper_base64, freeze_helper_blob, "selected-Xcode freeze helper")
    build_origin_raw = _decode_verified_git_blob(
        build_origin_base64, build_origin_blob, "signed build-origin helper"
    )
    _decode_verified_git_blob(install_custody_base64, install_custody_blob, "signed install-custody helper")

    bundle: Path | None = None
    lease: _PrivateReadLease | None = None
    try:
        bundle, accepted_guard, _accepted_provenance = _materialize_accepted_guard_bundle(repo, source_sha)
        guarded_command = _replace_live_guard(
            command,
            live_guard=live_guard,
            accepted_guard=accepted_guard,
        )

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
            raise SelectedXcodeBuildOrchestratorError("signed build-origin helper returned malformed custody result")
        stage_root, fingerprint = result
        if not isinstance(stage_root, Path) or not isinstance(fingerprint, str):
            raise SelectedXcodeBuildOrchestratorError("signed build-origin helper returned invalid custody types")
        if lease._opened or lease._principal:
            raise SelectedXcodeBuildOrchestratorError("private read lease survived the guarded build window")
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
            raise SelectedXcodeBuildOrchestratorError("selected-Xcode build result contains malformed separators")
        sys.stdout.write("\t".join(values) + "\n")
        return 0
    except Exception as error:
        print(f"ERROR: selected-Xcode signed-build composition failed: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
