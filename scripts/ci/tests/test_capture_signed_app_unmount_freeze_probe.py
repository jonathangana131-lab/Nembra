#!/usr/bin/env python3
"""Validate a kernel-backed freeze boundary for signed-app compiler output.

The current signed-app build-origin repair removes pathname access after xcodebuild returns, but a
process that detached from the original process group can retain an already-open writable descriptor.
This validation-only probe asks a narrower question: can a non-forced disk-image detach serve as the
quiescence boundary before any compiler-output fingerprint is minted?

The witness deliberately keeps a writable file descriptor open from a detached same-UID process.
It requires the first detach to fail while that reference is live, proves the descriptor can still
mutate bytes after ordinary pathname access is revoked, then closes the descriptor and requires a
second detach to succeed. The image is reattached read-only and the exact post-quiescence bytes are
verified while a same-UID write is rejected.

No Xcode build, signing identity, device, Bluetooth, Tuya traffic, install, launch, or physical action
occurs here. A green result is architecture-feasibility evidence only.
"""

from __future__ import annotations

import argparse
import grp
import json
import os
from pathlib import Path
import plistlib
import pwd
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import time

MARKER = "NEMBRA_UNMOUNT_FREEZE_JSON="
ERROR_MARKER = "NEMBRA_UNMOUNT_FREEZE_ERROR="
POST_LOCK_BYTES = b"POST_LOCK_DETACHED_WRITE\n"


class ProbeError(RuntimeError):
    pass


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "kind": kind,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def choose_capability_gid(normal_groups: list[int]) -> int:
    occupied = {entry.gr_gid for entry in grp.getgrall()}
    occupied.update(normal_groups)
    occupied.add(0)
    low = 1 << 29
    span = (1 << 30) - low
    for _ in range(256):
        candidate = low + secrets.randbelow(span)
        if candidate not in occupied:
            return candidate
    raise ProbeError("could not allocate an isolated numeric capability gid")


def drop(uid: int, gid: int, groups: list[int]):
    normalized = sorted(set(groups))

    def apply() -> None:
        os.setgroups(normalized)
        os.setgid(gid)
        os.setuid(uid)

    return apply


def wait_for(path: Path, *, timeout: float = 8.0) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return path.read_text(encoding="utf-8").strip()
        except FileNotFoundError:
            time.sleep(0.03)
    raise ProbeError(f"timed out waiting for detached-writer marker: {path.name}")


def hdiutil_create(image: Path) -> None:
    completed = subprocess.run(
        [
            "/usr/bin/hdiutil",
            "create",
            "-quiet",
            "-size",
            "128m",
            "-type",
            "SPARSE",
            "-fs",
            "APFS",
            "-volname",
            "NembraOriginFreeze",
            str(image),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise ProbeError(f"hdiutil create failed: {completed.stderr.strip()}")


def hdiutil_attach(image: Path, mountpoint: Path, *, readonly: bool) -> str:
    command = [
        "/usr/bin/hdiutil",
        "attach",
        "-plist",
        "-nobrowse",
        "-mountpoint",
        str(mountpoint),
    ]
    if readonly:
        command.append("-readonly")
    command.append(str(image))
    completed = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise ProbeError(
            "hdiutil attach failed: " + completed.stderr.decode("utf-8", errors="replace").strip()
        )
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise ProbeError("hdiutil attach returned malformed plist output") from error
    entities = payload.get("system-entities", [])
    for entity in entities:
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise ProbeError("hdiutil attach returned no mounted device for the requested mountpoint")


def hdiutil_detach(device: str, *, force: bool = False) -> subprocess.CompletedProcess[str]:
    command = ["/usr/bin/hdiutil", "detach"]
    if force:
        command.append("-force")
    command.append(device)
    return subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def detached_writer_code() -> str:
    return r'''
import os
from pathlib import Path
import sys
import time

target = Path(sys.argv[1])
ready = Path(sys.argv[2])
write_request = Path(sys.argv[3])
write_ack = Path(sys.argv[4])
close_request = Path(sys.argv[5])
close_ack = Path(sys.argv[6])

fd = os.open(target, os.O_WRONLY | os.O_APPEND)
ready.write_text("ready\n", encoding="utf-8")
try:
    while not write_request.exists():
        time.sleep(0.02)
    try:
        os.write(fd, b"POST_LOCK_DETACHED_WRITE\n")
        os.fsync(fd)
        write_ack.write_text("write-ok\n", encoding="utf-8")
    except OSError as error:
        write_ack.write_text(f"write-errno-{error.errno}\n", encoding="utf-8")
    while not close_request.exists():
        time.sleep(0.02)
finally:
    os.close(fd)
    close_ack.write_text("closed\n", encoding="utf-8")
'''


def root_probe() -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "root probe requires sudo on macOS")
        return 70
    for tool in ("/usr/bin/hdiutil", "/usr/bin/python3"):
        if not Path(tool).is_file():
            emit_error("environment", f"required macOS tool is missing: {tool}")
            return 70

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
    capability_gid = choose_capability_gid(normal_groups)
    workspace = Path(tempfile.mkdtemp(prefix="nembra-unmount-freeze.", dir="/private/tmp"))
    image = workspace / "origin-freeze.sparseimage"
    mountpoint = workspace / "mount"
    control = workspace / "control"
    mountpoint.mkdir()
    control.mkdir()
    os.chown(control, uid, gid)
    os.chmod(control, 0o700)

    device: str | None = None
    writer: subprocess.Popen[str] | None = None
    try:
        hdiutil_create(image)
        device = hdiutil_attach(image, mountpoint, readonly=False)

        os.chown(mountpoint, 0, capability_gid)
        os.chmod(mountpoint, 0o770)
        target = mountpoint / "compiler-output.bin"
        target.write_bytes(b"INITIAL_BUILD_OUTPUT\n")
        os.chown(target, uid, capability_gid)
        os.chmod(target, 0o660)

        ready = control / "ready"
        write_request = control / "write-request"
        write_ack = control / "write-ack"
        close_request = control / "close-request"
        close_ack = control / "close-ack"
        child_groups = sorted(set(normal_groups) | {capability_gid})
        writer = subprocess.Popen(
            [
                "/usr/bin/python3",
                "-I",
                "-c",
                detached_writer_code(),
                str(target),
                str(ready),
                str(write_request),
                str(write_ack),
                str(close_request),
                str(close_ack),
            ],
            cwd="/private/tmp",
            env={
                "HOME": account.pw_dir,
                "USER": account.pw_name,
                "LOGNAME": account.pw_name,
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": "/tmp",
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            preexec_fn=drop(uid, gid, child_groups),
        )
        if wait_for(ready) != "ready":
            raise ProbeError("detached writer did not establish its held descriptor")

        # Model the current #2995 pathname revocation. A newly opened same-UID path must fail, but
        # the already-held descriptor intentionally remains capable until kernel-backed quiescence.
        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        path_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "PATH_ATTACK\\n" >> "$1"', "sh", str(target)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=drop(uid, gid, normal_groups),
            check=False,
        )
        if path_attack.returncode == 0:
            raise ProbeError("same-UID sibling still had pathname write authority after root lock")

        first_detach = hdiutil_detach(device)
        if first_detach.returncode == 0:
            device = None
            raise ProbeError(
                "non-forced detach succeeded while a detached process retained an open writable file descriptor"
            )

        write_request.write_text("go\n", encoding="utf-8")
        write_result = wait_for(write_ack)
        if write_result != "write-ok":
            raise ProbeError(
                "held descriptor could not demonstrate the post-lock mutation seam before quiescence: "
                + write_result
            )
        if target.read_bytes() != b"INITIAL_BUILD_OUTPUT\n" + POST_LOCK_BYTES:
            raise ProbeError("post-lock held-descriptor bytes were not durably visible before freeze")

        close_request.write_text("close\n", encoding="utf-8")
        if wait_for(close_ack) != "closed":
            raise ProbeError("detached writer did not close its held descriptor")
        writer.wait(timeout=5)
        if writer.returncode != 0:
            raise ProbeError("detached writer exited nonzero after closing its descriptor")

        second_detach = hdiutil_detach(device)
        if second_detach.returncode != 0:
            raise ProbeError(
                "non-forced detach still failed after the detached writer closed: "
                + second_detach.stderr.strip()
            )
        device = None

        device = hdiutil_attach(image, mountpoint, readonly=True)
        frozen = target.read_bytes()
        expected = b"INITIAL_BUILD_OUTPUT\n" + POST_LOCK_BYTES
        if frozen != expected:
            raise ProbeError("read-only remount did not preserve the exact quiesced compiler-output bytes")

        readonly_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "AFTER_FREEZE\\n" >> "$1"', "sh", str(target)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=drop(uid, gid, child_groups),
            check=False,
        )
        if readonly_attack.returncode == 0 or target.read_bytes() != expected:
            raise ProbeError("same-UID capability process mutated the image after read-only remount")

        evidence = {
            "schemaVersion": 1,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "capabilityGID": capability_gid,
            "normalGroupsContainCapability": capability_gid in normal_groups,
            "pathAttackReturnCode": path_attack.returncode,
            "firstDetachReturnCode": first_detach.returncode,
            "heldDescriptorPostLockWrite": write_result,
            "secondDetachReturnCode": second_detach.returncode,
            "readonlyAttackReturnCode": readonly_attack.returncode,
            "frozenByteCount": len(frozen),
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (ProbeError, subprocess.TimeoutExpired) as error:
        emit_error("probe", str(error))
        return 72
    finally:
        if writer is not None and writer.poll() is None:
            writer.kill()
            try:
                writer.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        if device is not None:
            hdiutil_detach(device, force=True)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "unmount-freeze probe requires macOS")
        return 76
    sudo = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sudo.returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 76
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
        emit_error("evidence", "missing or ambiguous unmount-freeze evidence")
        return 77
    evidence = json.loads(records[0])
    required = (
        evidence.get("normalGroupsContainCapability") is False
        and evidence.get("pathAttackReturnCode") != 0
        and evidence.get("firstDetachReturnCode") != 0
        and evidence.get("heldDescriptorPostLockWrite") == "write-ok"
        and evidence.get("secondDetachReturnCode") == 0
        and evidence.get("readonlyAttackReturnCode") != 0
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        emit_error("evidence", f"unmount-freeze evidence failed semantic checks: {evidence}")
        return 78
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    args = parser.parse_args()
    return root_probe() if args.root_probe else parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
