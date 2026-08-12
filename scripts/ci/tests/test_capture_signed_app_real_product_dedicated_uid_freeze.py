#!/usr/bin/env python3
"""Validation-only: build the real public Capture product under dedicated-UID APFS custody.

This closes one narrow feasibility question between accepted dedicated-UID/APFS architecture
validation and the production signed-iOS field installer. The normal runner identity never receives
compiler-output pathname authority. Root creates a temporary local build identity, copies the public
accepted checkout into a build-owned fixture, runs the real standalone Nembra Capture Xcode project
with signing disabled and DerivedData on a writable APFS image, retires pathname authority, requires
normal non-forced detach, and fingerprints the product only after read-only remount.

This deliberately does not exercise Apple Development identity, automatic provisioning, private Tuya
inputs, device install/launch, Bluetooth, scooter discovery, telemetry, commands, or physical action.
A green result proves only that the real public Capture product can traverse the dedicated-UID/APFS
freeze boundary. It narrows but does not close production signed-app custody.
"""
from __future__ import annotations

import argparse
import grp
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Iterable

MARKER = "NEMBRA_REAL_PRODUCT_DEDICATED_UID_JSON="
ERROR_MARKER = "NEMBRA_REAL_PRODUCT_DEDICATED_UID_ERROR="
INSTALL_CUSTODY_RELATIVE = Path("scripts/ci/capture_signed_app_install_custody.py")
APP_RELATIVE = Path("DerivedData/Build/Products/Debug-iphoneos/Nembra Capture.app")


class ProbeError(RuntimeError):
    pass


def emit_error(kind: str, message: str, *, build_output: str = "", detach_output: str = "") -> None:
    payload = {
        "kind": kind,
        "message": message,
        "buildOutputTail": "\n".join(build_output.splitlines()[-160:]),
        "detachOutput": detach_output[-6000:],
        "physicalAuthorityCreated": False,
        "signedIdentityAuthorityCreated": False,
    }
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    return {"user": uid, "group": gid, "extra_groups": sorted(set(groups))}


def run_checked(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


def _id_in_use(candidate: int) -> bool:
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
        if candidate > 0 and not _id_in_use(candidate):
            return candidate
    for candidate in range(52000, start):
        if not _id_in_use(candidate):
            return candidate
    raise ProbeError("could not find an unused dedicated validation UID/GID")


def create_local_build_identity(name: str, uid: int, gid: int, home: Path) -> None:
    if os.geteuid() != 0:
        raise ProbeError("dedicated build identity creation requires root")
    if uid <= 0 or gid <= 0 or uid != gid:
        raise ProbeError("dedicated build identity requires one positive UID/GID pair")
    if subprocess.run(["/usr/bin/dscl", ".", "-read", f"/Users/{name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise ProbeError("dedicated validation username already exists")
    if subprocess.run(["/usr/bin/dscl", ".", "-read", f"/Groups/{name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise ProbeError("dedicated validation group already exists")

    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(gid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Product Build Fixture"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(gid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", str(home)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Product Build Fixture"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"])
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)

    account = pwd.getpwnam(name)
    group = grp.getgrnam(name)
    if account.pw_uid != uid or account.pw_gid != gid or group.gr_gid != gid:
        raise ProbeError("directory services did not materialize the exact dedicated build identity")


def remove_local_build_identity(name: str, uid: int | None) -> None:
    if uid is not None and uid > 0:
        subprocess.run(["/usr/bin/pkill", "-9", "-u", str(uid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)


def chown_tree(root: Path, uid: int, gid: int) -> None:
    os.chown(root, uid, gid, follow_symlinks=False)
    for directory, directories, files in os.walk(root, topdown=True, followlinks=False):
        current = Path(directory)
        os.chown(current, uid, gid, follow_symlinks=False)
        for name in directories:
            os.chown(current / name, uid, gid, follow_symlinks=False)
        for name in files:
            os.chown(current / name, uid, gid, follow_symlinks=False)


def hdiutil_create(image: Path) -> None:
    completed = subprocess.run(
        ["/usr/bin/hdiutil", "create", "-quiet", "-size", "4g", "-type", "SPARSE", "-fs", "APFS", "-volname", "NembraProductFreeze", str(image)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise ProbeError("hdiutil create failed: " + completed.stderr.strip())


def hdiutil_attach(image: Path, mountpoint: Path, *, readonly: bool) -> str:
    command = ["/usr/bin/hdiutil", "attach", "-plist", "-nobrowse", "-mountpoint", str(mountpoint)]
    if readonly:
        command.append("-readonly")
    command.append(str(image))
    completed = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.returncode != 0:
        raise ProbeError("hdiutil attach failed: " + completed.stderr.decode("utf-8", errors="replace").strip())
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise ProbeError("hdiutil attach returned malformed plist output") from error
    for entity in payload.get("system-entities", []):
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise ProbeError("hdiutil attach returned no mounted device for the requested mountpoint")


def hdiutil_detach(device: str, *, force: bool = False) -> subprocess.CompletedProcess[str]:
    command = ["/usr/bin/hdiutil", "detach"]
    if force:
        command.append("-force")
    command.append(device)
    return subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)


def load_fingerprint(source_root: Path):
    helper_path = source_root / INSTALL_CUSTODY_RELATIVE
    spec = importlib.util.spec_from_file_location("nembra_install_custody_product_probe", helper_path)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load exact install-custody fingerprint helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    fingerprint = getattr(module, "fingerprint", None)
    if not callable(fingerprint):
        raise ProbeError("install-custody helper exposes no fingerprint function")
    return fingerprint


def require_regular_info_plist(app: Path) -> Path:
    info = app / "Info.plist"
    metadata = info.lstat()
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise ProbeError("built Capture Info.plist is not one real regular file")
    return info


def copy_public_source(source_root: Path, destination: Path) -> None:
    if destination.exists():
        raise ProbeError("dedicated source fixture unexpectedly already exists")
    ignore = shutil.ignore_patterns(".git", ".build", "DerivedData", "xcuserdata")
    shutil.copytree(source_root, destination, symlinks=True, ignore=ignore)
    if not (destination / "NembraCapture.xcodeproj").is_dir():
        raise ProbeError("copied source fixture is missing NembraCapture.xcodeproj")
    if not (destination / INSTALL_CUSTODY_RELATIVE).is_file():
        raise ProbeError("copied source fixture is missing install-custody fingerprint helper")


def root_probe(source_root: Path, field_uid_arg: int, field_gid_arg: int, field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "real-product dedicated-UID probe requires sudo on macOS")
        return 70
    try:
        field_uid = int(os.environ["SUDO_UID"])
        field_gid = int(os.environ["SUDO_GID"])
        field_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if field_uid != field_uid_arg or field_gid != field_gid_arg:
        emit_error("identity", "root evidence identity does not equal the exact pre-sudo UID/GID")
        return 71
    if field_uid <= 0 or field_gid <= 0:
        emit_error("identity", "field identity must be non-root")
        return 71
    account = pwd.getpwuid(field_uid)
    if account.pw_name != field_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo identity does not match the local field account")
        return 71
    field_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    if 0 in field_groups or 0 in field_active_groups:
        emit_error("identity", "field identity carries root group authority")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)) or any(group <= 0 for group in field_active_groups):
        emit_error("identity", "captured field supplementary-group vector is invalid")
        return 71
    if field_gid in field_active_groups or not set(field_active_groups).issubset(field_groups):
        emit_error("identity", "captured active field groups do not match a bounded real field authority")
        return 71

    source_root = source_root.resolve(strict=True)
    fingerprint = load_fingerprint(source_root)
    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-product-dedicated-uid.", dir="/private/tmp"))
    image = workspace / "product-origin.sparseimage"
    mountpoint = workspace / "mount"
    source_copy = workspace / "source"
    home = workspace / "home"
    temp_name = f"nembraproduct{os.getpid()}"
    build_uid: int | None = None
    build_gid: int | None = None
    device: str | None = None
    identity_created = False
    build_output = ""
    try:
        build_uid = choose_ephemeral_id()
        build_gid = build_uid
        if build_uid == field_uid or build_gid in field_groups or build_gid in field_active_groups:
            raise ProbeError("fresh build identity overlaps field authority")

        home.mkdir()
        mountpoint.mkdir()
        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        create_local_build_identity(temp_name, build_uid, build_gid, home)
        identity_created = True

        copy_public_source(source_root, source_copy)
        chown_tree(source_copy, build_uid, build_gid)
        chown_tree(home, build_uid, build_gid)
        os.chmod(source_copy, 0o700)
        os.chmod(home, 0o700)

        hdiutil_create(image)
        device = hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)

        environment = {
            "HOME": str(home),
            "USER": temp_name,
            "LOGNAME": temp_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": str(home),
            "LANG": "C",
            "LC_ALL": "C",
        }
        for variable in ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS"):
            value = os.environ.get(variable)
            if value:
                environment[variable] = value

        derived = mountpoint / "DerivedData"
        command = [
            "/usr/bin/xcodebuild",
            "-project", "NembraCapture.xcodeproj",
            "-scheme", "Nembra Capture",
            "-configuration", "Debug",
            "-sdk", "iphoneos",
            "-destination", "generic/platform=iOS",
            "-derivedDataPath", str(derived),
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "build",
        ]
        build = subprocess.run(
            command,
            cwd=source_copy,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            **structured_credentials(build_uid, build_gid, []),
            check=False,
        )
        build_output = build.stdout
        if build.returncode != 0:
            emit_error("xcodebuild", f"real public Nembra Capture build returned {build.returncode} under dedicated UID", build_output=build_output)
            return 72

        product = mountpoint / APP_RELATIVE
        if not product.is_dir() or product.is_symlink():
            emit_error("product", f"real Nembra Capture product is missing: {product}", build_output=build_output)
            return 73
        info = require_regular_info_plist(product)

        field_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "FIELD_ATTACK\\n" >> "$1"', "sh", str(info)],
            env={
                "HOME": account.pw_dir,
                "USER": account.pw_name,
                "LOGNAME": account.pw_name,
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": "/tmp",
                "LANG": "C",
                "LC_ALL": "C",
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(field_uid, field_gid, field_active_groups),
            check=False,
        )
        if field_attack.returncode == 0:
            emit_error("field-isolation", "field identity retained pathname write authority to compiler output", build_output=build_output)
            return 74

        # No compiler-output fingerprint is authoritative before this kernel quiescence boundary.
        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = hdiutil_detach(device)
        detach_text = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "real Nembra Capture build returned but compiler output could not reach normal non-forced detach",
                build_output=build_output,
                detach_output=detach_text,
            )
            return 75
        device = None

        device = hdiutil_attach(image, mountpoint, readonly=True)
        frozen_product = mountpoint / APP_RELATIVE
        if not frozen_product.is_dir() or frozen_product.is_symlink():
            emit_error("readonly-remount", "real Capture product is missing after read-only remount")
            return 76
        frozen_info = require_regular_info_plist(frozen_product)
        frozen_tree = str(fingerprint(frozen_product))
        if re.fullmatch(r"[0-9a-f]{64}", frozen_tree) is None:
            emit_error("readonly-remount", "read-only product tree fingerprint is malformed")
            return 76

        root_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "ROOT_AFTER_FREEZE\\n" >> "$1"', "sh", str(frozen_info)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if root_attack.returncode == 0 or str(fingerprint(frozen_product)) != frozen_tree:
            emit_error("readonly-remount", "root mutated the product after read-only freeze")
            return 77

        former_build = subprocess.run(
            ["/bin/sh", "-c", 'printf "BUILD_UID_AFTER_FREEZE\\n" >> "$1"', "sh", str(frozen_info)],
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(build_uid, build_gid, []),
            check=False,
        )
        if former_build.returncode == 0 or str(fingerprint(frozen_product)) != frozen_tree:
            emit_error("readonly-remount", "former build identity mutated the product after read-only freeze")
            return 78

        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "fieldGroupsContainBuildGID": build_gid in field_groups,
            "fieldActiveGroupsContainBuildGID": build_gid in field_active_groups,
            "buildUID": build_uid,
            "buildPrimaryGID": build_gid,
            "buildIdentityDistinctFromField": build_uid != field_uid,
            "xcodebuildReturnCode": build.returncode,
            "fieldAttackReturnCode": field_attack.returncode,
            "nonForcedDetachReturnCode": detach.returncode,
            "rootReadonlyAttackReturnCode": root_attack.returncode,
            "formerBuildReadonlyAttackReturnCode": former_build.returncode,
            "productTreeSHA256": frozen_tree,
            "physicalAuthorityCreated": False,
            "signedIdentityAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, subprocess.CalledProcessError, ProbeError, KeyError) as error:
        emit_error("fixture", f"real-product dedicated-UID fixture failed: {type(error).__name__}: {error}", build_output=build_output)
        return 79
    finally:
        if device is not None:
            try:
                hdiutil_detach(device, force=True)
            except Exception:
                pass
        if identity_created:
            remove_local_build_identity(temp_name, build_uid)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "real-product dedicated-UID probe requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent probe requires one stable non-root invoking identity")
        return 80
    active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if 0 in active_groups:
        emit_error("identity", "parent field process carries active root supplementary-group authority")
        return 80
    sudo = subprocess.run(["/usr/bin/sudo", "-n", "/usr/bin/true"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if sudo.returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 80

    source_root = Path.cwd().resolve(strict=True)
    group_args = [item for group in active_groups for item in ("--field-active-group", str(group))]
    completed = subprocess.run(
        [
            "/usr/bin/sudo", "-n", "/usr/bin/python3", "-B", "-I", str(Path(__file__).resolve()),
            "--root-probe",
            "--source-root", str(source_root),
            "--field-uid", str(field_uid),
            "--field-gid", str(field_gid),
            "--field-active-group-count", str(len(active_groups)),
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
        emit_error("evidence", "missing or ambiguous real-product dedicated-UID evidence")
        return 81
    evidence = json.loads(records[0])
    required = (
        evidence.get("fieldUID") == field_uid
        and evidence.get("fieldPrimaryGID") == field_gid
        and evidence.get("fieldActiveSupplementaryGroups") == active_groups
        and evidence.get("fieldGroupsContainBuildGID") is False
        and evidence.get("fieldActiveGroupsContainBuildGID") is False
        and evidence.get("buildIdentityDistinctFromField") is True
        and evidence.get("xcodebuildReturnCode") == 0
        and isinstance(evidence.get("fieldAttackReturnCode"), int)
        and evidence.get("fieldAttackReturnCode") != 0
        and evidence.get("nonForcedDetachReturnCode") == 0
        and isinstance(evidence.get("rootReadonlyAttackReturnCode"), int)
        and evidence.get("rootReadonlyAttackReturnCode") != 0
        and isinstance(evidence.get("formerBuildReadonlyAttackReturnCode"), int)
        and evidence.get("formerBuildReadonlyAttackReturnCode") != 0
        and re.fullmatch(r"[0-9a-f]{64}", str(evidence.get("productTreeSHA256", ""))) is not None
        and evidence.get("physicalAuthorityCreated") is False
        and evidence.get("signedIdentityAuthorityCreated") is False
    )
    if not required:
        emit_error("evidence", f"real-product dedicated-UID evidence failed semantic checks: {evidence}")
        return 82
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-gid", type=int)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.source_root is None or args.field_uid is None or args.field_gid is None:
            emit_error("arguments", "root probe requires exact source and pre-sudo UID/GID arguments")
            return 83
        if args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires one counted field supplementary-group vector")
            return 83
        return root_probe(args.source_root, args.field_uid, args.field_gid, args.field_active_group)
    if any(value is not None for value in (args.source_root, args.field_uid, args.field_gid, args.field_active_group_count)) or args.field_active_group:
        emit_error("arguments", "root-only fixture arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
