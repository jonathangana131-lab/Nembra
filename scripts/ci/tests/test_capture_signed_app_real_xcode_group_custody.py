#!/usr/bin/env python3
"""Real-Xcode acceptance for dedicated-UID APFS compiler-output custody.

The filename is retained so the permanent Signed App workflow keeps one canonical path.
The old supplementary-group topology is intentionally gone: real Xcode 27 demonstrated
that build-service/log-store processes do not preserve that synthetic group authority.
This probe binds the actual pre-sudo field identity to the root fixture, builds with a
fresh local UID/GID whose effective groups must match its exact Directory Services
baseline, requires the field identity to be unable to mutate compiler output, requires
normal non-forced detach, then accepts bytes only from a read-only remount. Successful
evidence also requires a normal frozen-volume detach and verified retirement of the
fresh build user/group.

Validation only: no signing identity, device operation, Bluetooth, Tuya traffic,
installation, launch, scooter command, or physical evidence occurs here.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import grp
import shutil
import subprocess
import sys
import tempfile
import textwrap
from typing import Iterable

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[2]
ORIGIN_HELPER_PATH = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"
MARKER = "NEMBRA_REAL_XCODE_ORIGIN_JSON="
ERROR_MARKER = "NEMBRA_REAL_XCODE_ORIGIN_ERROR="


class ProbeError(RuntimeError):
    pass


def load_origin_helper():
    spec = importlib.util.spec_from_file_location("nembra_origin_production", ORIGIN_HELPER_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load production build-origin helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str, *, build_output: str = "", detach_output: str = "") -> None:
    payload = {
        "kind": kind,
        "message": message,
        "buildOutputTail": "\n".join(build_output.splitlines()[-140:]),
        "detachOutput": detach_output[-6000:],
        "physicalAuthorityCreated": False,
    }
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
        'print("Nembra real-Xcode dedicated-UID production custody proof")\n',
        encoding="utf-8",
    )


def chown_tree(root: Path, uid: int, gid: int) -> None:
    os.chown(root, uid, gid)
    for directory, directories, files in os.walk(root):
        current = Path(directory)
        os.chown(current, uid, gid)
        for name in directories:
            os.chown(current / name, uid, gid)
        for name in files:
            os.chown(current / name, uid, gid)


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    normalized = sorted({int(value) for value in groups if int(value) != gid})
    if uid <= 0 or gid <= 0 or any(value <= 0 for value in normalized):
        raise ProbeError("invalid structured credential fixture")
    return {"user": uid, "group": gid, "extra_groups": normalized}


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
    for variable in ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS", "__CF_USER_TEXT_ENCODING"):
        value = os.environ.get(variable)
        if value:
            environment[variable] = value
    return environment


def root_probe(
    package_root: Path,
    expected_field_uid: int,
    expected_field_gid: int,
    field_active_groups: list[int],
) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "dedicated-UID root probe requires sudo on real macOS")
        return 70
    helper = load_origin_helper()
    try:
        field_user, field_uid, field_gid, _field_home, field_groups_tuple = helper._invoking_identity()
    except Exception as error:
        emit_error("identity", f"production invoking-identity admission failed: {type(error).__name__}: {error}")
        return 71
    field_groups = sorted(set(field_groups_tuple))
    if field_uid != expected_field_uid or field_gid != expected_field_gid:
        emit_error("identity", "root sudo identity differs from parent pre-sudo UID/GID")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)):
        emit_error("identity", "captured field supplementary-group vector is duplicated")
        return 71
    if field_gid in field_active_groups or any(group <= 0 for group in field_active_groups):
        emit_error("identity", "captured field supplementary groups are invalid")
        return 71
    if not set(field_active_groups).issubset(field_groups):
        emit_error("identity", "captured active field groups exceed directory-service membership")
        return 71

    field_account = pwd.getpwuid(field_uid)
    if field_account.pw_name != field_user:
        emit_error("identity", "field account changed during root admission")
        return 71

    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-dedicated-product.", dir="/private/tmp"))
    source_root = workspace / "source"
    home = workspace / "home"
    mountpoint = workspace / "mount"
    image = workspace / "origin.sparseimage"
    build_name = f"nembrabuildprobe{os.getpid()}"
    build_uid: int | None = None
    build_gid: int | None = None
    build_directory_groups: tuple[int, ...] = ()
    writable_device: str | None = None
    readonly_device: str | None = None
    identity_created = False
    try:
        build_uid = helper._choose_ephemeral_id()
        build_gid = build_uid
        if build_uid == field_uid or build_gid in field_groups or build_gid in field_active_groups:
            emit_error("identity", "ephemeral build identity overlaps field authority")
            return 71

        source_root.mkdir()
        home.mkdir()
        mountpoint.mkdir()
        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        os.chown(home, build_uid, build_gid)
        os.chmod(home, 0o700)

        helper._create_local_build_identity(build_name, build_uid, build_gid, home)
        identity_created = True
        shutil.copytree(package_root, source_root, dirs_exist_ok=True)
        chown_tree(source_root, build_uid, build_gid)
        os.chmod(source_root, 0o700)

        build_environment = helper._build_environment(build_name, home)
        os.chown(home / "tmp", build_uid, build_gid)
        os.chmod(home / "tmp", 0o700)
        helper._create_apfs_image(image)
        writable_device = helper._attach_apfs(image, mountpoint, readonly=False)
        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)
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
        attested_command = helper._credential_attesting_exec_command(
            command, name=build_name, uid=build_uid, gid=build_gid, field_groups=field_groups,
        )
        build = subprocess.run(
            attested_command,
            cwd=source_root,
            env=build_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            **structured_credentials(build_uid, build_gid, []),
        )
        credential_records = [
            line[len(helper.GROUP_ATTESTOR_MARKER):]
            for line in (build.stdout or "").splitlines()
            if line.startswith(helper.GROUP_ATTESTOR_MARKER)
        ]
        if len(credential_records) != 1:
            emit_error("effective-credentials", "missing or ambiguous same-process build credential attestation", build_output=build.stdout)
            return 72
        try:
            credential_attestation = json.loads(credential_records[0])
        except json.JSONDecodeError:
            emit_error("effective-credentials", "same-process build credential attestation is malformed", build_output=build.stdout)
            return 72
        if not (credential_attestation.get("identityExact") is True and credential_attestation.get("groupsExact") is True and credential_attestation.get("fieldOnlyLeak") == [] and credential_attestation.get("effectiveZeroSupplementaryGroupsClaim") is False):
            emit_error("effective-credentials", "same-process compiler credential authority rejected", build_output=build.stdout)
            return 72
        expected_effective_groups = credential_attestation.get("expectedEffectiveGroups")
        if not isinstance(expected_effective_groups, list) or any(not isinstance(group, int) for group in expected_effective_groups):
            emit_error("effective-credentials", "same-process credential baseline is malformed", build_output=build.stdout)
            return 72
        build_directory_groups = sorted(set([build_gid, *expected_effective_groups]))

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

        attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "FIELD_ATTACK\\n" >> "$1"', "sh", str(product)],
            env=field_environment(field_account),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(field_uid, field_gid, field_active_groups),
        )
        if attack.returncode == 0 or sha256(product) != before:
            emit_error("field-isolation", "field identity changed dedicated-UID compiler output")
            return 74

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = helper._detach_apfs(writable_device)
        detach_text = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "real Xcode returned but compiler output could not reach normal non-forced detach",
                build_output=build.stdout,
                detach_output=detach_text,
            )
            return 75
        writable_device = None

        readonly_device = helper._attach_apfs(image, mountpoint, readonly=True)
        try:
            helper._require_readonly_mount(mountpoint)
        except Exception as error:
            emit_error("readonly-remount", f"production read-only probe rejected remount: {error}")
            return 76
        frozen = mountpoint / "DerivedData/Build/Products/Debug/OriginDedicatedUIDProof"
        if not frozen.is_file() or frozen.is_symlink():
            emit_error("readonly-remount", "dedicated-UID product missing after read-only remount")
            return 76
        frozen_sha = sha256(frozen)
        if frozen_sha != before:
            emit_error("readonly-remount", "read-only remount changed dedicated-UID product bytes")
            return 76

        root_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "ROOT_AFTER_FREEZE\\n" >> "$1"', "sh", str(frozen)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if root_attack.returncode == 0 or sha256(frozen) != frozen_sha:
            emit_error("readonly-remount", "root mutated dedicated-UID output after read-only freeze")
            return 77

        former_build_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "BUILD_UID_AFTER_FREEZE\\n" >> "$1"', "sh", str(frozen)],
            env=build_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(build_uid, build_gid, []),
        )
        if former_build_attack.returncode == 0 or sha256(frozen) != frozen_sha:
            emit_error("readonly-remount", "former build identity mutated output after read-only freeze")
            return 78

        frozen_detach = helper._detach_apfs(readonly_device)
        frozen_detach_text = (frozen_detach.stdout or "") + "\n" + (frozen_detach.stderr or "")
        if frozen_detach.returncode != 0:
            emit_error(
                "quiescence",
                "read-only compiler output could not reach normal non-forced detach before principal retirement",
                detach_output=frozen_detach_text,
            )
            return 78
        readonly_device = None

        try:
            helper._remove_local_build_identity(build_name, build_uid, require_absent=True)
        except Exception as error:
            emit_error("identity-retirement", f"ephemeral build principal did not retire cleanly: {error}")
            return 78
        identity_created = False

        evidence = {
            "schemaVersion": 3,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "fieldActiveGroupsSubsetOfDirectoryService": set(field_active_groups).issubset(field_groups),
            "buildUID": build_uid,
            "buildPrimaryGID": build_gid,
            "buildDirectoryServiceGroups": list(build_directory_groups),
            "buildEffectiveGroupAuthorityAttested": True,
            "buildCredentialAttestation": credential_attestation,
            "buildCredentialAttestationSameExecTransition": True,
            "effectiveZeroSupplementaryGroupsClaim": False,
            "buildIdentityDistinctFromField": build_uid != field_uid,
            "fieldGroupsContainBuildGID": build_gid in field_groups,
            "fieldActiveGroupsContainBuildGID": build_gid in field_active_groups,
            "xcodebuildReturnCode": build.returncode,
            "fieldAttackReturnCode": attack.returncode,
            "nonForcedDetachReturnCode": detach.returncode,
            "rootReadonlyAttackReturnCode": root_attack.returncode,
            "formerBuildReadonlyAttackReturnCode": former_build_attack.returncode,
            "readonlyNonForcedDetachReturnCode": frozen_detach.returncode,
            "buildPrincipalRetired": True,
            "compilerProductSHA256": before,
            "readonlyRemountSHA256": frozen_sha,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, subprocess.CalledProcessError, ProbeError, KeyError, RuntimeError) as error:
        emit_error("fixture", f"dedicated-UID production fixture failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if readonly_device is not None:
            helper._detach_apfs(readonly_device, force=True)
        if writable_device is not None:
            helper._detach_apfs(writable_device, force=True)
        if identity_created:
            helper._remove_local_build_identity(build_name, build_uid)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "dedicated-UID real-Xcode custody proof requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "field probe requires one stable non-root invoking identity before sudo")
        return 80
    field_active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "field process carries root/invalid active supplementary-group authority")
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
        item for group in field_active_groups for item in ("--field-active-group", str(group))
    ]
    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-dedicated-package-") as temporary:
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
                "--field-uid",
                str(field_uid),
                "--field-gid",
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
        records = [line[len(MARKER):] for line in completed.stdout.splitlines() if line.startswith(MARKER)]
        if len(records) != 1:
            emit_error("evidence", "missing or ambiguous dedicated-UID Xcode custody evidence")
            return 81
        evidence = json.loads(records[0])
        build_directory_groups = evidence.get("buildDirectoryServiceGroups")
        required = (
            evidence.get("fieldUID") == field_uid
            and evidence.get("fieldPrimaryGID") == field_gid
            and evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
            and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
            and isinstance(build_directory_groups, list)
            and evidence.get("buildPrimaryGID") in build_directory_groups
            and evidence.get("buildEffectiveGroupAuthorityAttested") is True
            and evidence.get("buildCredentialAttestationSameExecTransition") is True
            and evidence.get("effectiveZeroSupplementaryGroupsClaim") is False
            and evidence.get("buildCredentialAttestation", {}).get("identityExact") is True
            and evidence.get("buildCredentialAttestation", {}).get("groupsExact") is True
            and evidence.get("buildCredentialAttestation", {}).get("fieldOnlyLeak") == []
            and evidence.get("fieldGroupsContainBuildGID") is False
            and evidence.get("fieldActiveGroupsContainBuildGID") is False
            and evidence.get("buildIdentityDistinctFromField") is True
            and evidence.get("xcodebuildReturnCode") == 0
            and evidence.get("fieldAttackReturnCode") != 0
            and evidence.get("nonForcedDetachReturnCode") == 0
            and evidence.get("rootReadonlyAttackReturnCode") != 0
            and evidence.get("formerBuildReadonlyAttackReturnCode") != 0
            and evidence.get("readonlyNonForcedDetachReturnCode") == 0
            and evidence.get("buildPrincipalRetired") is True
            and evidence.get("compilerProductSHA256") == evidence.get("readonlyRemountSHA256")
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            emit_error("evidence", f"dedicated-UID Xcode custody evidence failed semantic checks: {evidence}")
            return 82
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-gid", type=int)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if (
            args.package_root is None
            or args.field_uid is None
            or args.field_gid is None
            or args.field_active_group_count is None
            or args.field_active_group_count != len(args.field_active_group)
        ):
            emit_error("arguments", "root probe requires exact parent field identity and group vector")
            return 83
        return root_probe(args.package_root, args.field_uid, args.field_gid, args.field_active_group)
    if (
        args.package_root is not None
        or args.field_uid is not None
        or args.field_gid is not None
        or args.field_active_group
        or args.field_active_group_count is not None
    ):
        emit_error("arguments", "root-only fixture arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
