#!/usr/bin/env python3
"""Validate APFS freeze semantics against an escaped writable shared mmap.

Validation-only child of #3027. The regular-file-FD and directory-FD probes do not
mechanically answer the distinct authority class where a compiler descendant maps
an output file MAP_SHARED/ACCESS_WRITE, closes its file descriptor, escapes the
original process group, and keeps only the writable mapping alive.

This witness proves the mapping can mutate compiler-output bytes after ordinary
pathname authority is revoked, then attempts a normal non-forced disk-image detach.
It accepts only two kernel-safe shapes:

* BUSY: the live mapping keeps the image mounted; after the mapping closes, normal
  detach must actually remove the image before any fingerprint could be minted.
* DETACHED: the image is mechanically absent even if hdiutil returned a surprising
  status; the escaped mapping may be exercised, but no post-detach mutation may
  persist into the subsequent read-only remount.

Detach classification uses hdiutil's machine-readable ``info -plist`` inventory,
not exit status alone. No Xcode signing identity, device, Bluetooth, Tuya traffic,
install, launch, or physical authority is created.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import pwd
import select
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
BASE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_APFS_MMAP_FREEZE_JSON="
ERROR_MARKER = "NEMBRA_APFS_MMAP_FREEZE_ERROR="
FILE_SIZE = 4096
PRE_OFFSET = 0
POST_OFFSET = 64
PRE_BYTES = b"PREDETACH_MAP_OK"
POST_BYTES = b"POSTDETACH_MAPOK"
INITIAL_BYTES = b"A" * FILE_SIZE


class ProbeError(RuntimeError):
    pass


def load_base_helper():
    spec = importlib.util.spec_from_file_location("nembra_unmount_base_for_mmap", BASE_HELPER_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load corrected APFS unmount helper")
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


def structured_credentials(uid: int, gid: int, extra_groups: list[int]) -> dict[str, object]:
    normalized = sorted({int(group) for group in extra_groups if int(group) != gid})
    if uid <= 0 or gid < 0 or any(group <= 0 for group in normalized):
        raise ProbeError("invalid structured child credentials")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def mapped_writer_code() -> str:
    return r'''
import mmap
import os
import sys

target = sys.argv[1]
fd = os.open(target, os.O_RDWR)
try:
    mapping = mmap.mmap(fd, 0, access=mmap.ACCESS_WRITE)
finally:
    os.close(fd)

# Only the writable shared mapping remains after READY; no file descriptor is kept.
print("READY", flush=True)
command = sys.stdin.buffer.read(1)
if command != b"W":
    raise SystemExit(91)
mapping[0:16] = b"PREDETACH_MAP_OK"
mapping.flush()
print("WROTE", flush=True)

command = sys.stdin.buffer.read(1)
if command == b"P":
    try:
        mapping[64:80] = b"POSTDETACH_MAPOK"
        mapping.flush()
        print("POSTDETACH_OK", flush=True)
    except BaseException as error:
        print(f"POSTDETACH_ERR:{type(error).__name__}:{error}", flush=True)
    command = sys.stdin.buffer.read(1)

if command != b"C":
    raise SystemExit(92)
mapping.close()
print("CLOSED", flush=True)
'''


def read_event(
    process: subprocess.Popen[str],
    *,
    timeout: float = 8.0,
    allow_signal_exit: bool = False,
) -> str:
    if process.stdout is None:
        raise ProbeError("mapping writer stdout unavailable")
    readable, _, _ = select.select([process.stdout], [], [], timeout)
    if readable:
        line = process.stdout.readline()
        if line:
            return line.strip()
        try:
            returncode = process.wait(timeout=2)
        except subprocess.TimeoutExpired as error:
            raise ProbeError("mapping writer closed stdout but remained live") from error
        if allow_signal_exit and returncode < 0:
            return f"POSTDETACH_SIGNAL:{-returncode}"
        stderr = process.stderr.read() if process.stderr is not None else ""
        raise ProbeError(f"mapping writer exited {returncode} without an event: {stderr.strip()}")

    returncode = process.poll()
    if allow_signal_exit and returncode is not None and returncode < 0:
        return f"POSTDETACH_SIGNAL:{-returncode}"
    raise ProbeError("timed out waiting for mapping-writer event")


def send(process: subprocess.Popen[str], command: str) -> None:
    if process.stdin is None:
        raise ProbeError("mapping writer stdin unavailable")
    process.stdin.write(command)
    process.stdin.flush()


def expected_pre_detach_bytes() -> bytes:
    expected = bytearray(INITIAL_BYTES)
    expected[PRE_OFFSET : PRE_OFFSET + len(PRE_BYTES)] = PRE_BYTES
    return bytes(expected)


def collect_hdiutil_inventory(value: object, devices: set[str], mountpoints: set[str]) -> None:
    if isinstance(value, dict):
        device = value.get("dev-entry")
        mountpoint = value.get("mount-point")
        if isinstance(device, str):
            devices.add(device)
        if isinstance(mountpoint, str):
            mountpoints.add(mountpoint)
        for child in value.values():
            collect_hdiutil_inventory(child, devices, mountpoints)
    elif isinstance(value, list):
        for child in value:
            collect_hdiutil_inventory(child, devices, mountpoints)


def observe_attachment(device: str, mountpoint: Path) -> dict[str, object]:
    completed = subprocess.run(
        ["/usr/bin/hdiutil", "info", "-plist"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise ProbeError(
            "hdiutil info -plist failed while classifying detach state: "
            + completed.stderr.decode("utf-8", errors="replace").strip()
        )
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise ProbeError("hdiutil info -plist returned malformed data") from error
    devices: set[str] = set()
    mountpoints: set[str] = set()
    collect_hdiutil_inventory(payload, devices, mountpoints)
    device_present = device in devices
    mount_present = str(mountpoint) in mountpoints
    if device_present and mount_present:
        state = "ATTACHED_MOUNTED"
    elif not device_present and not mount_present:
        state = "DETACHED"
    else:
        state = "AMBIGUOUS"
    return {
        "state": state,
        "devicePresent": device_present,
        "mountPresent": mount_present,
    }


def detach_output(completed: subprocess.CompletedProcess[str]) -> str:
    return ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()


def is_resource_busy(completed: subprocess.CompletedProcess[str]) -> bool:
    return "resource busy" in detach_output(completed).casefold()


def detach_classification(
    completed: subprocess.CompletedProcess[str],
    observation: dict[str, object],
) -> str:
    state = observation.get("state")
    if state == "DETACHED":
        return "DETACHED"
    if state == "ATTACHED_MOUNTED" and is_resource_busy(completed):
        return "BUSY"
    return "AMBIGUOUS"


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
    workspace = Path(tempfile.mkdtemp(prefix="nembra-apfs-mmap-freeze.", dir="/private/tmp"))
    os.chown(workspace, 0, capability_gid)
    os.chmod(workspace, 0o710)
    image = workspace / "origin-freeze.sparseimage"
    mountpoint = workspace / "mount"
    mountpoint.mkdir()

    child_env = {
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
    }
    writer: subprocess.Popen[str] | None = None
    device: str | None = None
    try:
        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, 0, capability_gid)
        os.chmod(mountpoint, 0o770)

        target = mountpoint / "compiler-output.bin"
        target.write_bytes(INITIAL_BYTES)
        os.chown(target, uid, capability_gid)
        os.chmod(target, 0o660)

        writer = subprocess.Popen(
            ["/usr/bin/python3", "-I", "-c", mapped_writer_code(), str(target)],
            cwd="/private/tmp",
            env=child_env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            **structured_credentials(uid, gid, [capability_gid]),
        )
        if read_event(writer) != "READY":
            raise ProbeError("mapping writer did not arm")

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        path_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf PATH_ATTACK >> "$1"', "sh", str(target)],
            cwd="/private/tmp",
            env=child_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(uid, gid, []),
        )
        if path_attack.returncode == 0:
            raise ProbeError("same-UID sibling retained fresh pathname write authority after root lock")

        send(writer, "W")
        if read_event(writer) != "WROTE":
            raise ProbeError("writable shared mapping did not demonstrate post-lock mutation authority")
        expected = expected_pre_detach_bytes()
        if target.read_bytes() != expected:
            raise ProbeError("post-lock shared-mapping bytes were not durably visible before detach")

        first_device = device
        first_detach = helper.hdiutil_detach(first_device)
        first_observation = observe_attachment(first_device, mountpoint)
        first_classification = detach_classification(first_detach, first_observation)
        first_output = detach_output(first_detach)
        if first_classification == "AMBIGUOUS":
            emit_error(
                "detach-classification",
                "first non-forced detach did not reach a mechanically provable BUSY or DETACHED state",
                firstDetachReturnCode=first_detach.returncode,
                firstDetachOutput=first_output,
                firstDetachObservation=first_observation,
            )
            return 72

        post_result = "NOT_ATTEMPTED_BUSY_DETACH"
        post_persisted = False
        if first_classification == "BUSY":
            send(writer, "C")
            if read_event(writer) != "CLOSED":
                raise ProbeError("mapping writer did not close after busy detach")
            writer.wait(timeout=5)
            if writer.returncode != 0:
                raise ProbeError(f"mapping writer exited {writer.returncode} after close")

            second_detach = helper.hdiutil_detach(first_device)
            second_observation = observe_attachment(first_device, mountpoint)
            if detach_classification(second_detach, second_observation) != "DETACHED":
                emit_error(
                    "quiescence",
                    "normal detach did not mechanically remove the image after the mapping closed",
                    secondDetachReturnCode=second_detach.returncode,
                    secondDetachOutput=detach_output(second_detach),
                    secondDetachObservation=second_observation,
                )
                return 73
            device = None
        else:
            device = None
            send(writer, "P")
            post_result = read_event(writer, allow_signal_exit=True)
            if post_result.startswith("POSTDETACH_SIGNAL:"):
                writer.wait(timeout=2)
            else:
                send(writer, "C")
                if read_event(writer) != "CLOSED":
                    raise ProbeError("mapping writer did not close after post-detach probe")
                writer.wait(timeout=5)
            if writer.returncode is None:
                writer.wait(timeout=2)
            if writer.returncode is not None and writer.returncode > 0:
                raise ProbeError(
                    f"mapping writer exited {writer.returncode} after detach without a kernel-signal classification"
                )

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen = target.read_bytes()
        if frozen != expected:
            post_persisted = frozen[POST_OFFSET : POST_OFFSET + len(POST_BYTES)] == POST_BYTES
            emit_error(
                "authority-survived-detach",
                "post-detach mapping activity changed bytes visible in the read-only remount",
                firstDetachClassification=first_classification,
                postDetachResult=post_result,
                postDetachPersisted=post_persisted,
            )
            return 74
        post_persisted = False

        root_readonly_errno: int | None = None
        try:
            with target.open("r+b", buffering=0) as handle:
                handle.seek(POST_OFFSET)
                handle.write(POST_BYTES)
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as error:
            root_readonly_errno = error.errno
        if root_readonly_errno is None or target.read_bytes() != expected:
            raise ProbeError("read-only remount accepted a root write or changed frozen bytes")

        former_capability = subprocess.run(
            ["/bin/sh", "-c", 'printf CAPABILITY_ATTACK >> "$1"', "sh", str(target)],
            cwd="/private/tmp",
            env=child_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(uid, gid, [capability_gid]),
        )
        if former_capability.returncode == 0 or target.read_bytes() != expected:
            raise ProbeError("former capability mutated the read-only remount")

        evidence = {
            "schemaVersion": 1,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "capabilityGID": capability_gid,
            "normalGroupsContainCapability": capability_gid in normal_groups,
            "writerRetainedFileDescriptor": False,
            "writerRetainedSharedWritableMapping": True,
            "writerSupplementaryGroups": [capability_gid],
            "ordinaryAttackSupplementaryGroups": [],
            "freshPathAttackReturnCode": path_attack.returncode,
            "firstDetachReturnCode": first_detach.returncode,
            "firstDetachOutput": first_output,
            "firstDetachObservation": first_observation,
            "firstDetachClassification": first_classification,
            "postDetachResult": post_result,
            "postDetachPersisted": post_persisted,
            "rootReadonlyWriteErrno": root_readonly_errno,
            "formerCapabilityReadonlyReturnCode": former_capability.returncode,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (ProbeError, subprocess.TimeoutExpired, OSError) as error:
        emit_error(
            "probe",
            str(error),
            errorType=type(error).__name__,
            errno=getattr(error, "errno", None),
        )
        return 75
    finally:
        if writer is not None and writer.poll() is None:
            try:
                send(writer, "C")
            except Exception:
                pass
            try:
                writer.terminate()
                writer.wait(timeout=2)
            except Exception:
                try:
                    writer.kill()
                    writer.wait(timeout=2)
                except Exception:
                    pass
        if device is not None:
            helper.hdiutil_detach(device, force=True)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "APFS mmap freeze probe requires macOS")
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
        emit_error("evidence", "missing or ambiguous APFS mmap freeze evidence")
        return 81
    evidence = json.loads(records[0])
    classification = evidence.get("firstDetachClassification")
    post_result = str(evidence.get("postDetachResult", ""))
    detached_result_classified = (
        classification == "DETACHED"
        and (
            post_result == "POSTDETACH_OK"
            or post_result.startswith("POSTDETACH_ERR:")
            or post_result.startswith("POSTDETACH_SIGNAL:")
        )
    )
    safe = (
        evidence.get("normalGroupsContainCapability") is False
        and evidence.get("writerRetainedFileDescriptor") is False
        and evidence.get("writerRetainedSharedWritableMapping") is True
        and evidence.get("writerSupplementaryGroups") == [evidence.get("capabilityGID")]
        and evidence.get("ordinaryAttackSupplementaryGroups") == []
        and evidence.get("freshPathAttackReturnCode") != 0
        and evidence.get("postDetachPersisted") is False
        and isinstance(evidence.get("rootReadonlyWriteErrno"), int)
        and evidence.get("rootReadonlyWriteErrno") != 0
        and evidence.get("formerCapabilityReadonlyReturnCode") != 0
        and evidence.get("physicalAuthorityCreated") is False
        and (classification == "BUSY" or detached_result_classified)
    )
    if not safe:
        emit_error("evidence", f"APFS mmap evidence failed semantic checks: {evidence}")
        return 82
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    args = parser.parse_args()
    return root_probe() if args.root_probe else parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
