#!/usr/bin/env python3
"""Validation-only signing-compatible APFS freeze through the real guard process shape.

The production installer does not invoke xcodebuild directly. A field-owned Python private-input
guard watches admitted Tuya inputs and then launches xcodebuild with ordinary subprocess.Popen.
That default child launch closes non-standard inherited descriptors, so a direct pass_fds proof is
not sufficient production evidence.

This oracle delegates the root-hidden APFS directory descriptor as standard input (fd 0) to an
intermediate field-UID Python guard shim. The shim launches real xcodebuild with ordinary Popen,
without pass_fds or close_fds overrides. Standard fd 0 therefore remains the narrow compiler-output
capability through the same process boundary used by the production private-input guard, while the
field account keeps its legitimate HOME/keychain/signing/private-input identity. DerivedData is
addressed only as /dev/fd/0/DerivedData.

After the guard/Xcode process group returns, root closes its descriptor and requires a normal,
non-forced APFS detach before any compiler-output hash becomes authoritative. A byte-identical
read-only remount must reject root writes and a field-UID write even when the frozen directory is
again explicitly delegated as fd 0.

This creates architecture evidence only. No signing, install, device, Bluetooth, Tuya traffic,
telemetry, or physical scooter authority is created.
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
from typing import Iterable

HERE = Path(__file__).resolve().parent
DIRECT_ORACLE_PATH = HERE / "test_capture_signed_app_real_xcode_dirfd_apfs_freeze.py"
MARKER = "NEMBRA_REAL_XCODE_STDIO_DIRFD_APFS_JSON="
ERROR_MARKER = "NEMBRA_REAL_XCODE_STDIO_DIRFD_APFS_ERROR="


class ProbeError(RuntimeError):
    pass


def load_direct_oracle():
    spec = importlib.util.spec_from_file_location("nembra_dirfd_apfs_direct_oracle", DIRECT_ORACLE_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load directory-FD APFS helper oracle")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str, *, output: str = "", detach_output: str = "") -> None:
    payload = {
        "kind": kind,
        "message": message,
        "buildOutputTail": "\n".join(output.splitlines()[-180:]),
        "detachOutput": detach_output[-6000:],
        "physicalAuthorityCreated": False,
    }
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    normalized = sorted({int(group) for group in groups if int(group) != gid})
    if uid <= 0 or gid <= 0 or any(group <= 0 for group in normalized):
        raise ProbeError("field credential vector contains root or invalid authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def guard_shim_code() -> str:
    # Deliberately ordinary Popen: no pass_fds and no close_fds override. The only delegated
    # compiler-output capability is standard fd 0, matching the real guard's inherited-stdio shape.
    return r'''
import json
import subprocess
import sys
command = json.loads(sys.argv[1])
process = subprocess.Popen(
    command,
    stdin=None,
    stdout=sys.stdout,
    stderr=sys.stderr,
    text=True,
)
raise SystemExit(process.wait())
'''


def field_environment(account: pwd.struct_passwd) -> dict[str, str]:
    environment = {
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
    }
    for variable in ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS"):
        value = os.environ.get(variable)
        if value:
            environment[variable] = value
    return environment


def root_probe(package_root: Path, expected_uid: int, expected_gid: int, active_groups: list[int]) -> int:
    helper = load_direct_oracle()
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "stdio directory-FD APFS root probe requires sudo on real macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if sudo_uid != expected_uid or sudo_gid != expected_gid or sudo_uid <= 0 or sudo_gid <= 0:
        emit_error("identity", "root evidence is not bound to exact pre-sudo field UID/GID")
        return 71
    account = pwd.getpwuid(sudo_uid)
    if account.pw_name != sudo_user or account.pw_gid != sudo_gid:
        emit_error("identity", "sudo identity does not match the local field account")
        return 71
    directory_groups = sorted(set(os.getgrouplist(account.pw_name, sudo_gid)))
    normalized_active = sorted(set(active_groups))
    if len(normalized_active) != len(active_groups) or sudo_gid in normalized_active:
        emit_error("identity", "captured active group vector is duplicated or contains primary GID")
        return 71
    if any(group <= 0 for group in normalized_active) or 0 in directory_groups:
        emit_error("identity", "field group authority contains root or invalid identity")
        return 71
    if not set(normalized_active).issubset(directory_groups):
        emit_error("identity", "active field groups exceed Directory Services membership")
        return 71

    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-stdio-dirfd-apfs.", dir="/private/tmp"))
    image = workspace / "field-output.sparseimage"
    mountpoint = workspace / "mount"
    mountpoint.mkdir()
    os.chown(workspace, 0, 0)
    os.chmod(workspace, 0o700)
    device: str | None = None
    mount_fd: int | None = None
    readonly_fd: int | None = None
    process: subprocess.Popen[str] | None = None
    try:
        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, sudo_uid, sudo_gid)
        os.chmod(mountpoint, 0o700)

        mount_fd = os.open(mountpoint, os.O_RDONLY | os.O_DIRECTORY)
        os.set_inheritable(mount_fd, True)

        no_fd_attack = subprocess.run(
            ["/bin/mkdir", str(mountpoint / "same-uid-sibling")],
            env=field_environment(account),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(sudo_uid, sudo_gid, normalized_active),
            check=False,
        )
        if no_fd_attack.returncode == 0:
            emit_error("field-isolation", "same-UID sibling reached root-hidden writable mount without delegated stdio FD")
            return 72

        xcode_command = [
            "/usr/bin/xcodebuild",
            "-scheme", "OriginDirFDFreezeProof",
            "-configuration", "Debug",
            "-sdk", "macosx",
            "-destination", "generic/platform=macOS",
            "-derivedDataPath", "/dev/fd/0/DerivedData",
            "CODE_SIGNING_ALLOWED=NO",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "build",
        ]
        process = subprocess.Popen(
            [
                "/usr/bin/python3", "-I", "-c", guard_shim_code(),
                json.dumps(xcode_command, separators=(",", ":")),
            ],
            cwd=package_root,
            env=field_environment(account),
            stdin=mount_fd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
            **structured_credentials(sudo_uid, sudo_gid, normalized_active),
        )
        output, _ = process.communicate()
        returncode = process.returncode
        os.close(mount_fd)
        mount_fd = None
        helper.terminate_process_group(process.pid)
        if returncode != 0:
            emit_error(
                "xcodebuild",
                f"real Xcode could not build through stdio directory-FD custody: {returncode}",
                output=output,
            )
            return 73

        product = mountpoint / "DerivedData/Build/Products/Debug/OriginDirFDFreezeProof"
        if not product.is_file() or product.is_symlink():
            emit_error("product", f"real-Xcode product missing behind stdio directory FD: {product}", output=output)
            return 74
        before = helper.sha256(product)

        post_build_no_fd_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "FIELD_PATH_ATTACK\\n" >> "$1"', "sh", str(product)],
            env=field_environment(account),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(sudo_uid, sudo_gid, normalized_active),
            check=False,
        )
        if post_build_no_fd_attack.returncode == 0 or helper.sha256(product) != before:
            emit_error("field-isolation", "same-UID sibling changed compiler output without delegated stdio FD", output=output)
            return 75

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = helper.hdiutil_detach(device)
        detach_text = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "guard/Xcode returned but stdio-delegated output could not reach normal non-forced detach",
                output=output,
                detach_output=detach_text,
            )
            return 76
        device = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen_product = mountpoint / "DerivedData/Build/Products/Debug/OriginDirFDFreezeProof"
        if not frozen_product.is_file() or frozen_product.is_symlink():
            emit_error("readonly-remount", "product missing after read-only APFS remount")
            return 77
        frozen = helper.sha256(frozen_product)
        if frozen != before:
            emit_error("readonly-remount", "read-only remount changed real-Xcode product bytes")
            return 77

        root_errno: int | None = None
        try:
            with frozen_product.open("ab", buffering=0) as handle:
                handle.write(b"ROOT_AFTER_FREEZE\n")
                handle.flush()
                os.fsync(handle.fileno())
        except OSError as error:
            root_errno = error.errno
        if root_errno is None or helper.sha256(frozen_product) != frozen:
            emit_error("readonly-remount", "root mutated product on purported read-only remount")
            return 78

        readonly_fd = os.open(mountpoint, os.O_RDONLY | os.O_DIRECTORY)
        os.set_inheritable(readonly_fd, True)
        readonly_field_attack = subprocess.run(
            [
                "/bin/sh", "-c",
                'printf "FIELD_AFTER_FREEZE\\n" >> "$1"',
                "sh", "/dev/fd/0/DerivedData/Build/Products/Debug/OriginDirFDFreezeProof",
            ],
            env=field_environment(account),
            stdin=readonly_fd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(sudo_uid, sudo_gid, normalized_active),
            check=False,
        )
        os.close(readonly_fd)
        readonly_fd = None
        if readonly_field_attack.returncode == 0 or helper.sha256(frozen_product) != frozen:
            emit_error("readonly-remount", "field identity mutated product through delegated stdio FD after freeze")
            return 78

        evidence = {
            "schemaVersion": 1,
            "fieldUID": sudo_uid,
            "fieldPrimaryGID": sudo_gid,
            "fieldActiveSupplementaryGroups": normalized_active,
            "fieldActiveGroupsSubsetOfDirectoryService": set(normalized_active).issubset(directory_groups),
            "sameUIDNoFDPreBuildReturnCode": no_fd_attack.returncode,
            "guardShimReturnCode": returncode,
            "sameUIDNoFDPostBuildReturnCode": post_build_no_fd_attack.returncode,
            "nonForcedDetachReturnCode": detach.returncode,
            "compilerProductSHA256": before,
            "readonlyRemountSHA256": frozen,
            "rootReadonlyWriteErrno": root_errno,
            "fieldReadonlyStdioFDAttackReturnCode": readonly_field_attack.returncode,
            "derivedDataUsedStandardInputDirectoryFD": True,
            "guardShimUsedOrdinaryPopen": True,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, ProbeError, subprocess.CalledProcessError) as error:
        emit_error("fixture", f"stdio directory-FD APFS fixture failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if mount_fd is not None:
            try:
                os.close(mount_fd)
            except OSError:
                pass
        if readonly_fd is not None:
            try:
                os.close(readonly_fd)
            except OSError:
                pass
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, 9)
            except ProcessLookupError:
                pass
            process.wait()
        if device is not None:
            try:
                helper.hdiutil_detach(device, force=True)
            except Exception:
                pass
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    helper = load_direct_oracle()
    if sys.platform != "darwin":
        emit_error("environment", "stdio directory-FD APFS real-Xcode probe requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "probe requires one stable non-root field identity before sudo")
        return 80
    active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if 0 in active_groups:
        emit_error("identity", "field process carries active root supplementary-group authority")
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

    active_args = [item for group in active_groups for item in ("--field-active-group", str(group))]
    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-stdio-dirfd-source-") as temporary:
        package_root = Path(temporary)
        helper.make_package(package_root)
        completed = subprocess.run(
            [
                "/usr/bin/sudo", "-n", "/usr/bin/python3", "-B", "-I",
                str(Path(__file__).resolve()),
                "--root-probe",
                "--package-root", str(package_root),
                "--field-uid", str(field_uid),
                "--field-primary-gid", str(field_gid),
                "--field-active-group-count", str(len(active_groups)),
                *active_args,
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
            emit_error("evidence", "missing or ambiguous stdio directory-FD APFS evidence")
            return 81
        evidence = json.loads(records[0])
        required = (
            evidence.get("fieldUID") == field_uid
            and evidence.get("fieldPrimaryGID") == field_gid
            and evidence.get("fieldActiveSupplementaryGroups") == active_groups
            and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
            and evidence.get("sameUIDNoFDPreBuildReturnCode") != 0
            and evidence.get("guardShimReturnCode") == 0
            and evidence.get("sameUIDNoFDPostBuildReturnCode") != 0
            and evidence.get("nonForcedDetachReturnCode") == 0
            and evidence.get("compilerProductSHA256") == evidence.get("readonlyRemountSHA256")
            and evidence.get("rootReadonlyWriteErrno") is not None
            and evidence.get("fieldReadonlyStdioFDAttackReturnCode") != 0
            and evidence.get("derivedDataUsedStandardInputDirectoryFD") is True
            and evidence.get("guardShimUsedOrdinaryPopen") is True
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            emit_error("evidence", f"stdio directory-FD APFS evidence failed semantic checks: {evidence}")
            return 82
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-primary-gid", type=int)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.package_root is None or args.field_uid is None or args.field_primary_gid is None:
            emit_error("arguments", "root probe requires package root and exact pre-sudo field identity")
            return 83
        if args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires one counted active supplementary-group vector")
            return 83
        return root_probe(
            args.package_root,
            args.field_uid,
            args.field_primary_gid,
            args.field_active_group,
        )
    if (
        args.package_root is not None
        or args.field_uid is not None
        or args.field_primary_gid is not None
        or args.field_active_group
        or args.field_active_group_count is not None
    ):
        emit_error("arguments", "root-only fixture arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
