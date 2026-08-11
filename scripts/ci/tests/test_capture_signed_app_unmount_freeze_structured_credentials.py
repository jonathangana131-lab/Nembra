#!/usr/bin/env python3
"""Replay APFS compiler-output quiescence without an opaque preexec_fn.

The corrected #3004 witness currently dies inside Python's custom pre-exec
credential shim on the GitHub macOS runner, before the detached writer arms.
This validation-only successor preserves the same filesystem authority oracle but
asks subprocess/Python to perform the POSIX user/group transition through its
structured ``user``, ``group``, and ``extra_groups`` arguments.

A green result means the APFS detach/read-only-remount primitive received a real
kernel test under the intended one-run supplementary-GID model. It is architecture
feasibility only: no signing identity, Xcode product, device, Bluetooth, Tuya,
install, launch, or physical authority is created.
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
BASE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_UNMOUNT_STRUCTURED_CREDENTIAL_JSON="
ERROR_MARKER = "NEMBRA_UNMOUNT_STRUCTURED_CREDENTIAL_ERROR="
INITIAL_BYTES = b"INITIAL_BUILD_OUTPUT\n"
POST_LOCK_BYTES = b"POST_LOCK_DETACHED_WRITE\n"


class ProbeError(RuntimeError):
    pass


def load_base_helper():
    spec = importlib.util.spec_from_file_location("nembra_unmount_base", BASE_HELPER_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load #3004 unmount helper")
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


def structured_credentials(uid: int, gid: int, groups: list[int]) -> dict[str, object]:
    """Return Popen's native POSIX credential arguments, with no user preexec hook."""
    return {
        "user": uid,
        "group": gid,
        "extra_groups": sorted(set(groups)),
    }


def wait_for(path: Path, *, timeout: float = 8.0) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return path.read_text(encoding="utf-8").strip()
        except FileNotFoundError:
            time.sleep(0.03)
    raise ProbeError(f"timed out waiting for detached-writer marker: {path.name}")


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
        emit_error("environment", "root probe requires sudo on real macOS")
        return 70
    helper = load_base_helper()

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
    workspace = Path(tempfile.mkdtemp(prefix="nembra-unmount-structured.", dir="/private/tmp"))
    os.chown(workspace, 0, capability_gid)
    os.chmod(workspace, 0o710)
    image = workspace / "origin-freeze.sparseimage"
    mountpoint = workspace / "mount"
    control = workspace / "control"
    mountpoint.mkdir()
    control.mkdir()
    os.chown(control, uid, gid)
    os.chmod(control, 0o700)

    child_env = {
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
    }
    device: str | None = None
    writer: subprocess.Popen[str] | None = None
    try:
        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, 0, capability_gid)
        os.chmod(mountpoint, 0o770)

        target = mountpoint / "compiler-output.bin"
        target.write_bytes(INITIAL_BYTES)
        os.chown(target, uid, capability_gid)
        os.chmod(target, 0o660)

        ready = control / "ready"
        write_request = control / "write-request"
        write_ack = control / "write-ack"
        close_request = control / "close-request"
        close_ack = control / "close-ack"

        try:
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
                env=child_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True,
                **structured_credentials(uid, gid, capability_groups),
            )
        except (OSError, subprocess.SubprocessError) as error:
            emit_error(
                "credential-launch",
                f"structured capability child launch failed: {type(error).__name__}: {error}",
                errno=getattr(error, "errno", None),
                pythonVersion=sys.version,
            )
            return 72

        if wait_for(ready) != "ready":
            raise ProbeError("detached writer did not establish its held descriptor")

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)

        try:
            path_attack = subprocess.run(
                ["/bin/sh", "-c", 'printf "PATH_ATTACK\\n" >> "$1"', "sh", str(target)],
                env=child_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                **structured_credentials(uid, gid, normal_groups),
            )
        except (OSError, subprocess.SubprocessError) as error:
            emit_error(
                "credential-launch",
                f"structured ordinary-user attack launch failed: {type(error).__name__}: {error}",
                errno=getattr(error, "errno", None),
            )
            return 73
        if path_attack.returncode == 0:
            raise ProbeError("same-UID sibling still had pathname write authority after root lock")

        first_detach = helper.hdiutil_detach(device)
        first_detach_output = ((first_detach.stdout or "") + "\n" + (first_detach.stderr or "")).strip()
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
        if target.read_bytes() != INITIAL_BYTES + POST_LOCK_BYTES:
            raise ProbeError("post-lock held-descriptor bytes were not durably visible before freeze")

        close_request.write_text("close\n", encoding="utf-8")
        if wait_for(close_ack) != "closed":
            raise ProbeError("detached writer did not close its held descriptor")
        writer.wait(timeout=5)
        if writer.returncode != 0:
            stderr = writer.stderr.read() if writer.stderr is not None else ""
            raise ProbeError(f"detached writer exited {writer.returncode}: {stderr.strip()}")

        second_detach = helper.hdiutil_detach(device)
        second_detach_output = ((second_detach.stdout or "") + "\n" + (second_detach.stderr or "")).strip()
        if second_detach.returncode != 0:
            raise ProbeError(
                "non-forced detach still failed after the detached writer closed: " + second_detach_output
            )
        device = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        expected = INITIAL_BYTES + POST_LOCK_BYTES
        if target.read_bytes() != expected:
            raise ProbeError("read-only remount did not preserve the exact quiesced compiler-output bytes")

        root_readonly_errno: int | None = None
        try:
            with target.open("ab", buffering=0) as handle:
                handle.write(b"ROOT_AFTER_FREEZE\n")
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as error:
            root_readonly_errno = error.errno
        if root_readonly_errno is None or target.read_bytes() != expected:
            raise ProbeError("read-only remount accepted a root write or changed frozen bytes")

        try:
            readonly_attack = subprocess.run(
                ["/bin/sh", "-c", 'printf "AFTER_FREEZE\\n" >> "$1"', "sh", str(target)],
                env=child_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                **structured_credentials(uid, gid, capability_groups),
            )
        except (OSError, subprocess.SubprocessError) as error:
            emit_error(
                "credential-launch",
                f"structured former-capability launch failed: {type(error).__name__}: {error}",
                errno=getattr(error, "errno", None),
            )
            return 74
        if readonly_attack.returncode == 0 or target.read_bytes() != expected:
            raise ProbeError("former capability mutated the read-only remount")

        evidence = {
            "schemaVersion": 1,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "capabilityGID": capability_gid,
            "normalGroupsContainCapability": capability_gid in normal_groups,
            "structuredCredentialLaunch": True,
            "pathAttackReturnCode": path_attack.returncode,
            "firstDetachReturnCode": first_detach.returncode,
            "firstDetachOutput": first_detach_output,
            "heldDescriptorPostLockWrite": write_result,
            "secondDetachReturnCode": second_detach.returncode,
            "secondDetachOutput": second_detach_output,
            "rootReadonlyWriteErrno": root_readonly_errno,
            "readonlyAttackReturnCode": readonly_attack.returncode,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (ProbeError, subprocess.TimeoutExpired, OSError) as error:
        emit_error("probe", str(error), errorType=type(error).__name__, errno=getattr(error, "errno", None))
        return 75
    finally:
        if writer is not None and writer.poll() is None:
            writer.kill()
            try:
                writer.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        if device is not None:
            helper.hdiutil_detach(device, force=True)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "structured-credential unmount probe requires macOS")
        return 80
    sudo = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sudo.returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 80
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
        emit_error("evidence", "missing or ambiguous structured-credential unmount evidence")
        return 81
    evidence = json.loads(records[0])
    required = (
        evidence.get("structuredCredentialLaunch") is True
        and evidence.get("normalGroupsContainCapability") is False
        and evidence.get("pathAttackReturnCode") != 0
        and evidence.get("firstDetachReturnCode") != 0
        and evidence.get("heldDescriptorPostLockWrite") == "write-ok"
        and evidence.get("secondDetachReturnCode") == 0
        and isinstance(evidence.get("rootReadonlyWriteErrno"), int)
        and evidence.get("rootReadonlyWriteErrno") != 0
        and evidence.get("readonlyAttackReturnCode") != 0
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        emit_error("evidence", f"structured-credential unmount evidence failed semantic checks: {evidence}")
        return 82
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    args = parser.parse_args()
    return root_probe() if args.root_probe else parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
