#!/usr/bin/env python3
"""Validation-only real-Xcode APFS freeze using a dedicated ephemeral build UID.

#3066 proved the supplementary-capability-GID topology is not a fair real-Xcode
fixture: xcodebuild starts, but Xcode log-store access loses the one-off group and
cannot read its own DerivedData. This successor tests a different authority model.
The field user never receives compiler-output pathname authority. Root creates one
temporary local build identity whose stable UID/primary GID owns the writable APFS
mount. Real Xcode runs as that identity. After build return, root removes pathname
authority and requires a normal, non-forced APFS detach before any compiler-output
fingerprint could become authoritative; inspection then occurs only after read-only
remount.

This is architecture evidence only. It creates no signing, install, device,
Bluetooth, Tuya, telemetry, or physical scooter authority.
"""
from __future__ import annotations

import argparse
import grp
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import textwrap
from typing import Iterable

HERE = Path(__file__).resolve().parent
FREEZE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_REAL_XCODE_DEDICATED_UID_JSON="
ERROR_MARKER = "NEMBRA_REAL_XCODE_DEDICATED_UID_ERROR="


class ProbeError(RuntimeError):
    pass


def load_freeze_helper():
    spec = importlib.util.spec_from_file_location("nembra_unmount_freeze_dedicated_uid", FREEZE_HELPER_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load accepted unmount-freeze validation helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def emit_error(kind: str, message: str, *, build_output: str = "", detach_output: str = "") -> None:
    payload = {
        "kind": kind,
        "message": message,
        "buildOutputTail": "\n".join(build_output.splitlines()[-140:]),
        "detachOutput": detach_output[-6000:],
        "physicalAuthorityCreated": False,
    }
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    return {
        "user": uid,
        "group": gid,
        "extra_groups": sorted(set(groups)),
    }


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
                name: "OriginDedicatedUIDProof",
                platforms: [.macOS(.v14)],
                products: [.executable(name: "OriginDedicatedUIDProof", targets: ["OriginDedicatedUIDProof"])],
                targets: [.executableTarget(name: "OriginDedicatedUIDProof")]
            )
            """
        ),
        encoding="utf-8",
    )
    source = root / "Sources/OriginDedicatedUIDProof"
    source.mkdir(parents=True)
    (source / "main.swift").write_text(
        'print("Nembra real-Xcode dedicated-UID freeze proof")\n',
        encoding="utf-8",
    )


def chown_tree(root: Path, uid: int, gid: int) -> None:
    os.chown(root, uid, gid)
    for directory, directories, files in os.walk(root):
        directory_path = Path(directory)
        os.chown(directory_path, uid, gid)
        for name in directories:
            os.chown(directory_path / name, uid, gid)
        for name in files:
            os.chown(directory_path / name, uid, gid)


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
    raise ProbeError("could not find an unused validation UID/GID")


def create_local_build_identity(name: str, uid: int, gid: int, home: Path) -> None:
    if os.geteuid() != 0:
        raise ProbeError("ephemeral build identity creation requires root")
    if uid <= 0 or gid <= 0 or uid != gid:
        raise ProbeError("ephemeral build identity requires one positive dedicated UID/GID")
    if subprocess.run(["/usr/bin/dscl", ".", "-read", f"/Users/{name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise ProbeError("ephemeral validation username already exists")
    if subprocess.run(["/usr/bin/dscl", ".", "-read", f"/Groups/{name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise ProbeError("ephemeral validation group already exists")

    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(gid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Build Fixture"])

    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(gid)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", str(home)])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"])
    run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Build Fixture"])
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


def root_probe(package_root: Path, field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "dedicated-UID root probe requires sudo on real macOS")
        return 70
    try:
        field_uid = int(os.environ["SUDO_UID"])
        field_gid = int(os.environ["SUDO_GID"])
        field_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if field_uid <= 0 or field_gid <= 0:
        emit_error("identity", "field identity must be non-root")
        return 71
    account = pwd.getpwuid(field_uid)
    if account.pw_name != field_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo identity does not match the local field account")
        return 71
    field_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    if 0 in field_groups:
        emit_error("identity", "field identity carries root supplementary-group authority")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)):
        emit_error("identity", "captured field supplementary-group vector is duplicated")
        return 71
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "captured field supplementary-group vector is invalid")
        return 71
    if field_gid in field_active_groups:
        emit_error("identity", "captured field supplementary-group vector must keep the primary GID separate")
        return 71
    if not set(field_active_groups).issubset(field_groups):
        emit_error("identity", "captured active field groups exceed directory-service membership")
        return 71

    helper = load_freeze_helper()
    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-dedicated-uid.", dir="/private/tmp"))
    image = workspace / "xcode-origin.sparseimage"
    mountpoint = workspace / "mount"
    source_root = workspace / "source"
    home = workspace / "home"
    temp_name = f"nembrabuild{os.getpid()}"
    build_uid: int | None = None
    build_gid: int | None = None
    device: str | None = None
    identity_created = False
    try:
        build_uid = choose_ephemeral_id()
        build_gid = build_uid
        home.mkdir()
        source_root.mkdir()
        mountpoint.mkdir()

        # Root workspace is traversable only by the dedicated build primary GID;
        # the field user's actual active groups never include this freshly selected ID.
        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        create_local_build_identity(temp_name, build_uid, build_gid, home)
        identity_created = True
        if build_uid == field_uid or build_gid in field_groups or build_gid in field_active_groups:
            emit_error("identity", "ephemeral build identity overlaps field authority")
            return 71

        shutil.copytree(package_root, source_root, dirs_exist_ok=True)
        chown_tree(source_root, build_uid, build_gid)
        chown_tree(home, build_uid, build_gid)
        os.chmod(source_root, 0o700)
        os.chmod(home, 0o700)

        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)

        child_environment = {
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
                child_environment[variable] = value

        derived = mountpoint / "DerivedData"
        command = [
            "/usr/bin/xcodebuild",
            "-scheme",
            "OriginDedicatedUIDProof",
            "-configuration",
            "Debug",
            "-sdk",
            "macosx",
            "-destination",
            "generic/platform=macOS",
            "-derivedDataPath",
            str(derived),
            "CODE_SIGNING_ALLOWED=NO",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "build",
        ]
        build = subprocess.run(
            command,
            cwd=source_root,
            env=child_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            **structured_credentials(build_uid, build_gid, []),
            check=False,
        )
        if build.returncode != 0:
            emit_error(
                "xcodebuild",
                f"real Xcode could not build as dedicated UID inside isolated APFS output: {build.returncode}",
                build_output=build.stdout,
            )
            return 72

        product = derived / "Build/Products/Debug/OriginDedicatedUIDProof"
        if not product.is_file() or product.is_symlink():
            emit_error("product", f"dedicated-UID Xcode product missing: {product}", build_output=build.stdout)
            return 73
        before = sha256(product)

        # Replay the exact active kernel identity captured by the invoking field
        # process before sudo. Directory-service memberships are used only as a
        # fail-closed superset check, never inflated into the child credential set.
        field_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "FIELD_ATTACK\\n" >> "$1"', "sh", str(product)],
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
        if field_attack.returncode == 0 or sha256(product) != before:
            emit_error("field-isolation", "field identity changed dedicated-UID compiler output")
            return 74

        # Retire fresh pathname authority before asking the kernel whether every
        # escaped Xcode/build descendant has released the volume.
        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = helper.hdiutil_detach(device)
        detach_text = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "real Xcode returned but dedicated-UID output could not reach non-forced detach",
                build_output=build.stdout,
                detach_output=detach_text,
            )
            return 75
        device = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen_product = mountpoint / "DerivedData/Build/Products/Debug/OriginDedicatedUIDProof"
        if not frozen_product.is_file() or frozen_product.is_symlink():
            emit_error("readonly-remount", "dedicated-UID product missing after read-only remount")
            return 76
        frozen = sha256(frozen_product)
        if frozen != before:
            emit_error("readonly-remount", "read-only remount changed dedicated-UID product bytes")
            return 76

        root_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "ROOT_AFTER_FREEZE\\n" >> "$1"', "sh", str(frozen_product)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if root_attack.returncode == 0 or sha256(frozen_product) != frozen:
            emit_error("readonly-remount", "root mutated dedicated-UID output after read-only freeze")
            return 77

        former_build = subprocess.run(
            ["/bin/sh", "-c", 'printf "BUILD_UID_AFTER_FREEZE\\n" >> "$1"', "sh", str(frozen_product)],
            env=child_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(build_uid, build_gid, []),
            check=False,
        )
        if former_build.returncode == 0 or sha256(frozen_product) != frozen:
            emit_error("readonly-remount", "former build identity mutated output after read-only freeze")
            return 78

        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "fieldActiveGroupsContainBuildGID": build_gid in field_active_groups,
            "fieldActiveGroupsSubsetOfDirectoryService": set(field_active_groups).issubset(field_groups),
            "fieldGroupsContainBuildGID": build_gid in field_groups,
            "buildUID": build_uid,
            "buildPrimaryGID": build_gid,
            "buildIdentityDistinctFromField": build_uid != field_uid,
            "xcodebuildReturnCode": build.returncode,
            "fieldAttackReturnCode": field_attack.returncode,
            "nonForcedDetachReturnCode": detach.returncode,
            "rootReadonlyAttackReturnCode": root_attack.returncode,
            "formerBuildReadonlyAttackReturnCode": former_build.returncode,
            "compilerProductSHA256": before,
            "readonlyRemountSHA256": frozen,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, subprocess.CalledProcessError, ProbeError, KeyError) as error:
        emit_error("fixture", f"dedicated-UID validation fixture failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if device is not None:
            try:
                helper.hdiutil_detach(device, force=True)
            except Exception:
                pass
        if identity_created:
            remove_local_build_identity(temp_name, build_uid)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "dedicated-UID real-Xcode freeze probe requires macOS")
        return 80
    if os.getuid() <= 0 or os.geteuid() != os.getuid() or os.getegid() != os.getgid():
        emit_error("identity", "field probe requires one stable non-root invoking identity before sudo")
        return 80
    field_primary_gid = os.getgid()
    field_active_groups = sorted({group for group in os.getgroups() if group != field_primary_gid})
    if 0 in field_active_groups:
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

    active_group_args = [
        item
        for group in field_active_groups
        for item in ("--field-active-group", str(group))
    ]
    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-dedicated-uid-package-") as temporary:
        package = Path(temporary)
        make_package(package)
        completed = subprocess.run(
            [
                "/usr/bin/sudo",
                "-n",
                "/usr/bin/python3",
                "-B",
                "-I",
                str(Path(__file__).resolve()),
                "--root-probe",
                "--package-root",
                str(package),
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
        records = [line[len(MARKER):] for line in completed.stdout.splitlines() if line.startswith(MARKER)]
        if len(records) != 1:
            emit_error("evidence", "missing or ambiguous dedicated-UID Xcode freeze evidence")
            return 81
        evidence = json.loads(records[0])
        required = (
            evidence.get("xcodebuildReturnCode") == 0
            and evidence.get("fieldAttackReturnCode") != 0
            and evidence.get("fieldGroupsContainBuildGID") is False
            and evidence.get("fieldActiveGroupsContainBuildGID") is False
            and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
            and evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
            and evidence.get("buildIdentityDistinctFromField") is True
            and evidence.get("nonForcedDetachReturnCode") == 0
            and evidence.get("rootReadonlyAttackReturnCode") != 0
            and evidence.get("formerBuildReadonlyAttackReturnCode") != 0
            and evidence.get("compilerProductSHA256") == evidence.get("readonlyRemountSHA256")
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            emit_error("evidence", f"dedicated-UID Xcode freeze evidence failed semantic checks: {evidence}")
            return 82
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.package_root is None:
            emit_error("arguments", "--package-root is required for root probe")
            return 83
        if args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires one explicit captured field supplementary-group vector")
            return 83
        return root_probe(args.package_root, args.field_active_group)
    if args.package_root is not None or args.field_active_group or args.field_active_group_count is not None:
        emit_error("arguments", "root-only fixture arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
