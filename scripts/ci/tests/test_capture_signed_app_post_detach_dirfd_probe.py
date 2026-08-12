#!/usr/bin/env python3
"""Probe retained directory-FD authority using the accepted dedicated build identity topology.

Validation-only successor to #3130. #3130 showed that replaying the field user's
real supplementary groups plus a synthetic capability can exceed macOS/Python's
structured credential-launch ceiling before the writer reaches READY. This probe
keeps the same APFS detach oracle, but arms the retained directory FD as one fresh
dedicated build UID/primary GID with zero supplementary groups, matching the
accepted real-Xcode architecture from #3131. The exact pre-sudo field identity is
still replayed independently as a negative control.

No signing, install, device, Bluetooth, Tuya, telemetry, or physical action occurs.
"""

from __future__ import annotations

import argparse
import grp
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
from typing import Iterable

HERE = Path(__file__).resolve().parent
FREEZE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_POST_DETACH_DIRFD_JSON="
ERROR_MARKER = "NEMBRA_POST_DETACH_DIRFD_ERROR="


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


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise ProbeError("structured credentials require one non-root uid/gid")
    normalized = sorted({int(group) for group in groups if int(group) != gid})
    if any(group <= 0 for group in normalized):
        raise ProbeError("structured supplementary groups contain root or invalid authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def run_checked(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


def id_in_use(candidate: int) -> bool:
    try:
        pwd.getpwuid(candidate)
        return True
    except KeyError:
        pass
    try:
        grp.getgrgid(candidate)
        return True
    except KeyError:
        return False


def choose_ephemeral_id() -> int:
    start = 52000 + (os.getpid() % 7000)
    for candidate in range(start, 62000):
        if candidate > 0 and not id_in_use(candidate):
            return candidate
    for candidate in range(52000, start):
        if not id_in_use(candidate):
            return candidate
    raise ProbeError("could not find an unused validation UID/GID")


def create_local_build_identity(name: str, uid: int, gid: int, home: Path) -> None:
    if os.geteuid() != 0:
        raise ProbeError("ephemeral build identity creation requires root")
    if uid <= 0 or gid <= 0 or uid != gid:
        raise ProbeError("ephemeral build identity requires one positive dedicated UID/GID")
    if subprocess.run(
        ["/usr/bin/dscl", ".", "-read", f"/Users/{name}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0:
        raise ProbeError("ephemeral validation username already exists")
    if subprocess.run(
        ["/usr/bin/dscl", ".", "-read", f"/Groups/{name}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0:
        raise ProbeError("ephemeral validation group already exists")

    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(gid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra DirFD Build Fixture"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(gid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", str(home)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra DirFD Build Fixture"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"])
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)

    account = pwd.getpwnam(name)
    group = grp.getgrnam(name)
    if account.pw_uid != uid or account.pw_gid != gid or group.gr_gid != gid:
        raise ProbeError("directory services did not materialize the exact ephemeral build identity")


def remove_local_build_identity(name: str, uid: int | None) -> None:
    if uid is not None and uid > 0:
        subprocess.run(
            ["/usr/bin/pkill", "-9", "-u", str(uid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)


def retained_dirfd_code() -> str:
    return r'''
import os
from pathlib import Path
import sys

bundle = Path(sys.argv[1])
bundle.mkdir(parents=True, exist_ok=True)
(bundle / "accepted.bin").write_bytes(b"ORIGINAL_BUILD_OUTPUT\n")
dirfd = os.open(bundle, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0))
print("READY", flush=True)
try:
    if sys.stdin.buffer.read(1) != b"W":
        raise SystemExit(91)
    fd = os.open("late-entry.bin", os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600, dir_fd=dirfd)
    try:
        os.write(fd, b"DIRFD_POST_LOCK_WRITE\n")
        os.fsync(fd)
    finally:
        os.close(fd)
    print("WROTE", flush=True)
    command = sys.stdin.buffer.read(1)
    if command == b"P":
        try:
            fd = os.open("post-detach-entry.bin", os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600, dir_fd=dirfd)
            try:
                os.write(fd, b"DIRFD_POST_DETACH_WRITE\n")
                os.fsync(fd)
            finally:
                os.close(fd)
            print("POSTDETACH_OK", flush=True)
        except OSError as error:
            print(f"POSTDETACH_ERR:{error.errno}:{error.strerror}", flush=True)
        command = sys.stdin.buffer.read(1)
    if command != b"C":
        raise SystemExit(92)
finally:
    os.close(dirfd)
print("CLOSED", flush=True)
'''


def read_line(process: subprocess.Popen[str]) -> str:
    if process.stdout is None:
        raise ProbeError("writer stdout unavailable")
    line = process.stdout.readline()
    if line:
        return line.strip()
    stderr = process.stderr.read() if process.stderr is not None else ""
    raise ProbeError(f"writer exited {process.poll()}: {stderr.strip()}")


def send(process: subprocess.Popen[str], command: str) -> None:
    if process.stdin is None:
        raise ProbeError("writer stdin unavailable")
    process.stdin.write(command)
    process.stdin.flush()


def detach_is_resource_busy(completed: subprocess.CompletedProcess[str]) -> bool:
    if completed.returncode == 0:
        return False
    diagnostic = ((completed.stdout or "") + "\n" + (completed.stderr or "")).casefold()
    return "resource busy" in diagnostic


def root_probe(field_uid_claim: int, field_gid_claim: int, field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "root probe requires sudo on real macOS")
        return 70

    helper = load_helper()
    try:
        field_uid = int(os.environ["SUDO_UID"])
        field_gid = int(os.environ["SUDO_GID"])
        field_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", str(error))
        return 71

    if field_uid != field_uid_claim or field_gid != field_gid_claim:
        emit_error("identity", "sudo identity differs from exact pre-sudo invoking uid/gid")
        return 71
    account = pwd.getpwuid(field_uid)
    if field_uid <= 0 or field_gid <= 0 or account.pw_name != field_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo identity mismatch")
        return 71

    field_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    if any(group <= 0 for group in field_groups):
        emit_error("identity", "field directory-service groups contain root or invalid authority")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)) or any(group <= 0 for group in field_active_groups):
        emit_error("identity", "captured active supplementary-group vector is invalid")
        return 71
    if field_gid in field_active_groups:
        emit_error("identity", "captured active supplementary groups must keep the primary gid separate")
        return 71
    if not set(field_active_groups).issubset(set(field_groups)):
        emit_error("identity", "captured active supplementary groups exceed directory-service membership")
        return 71

    workspace = Path(tempfile.mkdtemp(prefix="nembra-post-detach-dirfd-dedicated.", dir="/private/tmp"))
    image = workspace / "origin.sparseimage"
    mountpoint = workspace / "mount"
    home = workspace / "home"
    temp_name = f"nembradirfd{os.getpid()}"
    build_uid: int | None = None
    build_gid: int | None = None
    device: str | None = None
    writer: subprocess.Popen[str] | None = None
    identity_attempted = False

    try:
        build_uid = choose_ephemeral_id()
        build_gid = build_uid
        if build_uid == field_uid or build_gid in field_groups or build_gid in field_active_groups:
            emit_error("identity", "ephemeral build identity overlaps field authority")
            return 71

        mountpoint.mkdir()
        home.mkdir()
        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        identity_attempted = True
        create_local_build_identity(temp_name, build_uid, build_gid, home)
        os.chown(home, build_uid, build_gid)
        os.chmod(home, 0o700)

        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)

        bundle = mountpoint / "DerivedData/Build/Products/Debug-iphoneos/Nembra Capture.app"
        build_env = {
            "HOME": str(home),
            "USER": temp_name,
            "LOGNAME": temp_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": str(home),
            "LANG": "C",
            "LC_ALL": "C",
        }
        writer = subprocess.Popen(
            ["/usr/bin/python3", "-I", "-c", retained_dirfd_code(), str(bundle)],
            env=build_env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            **structured_credentials(build_uid, build_gid, []),
        )
        if read_line(writer) != "READY":
            raise ProbeError("writer did not arm")

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)

        field_env = {
            "HOME": account.pw_dir,
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": "/tmp",
            "LANG": "C",
            "LC_ALL": "C",
        }
        try:
            fresh = subprocess.run(
                ["/bin/sh", "-c", 'printf x > "$1"', "sh", str(bundle / "fresh-path-entry.bin")],
                env=field_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                **structured_credentials(field_uid, field_gid, field_active_groups),
                check=False,
            )
        except (OSError, subprocess.SubprocessError, ProbeError, ValueError) as error:
            emit_error(
                "credential-launch",
                f"field negative-control launch failed: {type(error).__name__}: {error}",
            )
            return 72
        if fresh.returncode == 0:
            emit_error("pathname-isolation", "fresh field path write survived lock")
            return 73

        send(writer, "W")
        if read_line(writer) != "WROTE":
            raise ProbeError("post-lock dedicated-build dirfd write not demonstrated")

        first_detach = helper.hdiutil_detach(device)
        detach_text = ((first_detach.stdout or "") + "\n" + (first_detach.stderr or "")).strip()
        detach_was_busy = detach_is_resource_busy(first_detach)
        if first_detach.returncode != 0 and not detach_was_busy:
            emit_error(
                "detach-classification",
                "first non-forced detach failed for a non-busy reason",
                firstDetachReturnCode=first_detach.returncode,
                firstDetachOutput=detach_text,
            )
            return 74

        post_result = "NOT_ATTEMPTED_BUSY_DETACH"
        if detach_was_busy:
            send(writer, "C")
            if read_line(writer) != "CLOSED":
                raise ProbeError("writer did not close")
            writer.wait(timeout=5)
            closed_detach = helper.hdiutil_detach(device)
            if closed_detach.returncode != 0:
                emit_error("quiescence", "detach remained busy after dedicated-build dirfd close")
                return 75
            device = None
        else:
            device = None
            send(writer, "P")
            post_result = read_line(writer)
            send(writer, "C")
            if read_line(writer) != "CLOSED":
                raise ProbeError("writer did not close after post-detach probe")
            writer.wait(timeout=5)

        if writer.returncode != 0:
            emit_error("writer", f"writer exited {writer.returncode}")
            return 76

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen = mountpoint / "DerivedData/Build/Products/Debug-iphoneos/Nembra Capture.app"
        if (frozen / "late-entry.bin").read_bytes() != b"DIRFD_POST_LOCK_WRITE\n":
            emit_error("readonly-remount", "pre-detach bytes changed")
            return 77

        post_path = frozen / "post-detach-entry.bin"
        persisted = post_path.exists()
        if post_result == "POSTDETACH_OK" or persisted:
            emit_error(
                "authority-survived-detach",
                "retained dedicated-build dirfd preserved mutation authority after detach",
                firstDetachOutput=detach_text,
                postDetachResult=post_result,
                postDetachPersisted=persisted,
            )
            return 78
        if not detach_was_busy and not post_result.startswith("POSTDETACH_ERR:"):
            emit_error("post-detach-probe", "ambiguous result", result=post_result)
            return 79

        root_create = subprocess.run(
            ["/bin/sh", "-c", 'printf x > "$1"', "sh", str(frozen / "root-after-freeze.bin")],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        try:
            former_build = subprocess.run(
                ["/bin/sh", "-c", 'printf x > "$1"', "sh", str(frozen / "build-after-freeze.bin")],
                env=build_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                **structured_credentials(build_uid, build_gid, []),
                check=False,
            )
        except (OSError, subprocess.SubprocessError, ProbeError, ValueError) as error:
            emit_error(
                "credential-launch",
                f"former-build negative-control launch failed: {type(error).__name__}: {error}",
            )
            return 72
        if root_create.returncode == 0 or former_build.returncode == 0:
            emit_error("readonly-remount", "read-only remount admitted a new entry")
            return 80

        evidence = {
            "schemaVersion": 3,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "fieldActiveGroupsSubsetOfDirectoryService": set(field_active_groups).issubset(set(field_groups)),
            "fieldGroupsContainBuildGID": build_gid in field_groups,
            "fieldActiveGroupsContainBuildGID": build_gid in field_active_groups,
            "buildUID": build_uid,
            "buildPrimaryGID": build_gid,
            "buildSupplementaryGroups": [],
            "buildIdentityDistinctFromField": build_uid != field_uid,
            "freshPathAttackReturnCode": fresh.returncode,
            "firstDetachReturnCode": first_detach.returncode,
            "firstDetachOutput": detach_text,
            "detachWasBusy": detach_was_busy,
            "postDetachResult": post_result,
            "postDetachPersisted": persisted,
            "rootReadonlyCreateReturnCode": root_create.returncode,
            "formerBuildReadonlyCreateReturnCode": former_build.returncode,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0

    except (ProbeError, subprocess.TimeoutExpired, subprocess.CalledProcessError, OSError, subprocess.SubprocessError, ValueError) as error:
        emit_error("probe", f"{type(error).__name__}: {error}")
        return 81
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
                    writer.wait()
                except Exception:
                    pass
        if device is not None:
            try:
                helper.hdiutil_detach(device, force=True)
            except Exception:
                pass
        if identity_attempted:
            remove_local_build_identity(temp_name, build_uid)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "requires macOS")
        return 82

    field_uid, field_euid = os.getuid(), os.geteuid()
    field_gid, field_egid = os.getgid(), os.getegid()
    if field_uid <= 0 or field_gid <= 0 or field_uid != field_euid or field_gid != field_egid:
        emit_error("identity", "field parent requires one stable non-root invoking uid/gid")
        return 82

    field_active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "field parent carries root or invalid active supplementary authority")
        return 82

    active_group_args = [
        item
        for group in field_active_groups
        for item in ("--field-active-group", str(group))
    ]
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
            "--field-uid",
            str(field_uid),
            "--field-primary-gid",
            str(field_gid),
            "--field-active-group-count",
            str(len(field_active_groups)),
            *active_group_args,
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
        emit_error("evidence", "missing/ambiguous evidence")
        return 83
    evidence = json.loads(records[0])
    busy_evidence = (
        evidence.get("detachWasBusy") is True
        and "resource busy" in str(evidence.get("firstDetachOutput", "")).casefold()
    )
    safe = (
        evidence.get("schemaVersion") == 3
        and evidence.get("fieldUID") == field_uid
        and evidence.get("fieldPrimaryGID") == field_gid
        and evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
        and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
        and evidence.get("fieldGroupsContainBuildGID") is False
        and evidence.get("fieldActiveGroupsContainBuildGID") is False
        and evidence.get("buildIdentityDistinctFromField") is True
        and evidence.get("buildUID") == evidence.get("buildPrimaryGID")
        and isinstance(evidence.get("buildUID"), int)
        and evidence.get("buildUID", 0) > 0
        and evidence.get("buildSupplementaryGroups") == []
        and evidence.get("freshPathAttackReturnCode") != 0
        and evidence.get("postDetachPersisted") is False
        and evidence.get("rootReadonlyCreateReturnCode") != 0
        and evidence.get("formerBuildReadonlyCreateReturnCode") != 0
        and evidence.get("physicalAuthorityCreated") is False
        and (
            busy_evidence
            or (
                evidence.get("detachWasBusy") is False
                and str(evidence.get("postDetachResult", "")).startswith("POSTDETACH_ERR:")
            )
        )
    )
    if not safe:
        emit_error("evidence", f"semantic checks failed: {evidence}")
        return 84
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-primary-gid", type=int)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()

    if args.root_probe:
        if (
            args.field_uid is None
            or args.field_primary_gid is None
            or args.field_active_group_count is None
            or args.field_active_group_count != len(args.field_active_group)
        ):
            emit_error(
                "arguments",
                "root probe requires exact pre-sudo uid/gid and one counted active supplementary-group vector",
            )
            return 85
        return root_probe(args.field_uid, args.field_primary_gid, args.field_active_group)

    if (
        args.field_uid is not None
        or args.field_primary_gid is not None
        or args.field_active_group
        or args.field_active_group_count is not None
    ):
        emit_error("arguments", "root-only identity arguments are unavailable in field parent mode")
        return 85
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
