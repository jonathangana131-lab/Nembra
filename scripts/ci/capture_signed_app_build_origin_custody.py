#!/usr/bin/env python3
"""Bind the physical install subject to the exact xcodebuild-produced Capture.app.

This helper is the privileged supervisor for the narrow compiler-output -> protected-install-stage
handoff. It intentionally does not grant the invoking UID path authority to its DerivedData root.
Instead, one otherwise-unused supplementary gid is a process capability carried only by the guarded
build process group. After xcodebuild exits, root revokes that filesystem capability, fingerprints
the now-inaccessible output, and snapshots the exact bytes into the canonical root-owned install
stage before the invoking process regains control.

The helper is executed from bytes resolved from the exact accepted Git tree by the field installer.
It is not itself field authorization; downstream provenance, signature, profile, target-device, and
Final-GO gates remain required.
"""

from __future__ import annotations

import argparse
import base64
import grp
import os
import pwd
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable, Sequence

DERIVED_PREFIX = "nembra-authenticated-capture-derived."
STAGE_PREFIX = "nembra-authenticated-capture-install."
DEFAULT_APP_RELATIVE = Path("Build/Products/Debug-iphoneos/Nembra Capture.app")
DERIVED_PLACEHOLDER = "__NEMBRA_PROTECTED_DERIVED__"


class BuildOriginCustodyError(RuntimeError):
    pass


def _require_real_private_tmp() -> Path:
    root = Path("/private/tmp")
    try:
        metadata = root.lstat()
    except OSError as error:
        raise BuildOriginCustodyError("/private/tmp is unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise BuildOriginCustodyError("/private/tmp is not one real directory")
    return root


def _invoking_identity() -> tuple[str, int, int, str, tuple[int, ...]]:
    if os.geteuid() != 0:
        raise BuildOriginCustodyError("build-origin custody must run as root through sudo")
    raw_uid = os.environ.get("SUDO_UID", "")
    raw_gid = os.environ.get("SUDO_GID", "")
    sudo_user = os.environ.get("SUDO_USER", "")
    if not raw_uid.isdigit() or not raw_gid.isdigit() or not sudo_user:
        raise BuildOriginCustodyError("sudo did not expose one invoking-user identity")
    uid = int(raw_uid)
    gid = int(raw_gid)
    if uid <= 0:
        raise BuildOriginCustodyError("root may not be the field-build invoking identity")
    account = pwd.getpwuid(uid)
    if account.pw_name != sudo_user or account.pw_gid != gid:
        raise BuildOriginCustodyError("sudo invoking identity does not match the local account database")
    groups = tuple(sorted(set(os.getgrouplist(account.pw_name, gid))))
    return account.pw_name, uid, gid, account.pw_dir, groups


def _choose_capability_gid(
    invoking_groups: Sequence[int],
    *,
    randbelow: Callable[[int], int] = secrets.randbelow,
) -> int:
    """Choose a high numeric gid absent from the named group database and caller groups."""

    occupied = {entry.gr_gid for entry in grp.getgrall()}
    occupied.update(int(value) for value in invoking_groups)
    occupied.add(0)
    low = 1 << 29
    span = (1 << 30) - low
    for _ in range(256):
        candidate = low + randbelow(span)
        if candidate not in occupied:
            return candidate
    raise BuildOriginCustodyError("could not allocate an isolated one-run build capability gid")


def _structured_credentials(
    uid: int,
    gid: int,
    extra_groups: Sequence[int],
) -> dict[str, object]:
    """Describe one minimum-authority POSIX child identity without Python pre-exec code."""

    if uid <= 0 or gid < 0:
        raise BuildOriginCustodyError("structured child credentials require a non-root invoking identity")
    normalized = tuple(
        sorted(
            {
                int(value)
                for value in extra_groups
                if int(value) != gid
            }
        )
    )
    if any(value <= 0 for value in normalized):
        raise BuildOriginCustodyError("structured child supplementary groups contain invalid authority")
    return {
        "user": uid,
        "group": gid,
        "extra_groups": list(normalized),
    }


def _invalidate_invoker_sudo(
    uid: int,
    gid: int,
    environment: dict[str, str],
) -> None:
    """Revoke caller-side cached sudo before any protected build output exists."""

    credentials = _structured_credentials(uid, gid, ())
    revoke = subprocess.run(
        ["/usr/bin/sudo", "-K"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    if revoke.returncode != 0:
        raise BuildOriginCustodyError("could not invalidate invoking-user sudo timestamp before build custody")
    probe = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    if probe.returncode == 0:
        raise BuildOriginCustodyError(
            "noninteractive sudo remains available after invalidation; build-origin isolation cannot be established"
        )


def _child_environment(user: str, home: str) -> dict[str, str]:
    environment = {
        "HOME": home,
        "USER": user,
        "LOGNAME": user,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
    }
    for key in ("LANG", "LC_ALL", "LC_CTYPE", "TERM", "__CF_USER_TEXT_ENCODING"):
        value = os.environ.get(key)
        if value:
            environment[key] = value
    return environment


def _replace_derived_placeholder(command: Sequence[str], derived_root: Path) -> list[str]:
    if not command:
        raise BuildOriginCustodyError("no guarded build command was supplied")
    matches = sum(argument.count(DERIVED_PLACEHOLDER) for argument in command)
    if matches != 1:
        raise BuildOriginCustodyError(
            "guarded build command must contain exactly one protected DerivedData placeholder"
        )
    return [argument.replace(DERIVED_PLACEHOLDER, str(derived_root)) for argument in command]


def _validate_app_relative(path: Path) -> Path:
    if path.is_absolute() or not path.parts or any(part in ("", ".", "..") for part in path.parts):
        raise BuildOriginCustodyError(
            "app-relative path must remain strictly beneath protected DerivedData"
        )
    return path


def _assert_real_ancestry(root: Path, relative: Path) -> Path:
    current = root
    for component in relative.parts:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise BuildOriginCustodyError(f"expected build output is missing: {current}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise BuildOriginCustodyError(f"build-output ancestry contains a symlink: {current}")
    if not current.is_dir():
        raise BuildOriginCustodyError("build output app is not one real directory")
    return current


def _load_fingerprint_helper(encoded: str):
    try:
        source = base64.b64decode(encoded, validate=True)
    except Exception as error:
        raise BuildOriginCustodyError("accepted install-custody helper transport is malformed") from error
    namespace = {
        "__name__": "nembra_signed_app_install_custody",
        "__file__": "<accepted-signed-app-install-custody>",
    }
    try:
        exec(
            compile(source, "<accepted-signed-app-install-custody>", "exec", dont_inherit=True),
            namespace,
        )
    except Exception as error:
        raise BuildOriginCustodyError("accepted install-custody helper could not be loaded") from error
    fingerprint = namespace.get("fingerprint")
    if not callable(fingerprint):
        raise BuildOriginCustodyError(
            "accepted install-custody helper exposes no fingerprint function"
        )
    return fingerprint


def _terminate_remaining_process_group(process_group: int) -> None:
    """Do not let ordinary xcodebuild descendants retain the one-run capability."""

    try:
        os.killpg(process_group, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        try:
            os.killpg(process_group, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.killpg(process_group, signal.SIGKILL)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        try:
            os.killpg(process_group, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    raise BuildOriginCustodyError(
        "guarded build left a live process in its isolated process group"
    )


def _prepare_derived(private_tmp: Path, capability_gid: int) -> Path:
    derived = Path(tempfile.mkdtemp(prefix=DERIVED_PREFIX, dir=private_tmp))
    os.chown(derived, 0, capability_gid)
    os.chmod(derived, 0o770)
    return derived


def _copy_to_stage(source_app: Path, private_tmp: Path) -> tuple[Path, Path]:
    stage_root = Path(tempfile.mkdtemp(prefix=STAGE_PREFIX, dir=private_tmp))
    os.chown(stage_root, 0, 0)
    os.chmod(stage_root, 0o700)
    stage_app = stage_root / "Nembra Capture.app"
    subprocess.run(
        ["/usr/bin/ditto", "--noacl", str(source_app), str(stage_app)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    acl = subprocess.run(
        ["/usr/bin/find", str(stage_root), "-acl", "-print", "-quit"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()
    if acl:
        raise BuildOriginCustodyError(f"protected stage retained an ACL: {acl}")

    # Preserve symlink objects rather than following them while transferring root ownership.
    for current_root, directories, files in os.walk(stage_root, topdown=False, followlinks=False):
        current = Path(current_root)
        for name in files:
            os.chown(current / name, 0, 0, follow_symlinks=False)
        for name in directories:
            os.chown(current / name, 0, 0, follow_symlinks=False)
        os.chown(current, 0, 0, follow_symlinks=False)
    os.chmod(stage_root, 0o755)
    return stage_root, stage_app


def run_custodied_build(
    command: Sequence[str],
    *,
    app_relative: Path,
    fingerprint_helper_base64: str,
) -> tuple[Path, str]:
    private_tmp = _require_real_private_tmp()
    user, uid, gid, home, invoking_groups = _invoking_identity()
    child_env = _child_environment(user, home)

    # The outer sudo invocation is needed only to establish this supervisor. Revoke its caller-side
    # cached authority before creating the protected output root. A passwordless/noninteractive sudo
    # policy is deliberately rejected because it defeats the intended same-UID isolation boundary.
    _invalidate_invoker_sudo(uid, gid, child_env)

    capability_gid = _choose_capability_gid(invoking_groups)
    derived_root: Path | None = None
    stage_root: Path | None = None
    process: subprocess.Popen[str] | None = None
    fingerprint = _load_fingerprint_helper(fingerprint_helper_base64)
    try:
        derived_root = _prepare_derived(private_tmp, capability_gid)
        guarded_command = _replace_derived_placeholder(command, derived_root)
        # Do not replay ambient supplementary groups into the authority-bearing compiler child.
        # Its primary gid is supplied separately; the fresh one-run capability is the only extra gid.
        child_groups = (capability_gid,)
        process = subprocess.Popen(
            guarded_command,
            cwd=os.getcwd(),
            env=child_env,
            stdin=None,
            stdout=sys.stderr,
            stderr=sys.stderr,
            text=True,
            start_new_session=True,
            **_structured_credentials(uid, gid, child_groups),
        )
        returncode = process.wait()
        # Revoke the transient filesystem capability at the first privileged instruction after the
        # guarded build returns. The group-owner change removes the one-run gid from the root
        # traversal decision; mode 0700 makes that closure explicit before descendant cleanup.
        os.chown(derived_root, 0, 0)
        os.chmod(derived_root, 0o700)
        _terminate_remaining_process_group(process.pid)
        if returncode != 0:
            raise BuildOriginCustodyError(
                f"guarded field build failed with exit status {returncode}"
            )

        source_app = _assert_real_ancestry(
            derived_root,
            _validate_app_relative(app_relative),
        )
        source_fingerprint = str(fingerprint(source_app))
        if len(source_fingerprint) != 64 or any(
            character not in "0123456789abcdef" for character in source_fingerprint
        ):
            raise BuildOriginCustodyError("build-produced app fingerprint is malformed")

        stage_root, stage_app = _copy_to_stage(source_app, private_tmp)
        staged_fingerprint = str(fingerprint(stage_app))
        if staged_fingerprint != source_fingerprint:
            raise BuildOriginCustodyError(
                "protected stage differs from the isolated xcodebuild-produced app"
            )
        return stage_root, source_fingerprint
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or "").strip()
        raise BuildOriginCustodyError(
            "protected signed-app staging command failed"
            + (f": {detail}" if detail else "")
        ) from error
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        if derived_root is not None:
            shutil.rmtree(derived_root, ignore_errors=True)
        if sys.exc_info()[0] is not None and stage_root is not None:
            shutil.rmtree(stage_root, ignore_errors=True)


def _parse_args(argv: Sequence[str]) -> tuple[Path, str, list[str]]:
    parser = argparse.ArgumentParser(
        description=(
            "Build the signed Capture app inside one root-supervised output custody life and "
            "return its protected stage."
        )
    )
    parser.add_argument("--app-relative", default=str(DEFAULT_APP_RELATIVE))
    parser.add_argument("--install-custody-helper-base64", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    return Path(args.app_relative), args.install_custody_helper_base64, command


def main(argv: Sequence[str] | None = None) -> int:
    try:
        app_relative, helper_source, command = _parse_args(
            sys.argv[1:] if argv is None else argv
        )
        stage_root, fingerprint = run_custodied_build(
            command,
            app_relative=app_relative,
            fingerprint_helper_base64=helper_source,
        )
        sys.stdout.write(f"{stage_root}\t{fingerprint}\n")
        return 0
    except BuildOriginCustodyError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
