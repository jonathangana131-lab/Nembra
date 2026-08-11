#!/usr/bin/env python3
"""Validate non-forced unmount against retained nested directory-FD authority.

Validation-only child of corrected #3004. The current production candidate #2995 revokes future
pathname traversal but does not mechanically revoke already-open nested directory descriptors. This
probe deliberately keeps such a descriptor live in a detached same-UID process, proves it can create
a post-lock bundle entry with openat-style dir_fd authority, and then requires a non-forced APFS
detach to stay busy until that descriptor is closed. Only after a successful normal detach may the
image be reattached read-only and treated as frozen evidence.

No Xcode build, signing, device, Bluetooth, Tuya, install, launch, or physical action occurs here.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
FREEZE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_UNMOUNT_DIRFD_JSON="
ERROR_MARKER = "NEMBRA_UNMOUNT_DIRFD_ERROR="


class ProbeError(RuntimeError):
    pass


def load_helper():
    spec = importlib.util.spec_from_file_location("nembra_unmount_freeze", FREEZE_HELPER_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load corrected unmount-freeze helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "kind": kind,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def retained_dirfd_code() -> str:
    return r'''
import os
from pathlib import Path
import sys

bundle = Path(sys.argv[1])
bundle.mkdir(parents=True, exist_ok=True)
(bundle / "accepted.bin").write_bytes(b"ORIGINAL_BUILD_OUTPUT\n")
dirfd = os.open(
    bundle,
    os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0),
)
print("READY", flush=True)
try:
    command = sys.stdin.buffer.read(1)
    if command != b"W":
        raise SystemExit(91)
    late_fd = os.open(
        "late-entry.bin",
        os.O_CREAT | os.O_WRONLY | os.O_TRUNC,
        0o600,
        dir_fd=dirfd,
    )
    try:
        os.write(late_fd, b"DIRFD_POST_LOCK_WRITE\n")
        os.fsync(late_fd)
    finally:
        os.close(late_fd)
    print("WROTE", flush=True)
    command = sys.stdin.buffer.read(1)
    if command != b"C":
        raise SystemExit(92)
finally:
    os.close(dirfd)
print("CLOSED", flush=True)
'''


def read_line(process: subprocess.Popen[str], expected: str, *, timeout: float = 6.0) -> None:
    if process.stdout is None:
        raise ProbeError("detached writer stdout pipe is unavailable")
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        line = process.stdout.readline()
        if line:
            actual = line.strip()
            if actual != expected:
                raise ProbeError(f"detached writer emitted {actual!r}; expected {expected!r}")
            return
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr is not None else ""
            raise ProbeError(
                f"detached writer exited {process.returncode} before {expected!r}: {stderr.strip()}"
            )
        time.sleep(0.02)
    raise ProbeError(f"timed out waiting for detached writer marker {expected!r}")


def root_probe() -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "root probe requires sudo on real macOS")
        return 70
    helper = load_helper()
    try:
        uid = int(os.environ["SUDO_UID"])
        gid = int(os.environ["SUDO_GID"])
        user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if uid <= 0:
        emit_error("identity", "root is not a valid field-user identity")
        return 71
    account = pwd.getpwuid(uid)
    if account.pw_name != user or account.pw_gid != gid:
        emit_error("identity", "sudo identity does not match local account database")
        return 71

    normal_groups = sorted(set(os.getgrouplist(account.pw_name, gid)))
    capability_gid = helper.choose_capability_gid(normal_groups)
    capability_groups = sorted(set(normal_groups) | {capability_gid})
    workspace = Path(tempfile.mkdtemp(prefix="nembra-unmount-dirfd.", dir="/private/tmp"))
    image = workspace / "origin.sparseimage"
    mountpoint = workspace / "mount"
    mountpoint.mkdir()
    os.chown(workspace, 0, capability_gid)
    os.chmod(workspace, 0o710)
    device: str | None = None
    writer: subprocess.Popen[str] | None = None
    try:
        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, 0, capability_gid)
        os.chmod(mountpoint, 0o770)

        bundle = mountpoint / "DerivedData/Build/Products/Debug-iphoneos/Nembra Capture.app"
        child_env = {
            "HOME": account.pw_dir,
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": "/tmp",
            "LANG": "C",
            "LC_ALL": "C",
        }
        writer = subprocess.Popen(
            ["/usr/bin/python3", "-I", "-c", retained_dirfd_code(), str(bundle)],
            env=child_env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            preexec_fn=helper.drop(uid, gid, capability_groups),
        )
        read_line(writer, "READY")

        # Revoke fresh pathname access exactly before testing the retained nested descriptor.
        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)

        fresh_attack = subprocess.run(
            [
                "/bin/sh",
                "-c",
                'printf "FRESH_PATH_WRITE\\n" > "$1"',
                "sh",
                str(bundle / "fresh-path-entry.bin"),
            ],
            env=child_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=helper.drop(uid, gid, normal_groups),
            check=False,
        )
        if fresh_attack.returncode == 0:
            emit_error("pathname-isolation", "fresh same-UID pathname write survived mount-root lock")
            return 72

        if writer.stdin is None:
            raise ProbeError("detached writer stdin pipe is unavailable")
        writer.stdin.write("W")
        writer.stdin.flush()
        read_line(writer, "WROTE")

        late = bundle / "late-entry.bin"
        if late.read_bytes() != b"DIRFD_POST_LOCK_WRITE\n":
            emit_error("dirfd-authority", "retained nested directory FD did not produce expected post-lock bytes")
            return 73

        busy = helper.hdiutil_detach(device)
        busy_text = ((busy.stdout or "") + "\n" + (busy.stderr or "")).strip()
        if busy.returncode == 0:
            device = None
            emit_error(
                "quiescence",
                "non-forced detach succeeded while retained nested directory FD was still live",
                detachOutput=busy_text,
            )
            return 74

        writer.stdin.write("C")
        writer.stdin.flush()
        read_line(writer, "CLOSED")
        writer.wait(timeout=5)
        if writer.returncode != 0:
            stderr = writer.stderr.read() if writer.stderr is not None else ""
            emit_error("writer", f"detached directory-FD writer exited {writer.returncode}: {stderr.strip()}")
            return 75

        detached = helper.hdiutil_detach(device)
        detached_text = ((detached.stdout or "") + "\n" + (detached.stderr or "")).strip()
        if detached.returncode != 0:
            emit_error(
                "quiescence",
                "non-forced detach remained busy after retained directory FD closed",
                detachOutput=detached_text,
            )
            return 76
        device = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen_bundle = mountpoint / "DerivedData/Build/Products/Debug-iphoneos/Nembra Capture.app"
        frozen_late = frozen_bundle / "late-entry.bin"
        if frozen_late.read_bytes() != b"DIRFD_POST_LOCK_WRITE\n":
            emit_error("readonly-remount", "frozen directory-FD mutation bytes changed across remount")
            return 77

        root_create = subprocess.run(
            [
                "/bin/sh",
                "-c",
                'printf "ROOT_AFTER_FREEZE\\n" > "$1"',
                "sh",
                str(frozen_bundle / "root-after-freeze.bin"),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if root_create.returncode == 0:
            emit_error("readonly-remount", "root created a directory entry after read-only freeze")
            return 78

        former_capability = subprocess.run(
            [
                "/bin/sh",
                "-c",
                'printf "CAP_AFTER_FREEZE\\n" > "$1"',
                "sh",
                str(frozen_bundle / "cap-after-freeze.bin"),
            ],
            env=child_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=helper.drop(uid, gid, capability_groups),
            check=False,
        )
        if former_capability.returncode == 0:
            emit_error("readonly-remount", "former capability created a directory entry after read-only freeze")
            return 79

        evidence = {
            "schemaVersion": 1,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "capabilityGID": capability_gid,
            "normalGroupsContainCapability": capability_gid in normal_groups,
            "freshPathAttackReturnCode": fresh_attack.returncode,
            "retainedDirFDPostLockWrite": True,
            "busyDetachReturnCode": busy.returncode,
            "postCloseDetachReturnCode": detached.returncode,
            "rootReadonlyCreateReturnCode": root_create.returncode,
            "formerCapabilityReadonlyCreateReturnCode": former_capability.returncode,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (ProbeError, subprocess.TimeoutExpired, OSError) as error:
        emit_error("probe", str(error))
        return 80
    finally:
        if writer is not None and writer.poll() is None:
            try:
                if writer.stdin is not None:
                    writer.stdin.write("C")
                    writer.stdin.flush()
            except Exception:
                pass
            try:
                writer.terminate()
            except ProcessLookupError:
                pass
            try:
                writer.wait(timeout=2)
            except subprocess.TimeoutExpired:
                writer.kill()
                writer.wait()
        if device is not None:
            helper.hdiutil_detach(device, force=True)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "directory-FD unmount-freeze probe requires macOS")
        return 81
    sudo = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sudo.returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 81
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    if completed.returncode != 0:
        return completed.returncode
    records = [
        line[len(MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(MARKER)
    ]
    if len(records) != 1:
        emit_error("evidence", "missing or ambiguous directory-FD unmount-freeze evidence")
        return 82
    evidence = json.loads(records[0])
    required = (
        evidence.get("freshPathAttackReturnCode") != 0
        and evidence.get("retainedDirFDPostLockWrite") is True
        and evidence.get("busyDetachReturnCode") != 0
        and evidence.get("postCloseDetachReturnCode") == 0
        and evidence.get("rootReadonlyCreateReturnCode") != 0
        and evidence.get("formerCapabilityReadonlyCreateReturnCode") != 0
        and evidence.get("normalGroupsContainCapability") is False
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        emit_error("evidence", f"directory-FD unmount-freeze evidence failed semantic checks: {evidence}")
        return 83
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    args = parser.parse_args()
    if args.root_probe:
        return root_probe()
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
