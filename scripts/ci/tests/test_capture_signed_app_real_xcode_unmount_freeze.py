#!/usr/bin/env python3
"""Validate real Xcode compiler output behind an unmount/read-only-remount freeze boundary.

This is a validation-only child of #3004. The generic detached-FD probe asks whether a non-forced
APFS detach rejects an open writer. This probe asks the complementary product question: can actual
Xcode finish a build in that isolated volume and leave it quiescent enough for a non-forced detach,
after which the exact output can be read only from a read-only remount?

No signing identity, device, install, Bluetooth, Tuya traffic, or physical action is used.
"""

from __future__ import annotations

import argparse
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

HERE = Path(__file__).resolve().parent
FREEZE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_REAL_XCODE_UNMOUNT_JSON="
ERROR_MARKER = "NEMBRA_REAL_XCODE_UNMOUNT_ERROR="


class ProbeError(RuntimeError):
    pass


def load_freeze_helper():
    spec = importlib.util.spec_from_file_location("nembra_unmount_freeze", FREEZE_HELPER_PATH)
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
        "buildOutputTail": "\n".join(build_output.splitlines()[-100:]),
        "detachOutput": detach_output[-4000:],
        "physicalAuthorityCreated": False,
    }
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def structured_credentials(uid: int, gid: int, groups: list[int]) -> dict[str, object]:
    return {
        "user": uid,
        "group": gid,
        "extra_groups": sorted(set(groups)),
    }


def make_package(root: Path) -> None:
    (root / "Package.swift").write_text(
        textwrap.dedent(
            """\
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "OriginUnmountProof",
                platforms: [.macOS(.v14)],
                products: [.executable(name: "OriginUnmountProof", targets: ["OriginUnmountProof"])],
                targets: [.executableTarget(name: "OriginUnmountProof")]
            )
            """
        ),
        encoding="utf-8",
    )
    source = root / "Sources/OriginUnmountProof"
    source.mkdir(parents=True)
    (source / "main.swift").write_text(
        'print("Nembra real-Xcode unmount-freeze proof")\n',
        encoding="utf-8",
    )


def root_probe(package_root: Path) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "root probe requires sudo on real macOS")
        return 70
    helper = load_freeze_helper()
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
    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-unmount.", dir="/private/tmp"))
    image = workspace / "xcode-origin.sparseimage"
    mountpoint = workspace / "mount"
    mountpoint.mkdir()
    # The invoking user needs to traverse only the package tree, never this root-owned workspace.
    # The fresh capability GID is the sole non-root path into the mounted compiler-output volume.
    os.chown(workspace, 0, capability_gid)
    os.chmod(workspace, 0o710)
    device: str | None = None
    try:
        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, 0, capability_gid)
        os.chmod(mountpoint, 0o770)

        # Only the fresh one-run capability is required as a supplementary
        # group. Replaying unrelated hosted-runner groups can exceed macOS
        # setgroups limits before Xcode starts and is not part of this oracle.
        child_groups = [capability_gid]
        ordinary_groups: list[int] = []
        child_environment = {
            "HOME": account.pw_dir,
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": "/tmp",
            "LANG": "C",
            "LC_ALL": "C",
        }
        for name in ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS", "__CF_USER_TEXT_ENCODING"):
            value = os.environ.get(name)
            if value:
                child_environment[name] = value

        derived = mountpoint / "DerivedData"
        command = [
            "/usr/bin/xcodebuild",
            "-scheme",
            "OriginUnmountProof",
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
            cwd=package_root,
            env=child_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            **structured_credentials(uid, gid, child_groups),
            check=False,
        )
        if build.returncode != 0:
            emit_error(
                "xcodebuild",
                f"real Xcode could not build inside the isolated APFS output volume: {build.returncode}",
                build_output=build.stdout,
            )
            return 72

        product = derived / "Build/Products/Debug/OriginUnmountProof"
        if not product.is_file() or product.is_symlink():
            emit_error(
                "product",
                f"real Xcode product missing from isolated APFS volume: {product}",
                build_output=build.stdout,
            )
            return 73
        before = sha256(product)

        sibling = subprocess.run(
            ["/bin/sh", "-c", 'printf "PATH_ATTACK\\n" >> "$1"', "sh", str(product)],
            env=child_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(uid, gid, ordinary_groups),
            check=False,
        )
        if sibling.returncode == 0 or sha256(product) != before:
            emit_error("same-uid-isolation", "ordinary same-UID sibling changed the real Xcode product")
            return 74

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = helper.hdiutil_detach(device)
        detach_text = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "real Xcode returned but the output filesystem could not reach a non-forced detach boundary",
                build_output=build.stdout,
                detach_output=detach_text,
            )
            return 75
        device = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen_product = mountpoint / "DerivedData/Build/Products/Debug/OriginUnmountProof"
        if not frozen_product.is_file() or frozen_product.is_symlink():
            emit_error("readonly-remount", "real Xcode product missing after read-only remount")
            return 76
        frozen = sha256(frozen_product)
        if frozen != before:
            emit_error("readonly-remount", "read-only remount changed the real Xcode product bytes")
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
            emit_error("readonly-remount", "root mutated real Xcode output after read-only freeze")
            return 77

        former_capability = subprocess.run(
            ["/bin/sh", "-c", 'printf "AFTER_FREEZE\\n" >> "$1"', "sh", str(frozen_product)],
            env=child_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            **structured_credentials(uid, gid, child_groups),
            check=False,
        )
        if former_capability.returncode == 0 or sha256(frozen_product) != frozen:
            emit_error("readonly-remount", "former build capability mutated real Xcode output after freeze")
            return 78

        evidence = {
            "schemaVersion": 1,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "capabilityGID": capability_gid,
            "normalGroupsContainCapability": capability_gid in normal_groups,
            "xcodebuildReturnCode": build.returncode,
            "sameUIDAttackReturnCode": sibling.returncode,
            "nonForcedDetachReturnCode": detach.returncode,
            "rootReadonlyAttackReturnCode": root_attack.returncode,
            "readonlyAttackReturnCode": former_capability.returncode,
            "compilerProductSHA256": before,
            "readonlyRemountSHA256": frozen,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    finally:
        if device is not None:
            helper.hdiutil_detach(device, force=True)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "real-Xcode unmount-freeze probe requires macOS")
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

    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-unmount-package-") as temporary:
        package = Path(temporary)
        make_package(package)
        completed = subprocess.run(
            [
                "/usr/bin/sudo",
                "-n",
                "/usr/bin/python3",
                "-I",
                str(Path(__file__).resolve()),
                "--root-probe",
                "--package-root",
                str(package),
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
            emit_error("evidence", "missing or ambiguous real-Xcode unmount-freeze evidence")
            return 81
        evidence = json.loads(records[0])
        required = (
            evidence.get("xcodebuildReturnCode") == 0
            and evidence.get("sameUIDAttackReturnCode") != 0
            and evidence.get("normalGroupsContainCapability") is False
            and evidence.get("nonForcedDetachReturnCode") == 0
            and evidence.get("rootReadonlyAttackReturnCode") != 0
            and evidence.get("readonlyAttackReturnCode") != 0
            and evidence.get("compilerProductSHA256") == evidence.get("readonlyRemountSHA256")
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            emit_error("evidence", f"real-Xcode unmount-freeze evidence failed semantic checks: {evidence}")
            return 82
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    args = parser.parse_args()
    if args.root_probe:
        if args.package_root is None:
            emit_error("arguments", "--package-root is required for root probe")
            return 83
        return root_probe(args.package_root)
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
