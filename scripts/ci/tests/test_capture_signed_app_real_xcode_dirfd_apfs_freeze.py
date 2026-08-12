#!/usr/bin/env python3
"""Validation-only real-Xcode APFS freeze using an inherited directory-FD capability.

The production problem is narrower than "run Xcode as a different user": the real field
account legitimately owns private Tuya compiler inputs plus signing/provisioning authority,
while unrelated same-UID processes must never gain compiler-output pathname authority.

This probe keeps xcodebuild under the exact pre-sudo field UID/GID/group vector, hides the
writable APFS mount beneath a root-only parent, and passes exactly one already-open directory
FD to the xcodebuild process tree. DerivedData is addressed through /dev/fd/<n>. A same-UID
sibling without that FD must fail to reach the writable mount. After xcodebuild returns, the
root supervisor closes its copy, retires the original process group, and requires a normal
non-forced detach. Only a byte-identical read-only remount may become fingerprint authority.

A green result is architecture evidence only. It creates no signing, install, device,
Bluetooth, Tuya, telemetry, or physical scooter authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
from typing import Iterable

MARKER = "NEMBRA_REAL_XCODE_DIRFD_APFS_JSON="
ERROR_MARKER = "NEMBRA_REAL_XCODE_DIRFD_APFS_ERROR="


class ProbeError(RuntimeError):
    pass


def emit_error(kind: str, message: str, *, build_output: str = "", detach_output: str = "") -> None:
    payload = {
        "kind": kind,
        "message": message,
        "buildOutputTail": "\n".join(build_output.splitlines()[-160:]),
        "detachOutput": detach_output[-6000:],
        "physicalAuthorityCreated": False,
    }
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    normalized = sorted({int(group) for group in groups if int(group) != gid})
    if uid <= 0 or gid <= 0 or any(group <= 0 for group in normalized):
        raise ProbeError("field credential vector contains root or invalid authority")
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


def make_package(root: Path) -> None:
    (root / "Package.swift").write_text(
        textwrap.dedent(
            """\
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "OriginDirFDFreezeProof",
                platforms: [.macOS(.v14)],
                products: [.executable(name: "OriginDirFDFreezeProof", targets: ["OriginDirFDFreezeProof"])],
                targets: [.executableTarget(name: "OriginDirFDFreezeProof")]
            )
            """
        ),
        encoding="utf-8",
    )
    source = root / "Sources/OriginDirFDFreezeProof"
    source.mkdir(parents=True)
    (source / "main.swift").write_text(
        'print("Nembra field-UID directory-FD APFS freeze proof")\n',
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hdiutil_create(image: Path) -> None:
    completed = subprocess.run(
        [
            "/usr/bin/hdiutil", "create", "-quiet", "-size", "256m", "-type", "SPARSE",
            "-fs", "APFS", "-volname", "NembraFieldDirFDFreeze", str(image),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise ProbeError("hdiutil create failed: " + completed.stderr.strip())


def hdiutil_attach(image: Path, mountpoint: Path, *, readonly: bool) -> str:
    command = [
        "/usr/bin/hdiutil", "attach", "-plist", "-nobrowse", "-mountpoint", str(mountpoint),
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
            "hdiutil attach failed: "
            + completed.stderr.decode("utf-8", errors="replace").strip()
        )
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise ProbeError("hdiutil attach returned malformed plist output") from error
    for entity in payload.get("system-entities", []):
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise ProbeError("hdiutil attach returned no device for the requested mountpoint")


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


def terminate_process_group(process_group: int) -> None:
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
    raise ProbeError("xcodebuild left a live process in its original process group")


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
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "directory-FD APFS root probe requires sudo on real macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if sudo_uid != expected_uid or sudo_gid != expected_gid or sudo_uid <= 0 or sudo_gid <= 0:
        emit_error("identity", "root evidence is not bound to the exact pre-sudo field UID/GID")
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

    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-dirfd-apfs.", dir="/private/tmp"))
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
        hdiutil_create(image)
        device = hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, sudo_uid, sudo_gid)
        os.chmod(mountpoint, 0o700)

        # The writable filesystem is hidden behind a root-only parent. Only the already-open
        # directory descriptor below is delegated to the intended Xcode process tree.
        mount_fd = os.open(mountpoint, os.O_RDONLY | os.O_DIRECTORY)
        os.set_inheritable(mount_fd, True)
        fd_root = f"/dev/fd/{mount_fd}"
        derived_via_fd = f"{fd_root}/DerivedData"

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
            emit_error("field-isolation", "same-UID sibling reached the root-hidden writable mount without the delegated FD")
            return 72

        command = [
            "/usr/bin/xcodebuild",
            "-scheme", "OriginDirFDFreezeProof",
            "-configuration", "Debug",
            "-sdk", "macosx",
            "-destination", "generic/platform=macOS",
            "-derivedDataPath", derived_via_fd,
            "CODE_SIGNING_ALLOWED=NO",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "build",
        ]
        process = subprocess.Popen(
            command,
            cwd=package_root,
            env=field_environment(account),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
            pass_fds=(mount_fd,),
            **structured_credentials(sudo_uid, sudo_gid, normalized_active),
        )
        build_output, _ = process.communicate()
        returncode = process.returncode
        if mount_fd is not None:
            os.close(mount_fd)
            mount_fd = None
        terminate_process_group(process.pid)
        if returncode != 0:
            emit_error(
                "xcodebuild",
                f"real Xcode could not build through the inherited directory-FD capability: {returncode}",
                build_output=build_output,
            )
            return 73

        product = mountpoint / "DerivedData/Build/Products/Debug/OriginDirFDFreezeProof"
        if not product.is_file() or product.is_symlink():
            emit_error("product", f"real-Xcode product missing behind delegated directory FD: {product}", build_output=build_output)
            return 74
        before = sha256(product)

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
        if post_build_no_fd_attack.returncode == 0 or sha256(product) != before:
            emit_error("field-isolation", "same-UID sibling changed compiler output without the delegated FD", build_output=build_output)
            return 75

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = hdiutil_detach(device)
        detach_text = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "xcodebuild returned but delegated-FD output could not reach normal non-forced detach",
                build_output=build_output,
                detach_output=detach_text,
            )
            return 76
        device = None

        device = hdiutil_attach(image, mountpoint, readonly=True)
        frozen_product = mountpoint / "DerivedData/Build/Products/Debug/OriginDirFDFreezeProof"
        if not frozen_product.is_file() or frozen_product.is_symlink():
            emit_error("readonly-remount", "product missing after read-only APFS remount")
            return 77
        frozen = sha256(frozen_product)
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
        if root_errno is None or sha256(frozen_product) != frozen:
            emit_error("readonly-remount", "root mutated product on the purported read-only remount")
            return 78

        # Give the field identity an explicit directory FD on the frozen volume. The write must
        # still fail because the kernel filesystem is read-only, not merely because pathname
        # traversal was hidden by the root-only parent.
        readonly_fd = os.open(mountpoint, os.O_RDONLY | os.O_DIRECTORY)
        os.set_inheritable(readonly_fd, True)
        frozen_via_fd = f"/dev/fd/{readonly_fd}/DerivedData/Build/Products/Debug/OriginDirFDFreezeProof"
        readonly_field_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "FIELD_AFTER_FREEZE\\n" >> "$1"', "sh", frozen_via_fd],
            env=field_environment(account),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            pass_fds=(readonly_fd,),
            **structured_credentials(sudo_uid, sudo_gid, normalized_active),
            check=False,
        )
        os.close(readonly_fd)
        readonly_fd = None
        if readonly_field_attack.returncode == 0 or sha256(frozen_product) != frozen:
            emit_error("readonly-remount", "field identity mutated product through an explicitly delegated FD after freeze")
            return 78

        evidence = {
            "schemaVersion": 1,
            "fieldUID": sudo_uid,
            "fieldPrimaryGID": sudo_gid,
            "fieldActiveSupplementaryGroups": normalized_active,
            "fieldActiveGroupsSubsetOfDirectoryService": set(normalized_active).issubset(directory_groups),
            "sameUIDNoFDPreBuildReturnCode": no_fd_attack.returncode,
            "xcodebuildReturnCode": returncode,
            "sameUIDNoFDPostBuildReturnCode": post_build_no_fd_attack.returncode,
            "nonForcedDetachReturnCode": detach.returncode,
            "compilerProductSHA256": before,
            "readonlyRemountSHA256": frozen,
            "rootReadonlyWriteErrno": root_errno,
            "fieldReadonlyFDAttackReturnCode": readonly_field_attack.returncode,
            "derivedDataUsedInheritedDirectoryFD": True,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, ProbeError, subprocess.CalledProcessError) as error:
        emit_error("fixture", f"directory-FD APFS validation fixture failed: {type(error).__name__}: {error}")
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
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        if device is not None:
            try:
                hdiutil_detach(device, force=True)
            except Exception:
                pass
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "directory-FD APFS real-Xcode probe requires macOS")
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
    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-dirfd-source-") as temporary:
        package_root = Path(temporary)
        make_package(package_root)
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
            emit_error("evidence", "missing or ambiguous directory-FD APFS real-Xcode evidence")
            return 81
        evidence = json.loads(records[0])
        required = (
            evidence.get("fieldUID") == field_uid
            and evidence.get("fieldPrimaryGID") == field_gid
            and evidence.get("fieldActiveSupplementaryGroups") == active_groups
            and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
            and evidence.get("sameUIDNoFDPreBuildReturnCode") != 0
            and evidence.get("xcodebuildReturnCode") == 0
            and evidence.get("sameUIDNoFDPostBuildReturnCode") != 0
            and evidence.get("nonForcedDetachReturnCode") == 0
            and evidence.get("compilerProductSHA256") == evidence.get("readonlyRemountSHA256")
            and evidence.get("rootReadonlyWriteErrno") is not None
            and evidence.get("fieldReadonlyFDAttackReturnCode") != 0
            and evidence.get("derivedDataUsedInheritedDirectoryFD") is True
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            emit_error("evidence", f"directory-FD APFS evidence failed semantic checks: {evidence}")
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
