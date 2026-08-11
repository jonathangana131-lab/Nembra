#!/usr/bin/env python3
"""Real-Xcode acceptance probe for the signed-app compiler-output custody primitive.

#2955 proves that a digest first minted after xcodebuild returns from a same-UID-writable
DerivedData tree cannot establish compiler-output origin. The production repair uses a root-owned
DerivedData root whose only non-root traversal/write capability is a fresh supplementary GID carried
by the guarded build process. This probe asks real Xcode whether that capability survives far enough
through its build-service machinery to produce a product while a same-UID sibling remains excluded.

Validation only: no signing identity, device, Bluetooth, Tuya, install, launch, or physical action.
"""
from __future__ import annotations

import argparse
import grp
import hashlib
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap

MARKER = "NEMBRA_REAL_XCODE_ORIGIN_JSON="
ERROR_MARKER = "NEMBRA_REAL_XCODE_ORIGIN_ERROR="


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
    raise RuntimeError("could not allocate isolated numeric capability gid")


def structured_credentials(uid: int, gid: int, extra_groups: list[int]) -> dict[str, object]:
    """Use the same minimum-authority POSIX launch shape as the production supervisor."""

    if uid <= 0 or gid <= 0:
        raise RuntimeError("structured child credentials require non-root user and group identity")
    normalized = sorted({group for group in extra_groups if group != gid})
    if any(group <= 0 for group in normalized):
        raise RuntimeError("structured child supplementary groups contain invalid authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def emit_error(kind: str, message: str, *, build_output: str = "") -> None:
    payload = {
        "kind": kind,
        "message": message,
        "buildOutputTail": "\n".join(build_output.splitlines()[-80:]),
        "physicalAuthorityCreated": False,
    }
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def make_package(root: Path) -> None:
    (root / "Package.swift").write_text(
        textwrap.dedent(
            """\
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "OriginProof",
                platforms: [.macOS(.v14)],
                products: [.executable(name: "OriginProof", targets: ["OriginProof"])],
                targets: [.executableTarget(name: "OriginProof")]
            )
            """
        ),
        encoding="utf-8",
    )
    source = root / "Sources/OriginProof"
    source.mkdir(parents=True)
    (source / "main.swift").write_text(
        'print("Nembra real-Xcode compiler-origin custody proof")\n',
        encoding="utf-8",
    )


def root_probe(package_root: Path, normal_groups: list[int], caller_environment: dict[str, str]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "root probe requires sudo on real macOS")
        return 70

    try:
        uid = int(os.environ["SUDO_UID"])
        gid = int(os.environ["SUDO_GID"])
        user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if uid <= 0 or gid <= 0:
        emit_error("identity", "root user/group is not a valid field-build identity")
        return 71
    account = pwd.getpwuid(uid)
    if account.pw_name != user or account.pw_gid != gid:
        emit_error("identity", "sudo identity does not match local account database")
        return 71

    normal_groups = sorted(set(normal_groups) | {gid})
    if any(group <= 0 for group in normal_groups):
        emit_error("identity", "field-build account carries root or invalid group authority")
        return 71
    capability_gid = choose_capability_gid(normal_groups)
    build_root = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-origin.", dir="/private/tmp"))
    stage_root = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-stage.", dir="/private/tmp"))
    try:
        os.chown(build_root, 0, capability_gid)
        os.chmod(build_root, 0o770)
        os.chown(stage_root, 0, 0)
        os.chmod(stage_root, 0o700)

        child_environment = {
            "HOME": account.pw_dir,
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": "/tmp",
            "LANG": caller_environment.get("LANG", "C"),
            "LC_ALL": caller_environment.get("LC_ALL", "C"),
        }
        for name in ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS", "__CF_USER_TEXT_ENCODING"):
            value = caller_environment.get(name)
            if value:
                child_environment[name] = value

        command = [
            "/usr/bin/xcodebuild",
            "-scheme",
            "OriginProof",
            "-configuration",
            "Debug",
            "-sdk",
            "macosx",
            "-destination",
            "generic/platform=macOS",
            "-derivedDataPath",
            str(build_root),
            "CODE_SIGNING_ALLOWED=NO",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "build",
        ]
        # The primary gid is supplied separately. The capability is deliberately the only
        # supplementary group admitted into the authority-bearing Xcode process.
        build = subprocess.run(
            command,
            cwd=package_root,
            env=child_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            **structured_credentials(uid, gid, [capability_gid]),
        )
        if build.returncode != 0:
            emit_error(
                "xcodebuild",
                f"real xcodebuild returned {build.returncode} inside group-isolated DerivedData",
                build_output=build.stdout,
            )
            return 72

        product = build_root / "Build/Products/Debug/OriginProof"
        if not product.is_file() or product.is_symlink():
            emit_error(
                "product",
                f"expected real xcodebuild product is missing: {product}",
                build_output=build.stdout,
            )
            return 73
        before = sha256_file(product)

        attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "\\nATTACKER\\n" >> "$1"', "sh", str(product)],
            env=child_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(uid, gid, []),
        )
        after = sha256_file(product)
        if attack.returncode == 0 or after != before:
            emit_error(
                "same-uid-isolation",
                "same-UID sibling without the capability changed the real xcodebuild product",
                build_output=(attack.stdout + "\n" + attack.stderr),
            )
            return 74

        # Model the production revocation order: remove the capability from filesystem authority
        # before reading/snapshotting product bytes.
        os.chown(build_root, 0, 0)
        os.chmod(build_root, 0o700)
        staged = stage_root / "OriginProof"
        shutil.copy2(product, staged, follow_symlinks=False)
        os.chown(staged, 0, 0)
        os.chmod(staged, stat.S_IMODE(staged.stat().st_mode) & ~0o022)
        staged_hash = sha256_file(staged)
        if staged_hash != before:
            emit_error("stage", "root snapshot differs from real xcodebuild product")
            return 75

        evidence = {
            "schemaVersion": 1,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "fieldNormalGroups": normal_groups,
            "capabilityGID": capability_gid,
            "normalGroupsContainCapability": capability_gid in normal_groups,
            "buildSupplementaryGroups": [capability_gid],
            "attackSupplementaryGroups": [],
            "buildRootOwnerUIDAfterRevocation": build_root.stat().st_uid,
            "buildRootGroupAfterRevocation": build_root.stat().st_gid,
            "buildRootModeAfterRevocation": oct(stat.S_IMODE(build_root.stat().st_mode)),
            "xcodebuildReturnCode": build.returncode,
            "sameUIDAttackReturnCode": attack.returncode,
            "compilerProductSHA256": before,
            "protectedStageSHA256": staged_hash,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    finally:
        shutil.rmtree(build_root, ignore_errors=True)
        shutil.rmtree(stage_root, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "real-Xcode custody proof requires macOS")
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

    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-package-") as temporary:
        package = Path(temporary)
        make_package(package)
        groups = ",".join(str(group) for group in os.getgroups())
        forwarded_environment = {
            key: os.environ[key]
            for key in ("LANG", "LC_ALL", "DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS", "__CF_USER_TEXT_ENCODING")
            if key in os.environ
        }
        encoded_environment = json.dumps(forwarded_environment, sort_keys=True)
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
                "--normal-groups",
                groups,
                "--caller-environment",
                encoded_environment,
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
            emit_error("evidence", "missing or ambiguous real-Xcode custody evidence")
            return 77
        evidence = json.loads(records[0])
        required = (
            evidence.get("xcodebuildReturnCode") == 0
            and evidence.get("sameUIDAttackReturnCode") != 0
            and all(group > 0 for group in evidence.get("fieldNormalGroups", []))
            and evidence.get("normalGroupsContainCapability") is False
            and evidence.get("buildSupplementaryGroups") == [evidence.get("capabilityGID")]
            and evidence.get("attackSupplementaryGroups") == []
            and evidence.get("buildRootOwnerUIDAfterRevocation") == 0
            and evidence.get("buildRootGroupAfterRevocation") == 0
            and evidence.get("buildRootModeAfterRevocation") == "0o700"
            and evidence.get("compilerProductSHA256") == evidence.get("protectedStageSHA256")
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            emit_error("evidence", f"real-Xcode custody evidence failed semantic checks: {evidence}")
            return 78
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    parser.add_argument("--normal-groups", default="")
    parser.add_argument("--caller-environment", default="{}")
    args = parser.parse_args()
    if args.root_probe:
        if args.package_root is None:
            emit_error("arguments", "--package-root is required for root probe")
            return 79
        try:
            normal_groups = [int(item) for item in args.normal_groups.split(",") if item]
            caller_environment = json.loads(args.caller_environment)
            if not isinstance(caller_environment, dict):
                raise ValueError("caller environment is not an object")
        except (ValueError, json.JSONDecodeError) as error:
            emit_error("arguments", f"invalid root-probe transport: {error}")
            return 79
        return root_probe(args.package_root, normal_groups, caller_environment)
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
