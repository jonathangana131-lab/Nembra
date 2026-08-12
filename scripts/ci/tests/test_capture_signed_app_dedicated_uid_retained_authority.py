#!/usr/bin/env python3
"""Validate retained compiler-output authority under the accepted dedicated-build-UID APFS model.

This validation-only witness supersedes older supplementary-capability fixtures that
could not arm on the hosted macOS runner. It reuses the accepted dedicated build
identity machinery from the real-Xcode freeze oracle, then isolates two retained
authority classes after fresh pathname authority is revoked:

* a nested directory descriptor that can create entries relative to an already-open
  directory even after the mount root is locked; and
* a shared writable mmap whose original file descriptor has already been closed.

For either class, a normal non-forced APFS detach is accepted only when the exact
image is mechanically absent, or when the exact image remains mounted and hdiutil
reports Resource busy. If detach succeeds while retained authority is live, any
post-detach mutation attempt must not persist into the later read-only remount.

No signing identity, install, device, Bluetooth, Tuya, telemetry, command, scooter,
or physical authority is created.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import mmap  # source-contract marker; writer imports mmap in its isolated process
import os
from pathlib import Path
import plistlib
import pwd
import select
import shutil
import subprocess
import sys
import tempfile
from typing import Iterable

HERE = Path(__file__).resolve().parent
DEDICATED_HELPER_PATH = HERE / "test_capture_signed_app_real_xcode_dedicated_uid_freeze.py"
MARKER = "NEMBRA_DEDICATED_UID_RETAINED_AUTHORITY_JSON="
ERROR_MARKER = "NEMBRA_DEDICATED_UID_RETAINED_AUTHORITY_ERROR="
FILE_SIZE = 4096
PRE_BYTES = b"PREDETACH_MAP_OK"
POST_BYTES = b"POSTDETACH_MAPOK"
INITIAL_BYTES = b"A" * FILE_SIZE
DIRFD_PRE_BYTES = b"DIRFD_PREDETACH_OK\n"
DIRFD_POST_BYTES = b"DIRFD_POSTDETACH_OK\n"


class ProbeError(RuntimeError):
    pass


def load_dedicated_helper():
    spec = importlib.util.spec_from_file_location("nembra_dedicated_uid_retained_authority", DEDICATED_HELPER_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load accepted dedicated-UID freeze helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str, *, authority: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "kind": kind,
        "authorityClass": authority,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    return {
        "user": uid,
        "group": gid,
        "extra_groups": sorted(set(groups)),
    }


def resolve_direct_writer_python() -> str:
    """Return the already-selected real interpreter, never the /usr/bin xcrun shim."""
    try:
        resolved = Path(sys.executable).resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise ProbeError(f"could not resolve selected Python executable: {error}") from error
    if not resolved.is_absolute() or not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise ProbeError(f"selected Python executable is not an absolute executable file: {resolved}")
    try:
        if os.path.samefile(resolved, "/usr/bin/python3"):
            raise ProbeError("selected Python executable resolved back to the /usr/bin xcrun shim")
    except OSError as error:
        raise ProbeError(f"could not compare selected Python executable with /usr/bin/python3: {error}") from error
    return str(resolved)


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
print("READY", flush=True)

command = sys.stdin.read(1)
if command != "W":
    raise SystemExit(91)
mapping[0:16] = b"PREDETACH_MAP_OK"
mapping.flush()
print("WROTE", flush=True)

command = sys.stdin.read(1)
if command == "P":
    try:
        mapping[64:80] = b"POSTDETACH_MAPOK"
        mapping.flush()
        print("POSTDETACH_OK", flush=True)
    except BaseException as error:
        print(f"POSTDETACH_ERR:{type(error).__name__}:{error}", flush=True)
    command = sys.stdin.read(1)

if command != "C":
    raise SystemExit(92)
mapping.close()
print("CLOSED", flush=True)
'''


def dirfd_writer_code() -> str:
    return r'''
import os
import sys

bundle = sys.argv[1]
fd = os.open(bundle, os.O_RDONLY | os.O_DIRECTORY)
print("READY", flush=True)

command = sys.stdin.read(1)
if command != "W":
    raise SystemExit(91)
entry = os.open("late-entry.bin", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
try:
    os.write(entry, b"DIRFD_PREDETACH_OK\n")
    os.fsync(entry)
finally:
    os.close(entry)
print("WROTE", flush=True)

command = sys.stdin.read(1)
if command == "P":
    try:
        post = os.open("post-detach.bin", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
        try:
            os.write(post, b"DIRFD_POSTDETACH_OK\n")
            os.fsync(post)
        finally:
            os.close(post)
        print("POSTDETACH_OK", flush=True)
    except BaseException as error:
        print(f"POSTDETACH_ERR:{type(error).__name__}:{error}", flush=True)
    command = sys.stdin.read(1)

if command != "C":
    raise SystemExit(92)
os.close(fd)
print("CLOSED", flush=True)
'''


def read_event(
    process: subprocess.Popen[str],
    *,
    timeout: float = 8.0,
    allow_signal_exit: bool = False,
) -> str:
    if process.stdout is None:
        raise ProbeError("retained-authority writer stdout unavailable")
    readable, _, _ = select.select([process.stdout], [], [], timeout)
    if readable:
        line = process.stdout.readline()
        if line:
            return line.strip()
        try:
            returncode = process.wait(timeout=2)
        except subprocess.TimeoutExpired as error:
            raise ProbeError("writer closed stdout but remained live") from error
        if allow_signal_exit and returncode < 0:
            return f"POSTDETACH_SIGNAL:{-returncode}"
        stderr = process.stderr.read() if process.stderr is not None else ""
        raise ProbeError(f"writer exited {returncode} without an event: {stderr.strip()}")
    returncode = process.poll()
    if allow_signal_exit and returncode is not None and returncode < 0:
        return f"POSTDETACH_SIGNAL:{-returncode}"
    raise ProbeError("timed out waiting for retained-authority writer event")


def send(process: subprocess.Popen[str], command: str) -> None:
    if process.stdin is None:
        raise ProbeError("retained-authority writer stdin unavailable")
    process.stdin.write(command)
    process.stdin.flush()


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


def classify_detach(
    completed: subprocess.CompletedProcess[str],
    observation: dict[str, object],
) -> str:
    state = observation.get("state")
    if state == "DETACHED":
        return "DETACHED"
    if state == "ATTACHED_MOUNTED" and "resource busy" in detach_output(completed).casefold():
        return "BUSY"
    return "AMBIGUOUS"


def expected_mmap_bytes() -> bytes:
    expected = bytearray(INITIAL_BYTES)
    expected[0 : len(PRE_BYTES)] = PRE_BYTES
    return bytes(expected)


def field_environment(account: pwd.struct_passwd) -> dict[str, str]:
    return {
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
    }


def build_environment(account_name: str, home: Path) -> dict[str, str]:
    return {
        "HOME": str(home),
        "USER": account_name,
        "LOGNAME": account_name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": str(home),
        "LANG": "C",
        "LC_ALL": "C",
    }


def validate_field_identity(field_uid: int, field_gid: int, active_groups: list[int]) -> tuple[pwd.struct_passwd, list[int]]:
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        raise ProbeError(f"missing sudo invoking identity: {error}") from error
    if field_uid <= 0 or field_gid <= 0 or field_uid != sudo_uid or field_gid != sudo_gid:
        raise ProbeError("root probe field UID/GID do not equal the exact pre-sudo identity")
    account = pwd.getpwuid(field_uid)
    if account.pw_name != sudo_user or account.pw_gid != field_gid:
        raise ProbeError("sudo identity does not match local account database")
    full_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    if 0 in full_groups or 0 in active_groups:
        raise ProbeError("field identity carries root-group authority")
    if len(active_groups) != len(set(active_groups)) or field_gid in active_groups:
        raise ProbeError("captured active field group vector is malformed")
    if any(group <= 0 for group in active_groups):
        raise ProbeError("captured active field group vector contains an invalid GID")
    if not set(active_groups).issubset(full_groups):
        raise ProbeError("captured active field groups exceed Directory Services membership")
    return account, full_groups


def root_probe(authority: str, field_uid: int, field_gid: int, active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "root probe requires sudo on real macOS", authority=authority)
        return 70
    if authority not in {"dirfd", "mmap"}:
        emit_error("arguments", "unknown retained-authority class", authority=authority)
        return 70

    writer: subprocess.Popen[str] | None = None
    device: str | None = None
    build_uid: int | None = None
    identity_created = False
    workspace: Path | None = None
    dedicated = load_dedicated_helper()
    helper = dedicated.load_freeze_helper()
    temp_name = f"nembraretain{os.getpid()}"
    try:
        account, full_groups = validate_field_identity(field_uid, field_gid, active_groups)
        writer_python = resolve_direct_writer_python()
        build_uid = dedicated.choose_ephemeral_id()
        build_gid = build_uid
        if build_uid == field_uid or build_gid in full_groups or build_gid in active_groups:
            raise ProbeError("fresh build identity overlaps field authority")

        workspace = Path(tempfile.mkdtemp(prefix=f"nembra-{authority}-dedicated-uid.", dir="/private/tmp"))
        mountpoint = workspace / "mount"
        home = workspace / "home"
        image = workspace / "origin-freeze.sparseimage"
        mountpoint.mkdir()
        home.mkdir()

        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        dedicated.create_local_build_identity(temp_name, build_uid, build_gid, home)
        identity_created = True
        dedicated.chown_tree(home, build_uid, build_gid)
        os.chmod(home, 0o700)

        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)

        target = mountpoint / "compiler-output.bin"
        bundle = mountpoint / "Nembra Capture.app"
        if authority == "mmap":
            target.write_bytes(INITIAL_BYTES)
            os.chown(target, build_uid, build_gid)
            os.chmod(target, 0o600)
            writer_argv = [writer_python, "-I", "-c", mapped_writer_code(), str(target)]
            path_attack_argv = ["/bin/sh", "-c", 'printf "FIELD_ATTACK" >> "$1"', "sh", str(target)]
        else:
            bundle.mkdir()
            os.chown(bundle, build_uid, build_gid)
            os.chmod(bundle, 0o700)
            writer_argv = [writer_python, "-I", "-c", dirfd_writer_code(), str(bundle)]
            path_attack_argv = ["/bin/sh", "-c", 'printf FIELD > "$1/field-attack.bin"', "sh", str(bundle)]

        writer = subprocess.Popen(
            writer_argv,
            cwd="/private/tmp",
            env=build_environment(temp_name, home),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            **structured_credentials(build_uid, build_gid, []),
        )
        if read_event(writer) != "READY":
            raise ProbeError("dedicated-build-UID writer did not arm")

        # Revoke every fresh path from the former build identity. The writer keeps
        # only its already-open dirfd or shared mapping across this transition.
        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)

        field_attack = subprocess.run(
            path_attack_argv,
            cwd="/private/tmp",
            env=field_environment(account),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(field_uid, field_gid, active_groups),
        )
        if field_attack.returncode == 0:
            raise ProbeError("real field identity retained fresh compiler-output pathname authority")

        former_build_path_attack = subprocess.run(
            path_attack_argv,
            cwd="/private/tmp",
            env=build_environment(temp_name, home),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(build_uid, build_gid, []),
        )
        if former_build_path_attack.returncode == 0:
            raise ProbeError("former build identity retained fresh compiler-output pathname authority")

        send(writer, "W")
        if read_event(writer) != "WROTE":
            raise ProbeError("retained authority did not demonstrate post-lock mutation")
        if authority == "mmap":
            if target.read_bytes() != expected_mmap_bytes():
                raise ProbeError("shared mapping mutation was not durably visible before detach")
        else:
            late_entry = bundle / "late-entry.bin"
            if not late_entry.is_file() or late_entry.read_bytes() != DIRFD_PRE_BYTES:
                raise ProbeError("directory-FD mutation was not durably visible before detach")

        first_device = device
        first_detach = helper.hdiutil_detach(first_device)
        first_observation = observe_attachment(first_device, mountpoint)
        detach_class = classify_detach(first_detach, first_observation)
        if detach_class == "AMBIGUOUS":
            raise ProbeError(
                "non-forced detach produced an ambiguous retained-authority state: "
                + detach_output(first_detach)
            )

        post_detach_event = "NOT_ATTEMPTED_BUSY"
        if detach_class == "BUSY":
            send(writer, "C")
            if read_event(writer) != "CLOSED":
                raise ProbeError("writer did not close after Resource busy")
            writer.wait(timeout=5)
            if writer.returncode != 0:
                stderr = writer.stderr.read() if writer.stderr is not None else ""
                raise ProbeError(f"writer exited {writer.returncode} after close: {stderr.strip()}")
            writer = None
            second_detach = helper.hdiutil_detach(first_device)
            second_observation = observe_attachment(first_device, mountpoint)
            if second_detach.returncode != 0 or second_observation.get("state") != "DETACHED":
                raise ProbeError(
                    "normal detach did not mechanically remove image after retained authority closed: "
                    + detach_output(second_detach)
                )
            device = None
        else:
            device = None
            send(writer, "P")
            post_detach_event = read_event(writer, allow_signal_exit=True)
            if post_detach_event.startswith("POSTDETACH_SIGNAL:"):
                writer = None
            else:
                send(writer, "C")
                close_event = read_event(writer, allow_signal_exit=True)
                if close_event not in {"CLOSED"} and not close_event.startswith("POSTDETACH_SIGNAL:"):
                    raise ProbeError(f"unexpected writer close event after detach: {close_event}")
                if close_event.startswith("POSTDETACH_SIGNAL:"):
                    writer = None
                else:
                    writer.wait(timeout=5)
                    if writer.returncode != 0:
                        stderr = writer.stderr.read() if writer.stderr is not None else ""
                        raise ProbeError(f"writer exited {writer.returncode} after detached close: {stderr.strip()}")
                    writer = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        if authority == "mmap":
            frozen_target = mountpoint / "compiler-output.bin"
            if frozen_target.read_bytes() != expected_mmap_bytes():
                raise ProbeError("read-only remount contains bytes outside the accepted pre-detach mmap prefix")
            frozen_path = frozen_target
            root_attack_argv = ["/bin/sh", "-c", 'printf ROOT_AFTER_FREEZE >> "$1"', "sh", str(frozen_target)]
            former_attack_argv = ["/bin/sh", "-c", 'printf BUILD_AFTER_FREEZE >> "$1"', "sh", str(frozen_target)]
        else:
            frozen_bundle = mountpoint / "Nembra Capture.app"
            frozen_entry = frozen_bundle / "late-entry.bin"
            post_entry = frozen_bundle / "post-detach.bin"
            if not frozen_entry.is_file() or frozen_entry.read_bytes() != DIRFD_PRE_BYTES:
                raise ProbeError("read-only remount lost the accepted pre-detach directory-FD entry")
            if post_entry.exists():
                raise ProbeError("post-detach directory-FD mutation persisted into read-only remount")
            frozen_path = frozen_entry
            root_attack_argv = ["/bin/sh", "-c", 'printf ROOT > "$1/root-after-freeze.bin"', "sh", str(frozen_bundle)]
            former_attack_argv = ["/bin/sh", "-c", 'printf BUILD > "$1/build-after-freeze.bin"', "sh", str(frozen_bundle)]

        before_readonly = frozen_path.read_bytes()
        root_attack = subprocess.run(
            root_attack_argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if root_attack.returncode == 0 or frozen_path.read_bytes() != before_readonly:
            raise ProbeError("root mutated retained-authority output after read-only freeze")

        former_build_readonly = subprocess.run(
            former_attack_argv,
            cwd="/private/tmp",
            env=build_environment(temp_name, home),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(build_uid, build_gid, []),
        )
        if former_build_readonly.returncode == 0 or frozen_path.read_bytes() != before_readonly:
            raise ProbeError("former build identity mutated retained-authority output after read-only freeze")

        evidence = {
            "schemaVersion": 1,
            "authorityClass": authority,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": active_groups,
            "fieldActiveGroupsSubsetOfDirectoryService": set(active_groups).issubset(full_groups),
            "buildUID": build_uid,
            "buildPrimaryGID": build_gid,
            "buildIdentityDistinctFromField": build_uid != field_uid,
            "fieldGroupsContainBuildGID": build_gid in full_groups,
            "fieldActiveGroupsContainBuildGID": build_gid in active_groups,
            "writerPythonExecutable": writer_python,
            "fieldPathAttackReturnCode": field_attack.returncode,
            "formerBuildPathAttackReturnCode": former_build_path_attack.returncode,
            "retainedAuthorityArmed": True,
            "nonForcedDetachReturnCode": first_detach.returncode,
            "detachClassification": detach_class,
            "postDetachWriterEvent": post_detach_event,
            "postDetachMutationPersisted": False,
            "rootReadonlyAttackReturnCode": root_attack.returncode,
            "formerBuildReadonlyAttackReturnCode": former_build_readonly.returncode,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, subprocess.SubprocessError, subprocess.TimeoutExpired, ProbeError, KeyError) as error:
        emit_error(
            "probe",
            f"dedicated-UID retained-authority validation failed: {type(error).__name__}: {error}",
            authority=authority,
        )
        return 79
    finally:
        if writer is not None:
            try:
                if writer.poll() is None:
                    writer.kill()
                writer.wait(timeout=2)
            except Exception:
                pass
        if device is not None:
            try:
                helper.hdiutil_detach(device, force=True)
            except Exception:
                pass
        if identity_created:
            try:
                dedicated.remove_local_build_identity(temp_name, build_uid)
            except Exception:
                pass
        if workspace is not None:
            shutil.rmtree(workspace, ignore_errors=True)


def parent_probe(authority: str) -> int:
    if sys.platform != "darwin":
        emit_error("environment", "retained-authority probe requires macOS", authority=authority)
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent requires one stable non-root invoking identity", authority=authority)
        return 80
    active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if 0 in active_groups:
        emit_error("identity", "field process carries active root-group authority", authority=authority)
        return 80
    sudo = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sudo.returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo", authority=authority)
        return 80

    group_args = [item for group in active_groups for item in ("--field-active-group", str(group))]
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
            "--authority",
            authority,
            "--field-uid",
            str(field_uid),
            "--field-gid",
            str(field_gid),
            "--field-active-group-count",
            str(len(active_groups)),
            *group_args,
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
    records = [line[len(MARKER):] for line in completed.stdout.splitlines() if line.startswith(MARKER)]
    if len(records) != 1:
        emit_error("evidence", "missing or ambiguous retained-authority evidence", authority=authority)
        return 81
    evidence = json.loads(records[0])
    writer_python = evidence.get("writerPythonExecutable")
    required = (
        evidence.get("schemaVersion") == 1
        and evidence.get("authorityClass") == authority
        and evidence.get("fieldUID") == field_uid
        and evidence.get("fieldPrimaryGID") == field_gid
        and evidence.get("fieldActiveSupplementaryGroups") == active_groups
        and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
        and evidence.get("buildIdentityDistinctFromField") is True
        and evidence.get("fieldGroupsContainBuildGID") is False
        and evidence.get("fieldActiveGroupsContainBuildGID") is False
        and isinstance(writer_python, str)
        and Path(writer_python).is_absolute()
        and writer_python != "/usr/bin/python3"
        and evidence.get("fieldPathAttackReturnCode") != 0
        and evidence.get("formerBuildPathAttackReturnCode") != 0
        and evidence.get("retainedAuthorityArmed") is True
        and evidence.get("detachClassification") in {"BUSY", "DETACHED"}
        and evidence.get("postDetachMutationPersisted") is False
        and evidence.get("rootReadonlyAttackReturnCode") != 0
        and evidence.get("formerBuildReadonlyAttackReturnCode") != 0
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        emit_error(
            "evidence",
            f"retained-authority evidence failed semantic checks: {evidence}",
            authority=authority,
        )
        return 82
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--authority", choices=("dirfd", "mmap"), required=True)
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-gid", type=int)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.field_uid is None or args.field_gid is None:
            emit_error("arguments", "root probe requires exact pre-sudo UID/GID", authority=args.authority)
            return 83
        if args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires one exact active field group vector", authority=args.authority)
            return 83
        return root_probe(args.authority, args.field_uid, args.field_gid, args.field_active_group)
    if (
        args.field_uid is not None
        or args.field_gid is not None
        or args.field_active_group
        or args.field_active_group_count is not None
    ):
        emit_error("arguments", "root-only identity arguments are unavailable in parent mode", authority=args.authority)
        return 83
    return parent_probe(args.authority)


if __name__ == "__main__":
    raise SystemExit(main())