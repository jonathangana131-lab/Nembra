#!/usr/bin/env python3
"""Real-macOS feasibility probe for signed-app compiler-output origin isolation.

#2955 proves that a digest first minted from a same-UID-mutable DerivedData app
after xcodebuild returns cannot establish compiler-output origin. This probe tests
a capability-style repair primitive without changing production: a root broker
creates a root-owned build namespace writable only by an ephemeral supplementary
GID, launches real xcodebuild as the original field UID with that GID, proves a
same-UID sibling without the GID cannot mutate the product, then snapshots the
product while the isolated namespace is still held.

Validation only. No device, Bluetooth, Tuya, signing identity, install, launch, or
physical experiment is used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _drop_to_field_user(uid: int, gid: int, supplementary: list[int]) -> None:
    os.setgroups(supplementary)
    os.setgid(gid)
    os.setuid(uid)


def _root_helper(package_root: Path, field_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise SystemExit("root helper requires the real macOS sudo boundary")

    try:
        field_uid = int(os.environ["SUDO_UID"])
        field_gid = int(os.environ["SUDO_GID"])
    except (KeyError, ValueError) as exc:
        raise SystemExit("root helper requires SUDO_UID/SUDO_GID from the invoking field user") from exc
    if field_uid == 0:
        raise SystemExit("root helper refuses a root field identity")

    account = pwd.getpwuid(field_uid)
    field_groups = sorted(set(group for group in field_groups if group >= 0))
    if field_gid not in field_groups:
        field_groups.append(field_gid)

    # A numeric supplementary GID does not need a directory-service group entry.
    # Pick one outside the invoking process's current group set and use it only as
    # an in-kernel capability shared by this broker and its xcodebuild child tree.
    ephemeral_gid = 60000 + (os.getpid() % 4000)
    while ephemeral_gid in field_groups:
        ephemeral_gid += 1

    build_root = Path(tempfile.mkdtemp(prefix="nembra-origin-build.", dir="/private/tmp"))
    stage_root = Path(tempfile.mkdtemp(prefix="nembra-origin-stage.", dir="/private/tmp"))
    try:
        os.chown(build_root, 0, ephemeral_gid)
        os.chmod(build_root, 0o770)
        os.chown(stage_root, 0, 0)
        os.chmod(stage_root, 0o700)

        child_env = {
            "HOME": account.pw_dir,
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": "/tmp",
            "LANG": "C",
            "LC_ALL": "C",
        }
        xcodebuild = "/usr/bin/xcodebuild"
        command = [
            xcodebuild,
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
            "build",
        ]
        build = subprocess.run(
            command,
            cwd=package_root,
            env=child_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            preexec_fn=lambda: _drop_to_field_user(
                field_uid,
                field_gid,
                sorted(set(field_groups + [ephemeral_gid])),
            ),
        )
        if build.returncode != 0:
            print(build.stdout, file=sys.stderr)
            raise SystemExit(f"real xcodebuild could not write the isolated DerivedData namespace: {build.returncode}")

        product = build_root / "Build/Products/Debug/OriginProof"
        if not product.is_file() or product.is_symlink():
            raise SystemExit(f"real xcodebuild product missing from isolated namespace: {product}")
        product_before = _sha256(product)

        # This sibling has the exact same UID + normal groups as the field user,
        # but deliberately does not receive the ephemeral build capability.
        attack = subprocess.run(
            ["/bin/sh", "-c", f"printf '\\nATTACKER\\n' >> {shlex_quote(str(product))}"],
            env=child_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=lambda: _drop_to_field_user(field_uid, field_gid, field_groups),
        )
        if attack.returncode == 0:
            raise SystemExit("same-UID sibling unexpectedly mutated the isolated xcodebuild product")
        if _sha256(product) != product_before:
            raise SystemExit("isolated xcodebuild product changed across the denied same-UID attack")

        staged = stage_root / "OriginProof"
        shutil.copy2(product, staged, follow_symlinks=False)
        os.chown(staged, 0, 0)
        os.chmod(staged, stat.S_IMODE(staged.stat().st_mode) & ~0o022)
        staged_hash = _sha256(staged)
        if staged_hash != product_before:
            raise SystemExit("root-held snapshot differs from the isolated xcodebuild product")

        result = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "ephemeralBuildGID": ephemeral_gid,
            "fieldGroupsContainEphemeralGID": ephemeral_gid in field_groups,
            "buildRootOwnerUID": build_root.stat().st_uid,
            "buildRootGroupGID": build_root.stat().st_gid,
            "buildRootMode": oct(stat.S_IMODE(build_root.stat().st_mode)),
            "xcodebuildReturnCode": build.returncode,
            "sameUIDAttackReturnCode": attack.returncode,
            "compilerProductSHA256": product_before,
            "protectedStageSHA256": staged_hash,
            "stageOwnerUID": staged.stat().st_uid,
            "physicalAuthorityCreated": False,
        }
        print("NEMBRA_SIGNED_ORIGIN_ISOLATION_JSON=" + json.dumps(result, sort_keys=True))
        return 0
    finally:
        shutil.rmtree(build_root, ignore_errors=True)
        shutil.rmtree(stage_root, ignore_errors=True)


def shlex_quote(value: str) -> str:
    # Keep the privileged helper dependency-free while producing an exact shell
    # literal for the intentionally unprivileged attacker child.
    return "'" + value.replace("'", "'\\''") + "'"


class SignedAppProcessGroupIsolationProbeTests(unittest.TestCase):
    def setUp(self) -> None:
        if sys.platform != "darwin":
            self.skipTest("real supplementary-group/xcodebuild proof requires macOS")
        probe = subprocess.run(
            ["/usr/bin/sudo", "-n", "/usr/bin/true"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.assertEqual(probe.returncode, 0, "xcode-27 runner must expose noninteractive sudo for this validation-only probe")

    def test_real_xcodebuild_output_isolated_from_same_uid_sibling_until_root_snapshot(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-origin-package-") as temporary:
            package = Path(temporary)
            (package / "Package.swift").write_text(
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
            source = package / "Sources/OriginProof"
            source.mkdir(parents=True)
            (source / "main.swift").write_text('print("Nembra compiler-origin isolation proof")\n', encoding="utf-8")

            groups = ",".join(str(group) for group in os.getgroups())
            completed = subprocess.run(
                [
                    "/usr/bin/sudo",
                    "-n",
                    "/usr/bin/python3",
                    "-I",
                    str(Path(__file__).resolve()),
                    "--root-helper",
                    "--package-root",
                    str(package),
                    "--field-groups",
                    groups,
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if completed.returncode != 0:
                self.fail(
                    "process-group isolation broker failed before producing evidence\n"
                    f"stdout:\n{completed.stdout}\n"
                    f"stderr:\n{completed.stderr}"
                )
            marker = "NEMBRA_SIGNED_ORIGIN_ISOLATION_JSON="
            records = [line[len(marker):] for line in completed.stdout.splitlines() if line.startswith(marker)]
            self.assertEqual(len(records), 1, f"missing/ambiguous isolation evidence: {completed.stdout}")
            evidence = json.loads(records[0])
            self.assertEqual(evidence["xcodebuildReturnCode"], 0)
            self.assertNotEqual(evidence["sameUIDAttackReturnCode"], 0)
            self.assertFalse(evidence["fieldGroupsContainEphemeralGID"])
            self.assertEqual(evidence["buildRootOwnerUID"], 0)
            self.assertEqual(evidence["buildRootGroupGID"], evidence["ephemeralBuildGID"])
            self.assertEqual(evidence["buildRootMode"], "0o770")
            self.assertEqual(evidence["compilerProductSHA256"], evidence["protectedStageSHA256"])
            self.assertEqual(evidence["stageOwnerUID"], 0)
            self.assertFalse(evidence["physicalAuthorityCreated"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--root-helper", action="store_true")
    parser.add_argument("--package-root", type=Path)
    parser.add_argument("--field-groups", default="")
    known, remaining = parser.parse_known_args()
    if known.root_helper:
        if remaining:
            raise SystemExit(f"unexpected root-helper arguments: {remaining}")
        if known.package_root is None:
            raise SystemExit("--package-root is required")
        groups = [int(item) for item in known.field_groups.split(",") if item]
        raise SystemExit(_root_helper(known.package_root, groups))
    unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
