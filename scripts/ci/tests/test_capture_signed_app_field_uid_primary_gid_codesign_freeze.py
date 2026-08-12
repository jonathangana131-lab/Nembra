#!/usr/bin/env python3
"""Validate a field-UID signing bridge through a fresh primary GID and APFS freeze.

This validation-only witness answers one narrow question left between the accepted dedicated-build
UID/APFS compiler-output architecture and the real field account's future Apple signing context:
can the real field UID keep its exact pre-sudo baseline group identity while receiving one fresh
primary GID that alone traverses a root-hidden signing workspace, sign a real Mach-O app with direct
ad-hoc codesign, then reach a normal non-forced APFS detach and byte-identical read-only remount?

The ordinary field identity is replayed independently and must remain unable to traverse/mutate the
protected subject. The signer child's actual kernel UID/GID/os.getgroups() are measured rather than
inferred from subprocess constructor arguments. Internal APFS owner-UID mapping is recorded but is
not treated as the access boundary; the root-hidden outer workspace + fresh primary GID is.

A green result is architecture evidence only. It does not exercise an Apple Development identity,
keychain access, provisioning, private Tuya inputs, device install, Bluetooth, telemetry, commands,
or physical scooter authority.
"""
from __future__ import annotations

import argparse
import grp
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import pwd
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Iterable

HERE = Path(__file__).resolve().parent
FREEZE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_FIELD_UID_PRIMARY_GID_CODESIGN_FREEZE_JSON="
ERROR_MARKER = "NEMBRA_FIELD_UID_PRIMARY_GID_CODESIGN_FREEZE_ERROR="
PATH_MARKER = "NEMBRA_FIELD_UID_PRIMARY_GID_PATH_JSON="


class ProbeError(RuntimeError):
    pass


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "kind": kind,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def load_freeze_helper():
    spec = importlib.util.spec_from_file_location(
        "nembra_field_uid_codesign_freeze_helper",
        FREEZE_HELPER_PATH,
    )
    if spec is None or spec.loader is None:
        raise ProbeError("could not load accepted APFS freeze helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise ProbeError("structured credentials require positive non-root UID/GID")
    normalized = sorted({int(group) for group in groups if int(group) != gid})
    if any(group <= 0 for group in normalized):
        raise ProbeError("structured credentials contain root or invalid supplementary authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def choose_capability_gid(field_groups: Iterable[int]) -> int:
    occupied = {entry.gr_gid for entry in grp.getgrall()}
    occupied.update(int(group) for group in field_groups)
    occupied.add(0)
    low = 1 << 29
    span = (1 << 30) - low
    for _ in range(256):
        candidate = low + secrets.randbelow(span)
        if candidate not in occupied:
            return candidate
    raise ProbeError("could not allocate a fresh signing primary GID")


def tree_fingerprint(root: Path) -> str:
    if not root.is_dir() or root.is_symlink():
        raise ProbeError("signing subject is not one real directory")
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        metadata = path.lstat()
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISLNK(metadata.st_mode):
            kind = b"L"
            payload = os.readlink(path).encode("utf-8")
        elif stat.S_ISDIR(metadata.st_mode):
            kind = b"D"
            payload = b""
        elif stat.S_ISREG(metadata.st_mode):
            kind = b"F"
            payload = path.read_bytes()
        else:
            raise ProbeError(f"unexpected signing-subject node type: {path}")
        digest.update(kind)
        digest.update(b"\0")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(f"{mode:o}".encode("ascii"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(payload).digest())
        digest.update(b"\0")
    return digest.hexdigest()


def metadata(path: Path) -> dict[str, object]:
    value = path.lstat()
    return {
        "uid": value.st_uid,
        "gid": value.st_gid,
        "mode": oct(stat.S_IMODE(value.st_mode)),
        "isDirectory": stat.S_ISDIR(value.st_mode),
        "isSymlink": stat.S_ISLNK(value.st_mode),
    }


def make_unsigned_app(app: Path, capability_gid: int) -> None:
    contents = app / "Contents"
    macos = contents / "MacOS"
    macos.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(
        plistlib.dumps(
            {
                "CFBundleExecutable": "SignerProof",
                "CFBundleIdentifier": "com.nembra.validation.signerproof",
                "CFBundleName": "SignerProof",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
            },
            fmt=plistlib.FMT_XML,
            sort_keys=True,
        )
    )
    executable = macos / "SignerProof"
    compiled = subprocess.run(
        ["/usr/bin/xcrun", "clang", "-x", "c", "-o", str(executable), "-"],
        input="int main(void) { return 0; }\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if compiled.returncode != 0:
        raise ProbeError("could not create Mach-O signing fixture: " + compiled.stderr.strip())

    for directory, directories, files in os.walk(app):
        current = Path(directory)
        os.chown(current, 0, capability_gid)
        os.chmod(current, 0o770)
        for name in directories:
            child = current / name
            os.chown(child, 0, capability_gid)
            os.chmod(child, 0o770)
        for name in files:
            child = current / name
            os.chown(child, 0, capability_gid)
            os.chmod(child, 0o770 if child == executable else 0o660)


def signer_path_probe_code() -> str:
    return r'''
import json
import os
from pathlib import Path
import stat
import sys

workspace = Path(sys.argv[1])
mountpoint = Path(sys.argv[2])
app = Path(sys.argv[3])
contents = app / "Contents"
probe = contents / "signer-path-probe.tmp"

def meta(path):
    value = path.lstat()
    return {
        "uid": value.st_uid,
        "gid": value.st_gid,
        "mode": oct(stat.S_IMODE(value.st_mode)),
        "isDirectory": stat.S_ISDIR(value.st_mode),
        "isSymlink": stat.S_ISLNK(value.st_mode),
    }

record = {
    "realUID": os.getuid(),
    "effectiveUID": os.geteuid(),
    "realPrimaryGID": os.getgid(),
    "effectivePrimaryGID": os.getegid(),
    "rawSupplementaryGroups": sorted(os.getgroups()),
    "workspace": meta(workspace),
    "mountpoint": meta(mountpoint),
    "app": meta(app),
    "contents": meta(contents),
    "writeSucceeded": False,
    "cleanupSucceeded": False,
}
try:
    probe.write_text("NEMBRA_SIGNER_PATH_PROBE\n", encoding="utf-8")
    record["writeSucceeded"] = True
    probe.unlink()
    record["cleanupSucceeded"] = True
except OSError as error:
    record["writeErrno"] = error.errno
    record["writeError"] = str(error)
print("NEMBRA_FIELD_UID_PRIMARY_GID_PATH_JSON=" + json.dumps(record, sort_keys=True))
'''


def run_signer_path_probe(
    workspace: Path,
    mountpoint: Path,
    app: Path,
    *,
    environment: dict[str, str],
    field_uid: int,
    capability_gid: int,
) -> dict[str, object]:
    completed = subprocess.run(
        [
            "/usr/bin/python3",
            "-B",
            "-I",
            "-c",
            signer_path_probe_code(),
            str(workspace),
            str(mountpoint),
            str(app),
        ],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **structured_credentials(field_uid, capability_gid, []),
    )
    records = [
        line[len(PATH_MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(PATH_MARKER)
    ]
    if completed.returncode != 0 or len(records) != 1:
        raise ProbeError(
            "signer path attestation did not return one canonical record: "
            + (completed.stdout + "\n" + completed.stderr)[-6000:]
        )
    try:
        record = json.loads(records[0])
    except json.JSONDecodeError as error:
        raise ProbeError("signer path attestation returned malformed JSON") from error
    if not isinstance(record, dict):
        raise ProbeError("signer path attestation returned a non-object")
    return record


def root_probe(field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "field-UID codesign freeze root probe requires sudo on macOS")
        return 70
    for tool in ("/usr/bin/codesign", "/usr/bin/hdiutil", "/usr/bin/xcrun", "/usr/bin/python3"):
        if not Path(tool).is_file():
            emit_error("environment", f"required macOS tool is missing: {tool}")
            return 70

    try:
        field_uid = int(os.environ["SUDO_UID"])
        field_gid = int(os.environ["SUDO_GID"])
        field_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if field_uid <= 0 or field_gid <= 0:
        emit_error("identity", "field signing identity must be non-root")
        return 71
    try:
        account = pwd.getpwuid(field_uid)
    except KeyError:
        emit_error("identity", "sudo field UID has no local account")
        return 71
    if account.pw_name != field_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo identity does not match the local field account")
        return 71

    directory_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    if any(group <= 0 for group in directory_groups):
        emit_error("identity", "field account carries root or invalid Directory Services group authority")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)):
        emit_error("identity", "captured active supplementary vector contains duplicates")
        return 71
    if any(group <= 0 for group in field_active_groups) or field_gid in field_active_groups:
        emit_error("identity", "captured active supplementary vector is invalid")
        return 71
    if not set(field_active_groups).issubset(directory_groups):
        emit_error("identity", "captured active field groups exceed Directory Services membership")
        return 71

    field_baseline = sorted(set([field_gid, *field_active_groups]))
    capability_gid = choose_capability_gid([*directory_groups, field_gid])
    if capability_gid == field_gid or capability_gid in directory_groups or capability_gid in field_active_groups:
        emit_error("identity", "fresh signing primary GID overlaps ordinary field authority")
        return 71

    helper = load_freeze_helper()
    workspace = Path(tempfile.mkdtemp(prefix="nembra-field-uid-codesign-freeze.", dir="/private/tmp"))
    image = workspace / "signing.sparseimage"
    mountpoint = workspace / "mount"
    mountpoint.mkdir()
    os.chown(workspace, 0, capability_gid)
    os.chmod(workspace, 0o710)
    os.chown(mountpoint, 0, capability_gid)
    os.chmod(mountpoint, 0o770)

    device: str | None = None
    try:
        helper.hdiutil_create(image)
        device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, 0, capability_gid)
        os.chmod(mountpoint, 0o770)

        app = mountpoint / "SignerProof.app"
        make_unsigned_app(app, capability_gid)
        unsigned = tree_fingerprint(app)

        field_environment = {
            "HOME": account.pw_dir,
            "USER": account.pw_name,
            "LOGNAME": account.pw_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": "/tmp",
            "LANG": "C",
            "LC_ALL": "C",
        }

        ordinary_attack = subprocess.run(
            [
                "/bin/sh",
                "-c",
                'printf "ORDINARY_FIELD_ATTACK\\n" >> "$1"',
                "sh",
                str(app / "Contents/Info.plist"),
            ],
            env=field_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(field_uid, field_gid, field_active_groups),
        )
        if ordinary_attack.returncode == 0 or tree_fingerprint(app) != unsigned:
            emit_error(
                "field-isolation",
                "ordinary field identity mutated the signing subject without the fresh primary GID",
                ordinaryFieldOutput=(ordinary_attack.stdout + "\n" + ordinary_attack.stderr)[-4000:],
            )
            return 72

        path_probe = run_signer_path_probe(
            workspace,
            mountpoint,
            app,
            environment=field_environment,
            field_uid=field_uid,
            capability_gid=capability_gid,
        )
        raw_groups = path_probe.get("rawSupplementaryGroups")
        if not isinstance(raw_groups, list) or any(not isinstance(group, int) for group in raw_groups):
            emit_error("signer-identity", "signer path attestation exposed no integer kernel group vector", pathProbe=path_probe)
            return 73
        normalized_signer_groups = sorted({group for group in raw_groups if group != capability_gid})
        unexpected_groups = sorted(set(normalized_signer_groups).difference(field_baseline))
        missing_groups = sorted(set(field_baseline).difference(normalized_signer_groups))
        signer_identity_exact = (
            path_probe.get("realUID") == field_uid
            and path_probe.get("effectiveUID") == field_uid
            and path_probe.get("realPrimaryGID") == capability_gid
            and path_probe.get("effectivePrimaryGID") == capability_gid
            and not unexpected_groups
            and not missing_groups
            and path_probe.get("writeSucceeded") is True
            and path_probe.get("cleanupSucceeded") is True
        )
        path_probe["capturedFieldBaselineGroups"] = field_baseline
        path_probe["normalizedSupplementaryGroups"] = normalized_signer_groups
        path_probe["unexpectedGroupsBeyondFieldBaseline"] = unexpected_groups
        path_probe["missingFieldBaselineGroups"] = missing_groups
        path_probe["fieldBaselinePreservedExact"] = not unexpected_groups and not missing_groups
        if not signer_identity_exact:
            emit_error(
                "signer-identity",
                "field-UID signer did not match the exact baseline + fresh-primary-GID contract",
                pathProbe=path_probe,
            )
            return 73
        if tree_fingerprint(app) != unsigned:
            emit_error("signer-path", "signer path probe did not restore the unsigned fixture exactly", pathProbe=path_probe)
            return 73

        signing = subprocess.run(
            [
                "/usr/bin/codesign",
                "--force",
                "--verbose=4",
                "--sign",
                "-",
                "--timestamp=none",
                str(app),
            ],
            env=field_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(field_uid, capability_gid, []),
        )
        if signing.returncode != 0:
            emit_error(
                "codesign",
                f"direct ad-hoc codesign failed under the attested signer identity: {signing.returncode}",
                pathProbe=path_probe,
                signingOutput=(signing.stdout + "\n" + signing.stderr)[-6000:],
            )
            return 74

        verify_live = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if verify_live.returncode != 0:
            emit_error("codesign", "live signed app failed strict verification", verifyOutput=verify_live.stderr[-6000:])
            return 75
        signed = tree_fingerprint(app)
        if signed == unsigned:
            emit_error("codesign", "codesign reported success without changing the signing subject")
            return 75

        detach = helper.hdiutil_detach(device)
        detach_output = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "signed output could not reach a normal non-forced APFS detach",
                detachOutput=detach_output[-6000:],
            )
            return 76
        device = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen_app = mountpoint / "SignerProof.app"
        frozen = tree_fingerprint(frozen_app)
        if frozen != signed:
            emit_error("readonly-remount", "signed tree changed across APFS freeze", signed=signed, frozen=frozen)
            return 77

        verify_frozen = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(frozen_app)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if verify_frozen.returncode != 0:
            emit_error(
                "readonly-remount",
                "signature failed strict verification after read-only remount",
                verifyOutput=verify_frozen.stderr[-6000:],
            )
            return 77

        root_attack = subprocess.run(
            [
                "/bin/sh",
                "-c",
                'printf "ROOT_AFTER_FREEZE\\n" > "$1/root-attack.txt"',
                "sh",
                str(frozen_app),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if root_attack.returncode == 0 or tree_fingerprint(frozen_app) != frozen:
            emit_error("readonly-remount", "root mutated the read-only signed subject")
            return 78

        former_signer = subprocess.run(
            [
                "/bin/sh",
                "-c",
                'printf "SIGNER_AFTER_FREEZE\\n" > "$1/signer-attack.txt"',
                "sh",
                str(frozen_app),
            ],
            env=field_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(field_uid, capability_gid, []),
        )
        if former_signer.returncode == 0 or tree_fingerprint(frozen_app) != frozen:
            emit_error("readonly-remount", "former signer mutated the read-only signed subject")
            return 79

        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "capturedFieldBaselineGroups": field_baseline,
            "fieldActiveGroupsSubsetOfDirectoryServices": set(field_active_groups).issubset(directory_groups),
            "signingCapabilityGID": capability_gid,
            "fieldDirectoryGroupsContainSigningCapability": capability_gid in directory_groups,
            "fieldActiveGroupsContainSigningCapability": capability_gid in field_active_groups,
            "workspaceMetadata": metadata(workspace),
            "mountpointMetadataBeforeFreeze": metadata(mountpoint),
            "signerPathProbe": path_probe,
            "ordinaryFieldAttackReturnCode": ordinary_attack.returncode,
            "codesignReturnCode": signing.returncode,
            "liveCodesignVerifyReturnCode": verify_live.returncode,
            "nonForcedDetachReturnCode": detach.returncode,
            "frozenCodesignVerifyReturnCode": verify_frozen.returncode,
            "rootReadonlyAttackReturnCode": root_attack.returncode,
            "formerSignerReadonlyAttackReturnCode": former_signer.returncode,
            "unsignedTreeSHA256": unsigned,
            "signedTreeSHA256": signed,
            "readonlyRemountTreeSHA256": frozen,
            "appleIdentityExercised": False,
            "provisioningExercised": False,
            "privateTuyaInputExercised": False,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except Exception as error:
        emit_error("fixture", f"field-UID codesign freeze fixture failed: {type(error).__name__}: {error}")
        return 80
    finally:
        if device is not None:
            try:
                helper.hdiutil_detach(device, force=True)
            except Exception:
                pass
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "field-UID codesign freeze probe requires macOS")
        return 81
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "field parent requires one stable non-root UID/GID")
        return 81
    field_active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "field parent carries root or invalid active group authority")
        return 81

    sudo = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sudo.returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 81

    active_args = [
        item
        for group in field_active_groups
        for item in ("--field-active-group", str(group))
    ]
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
            "--field-active-group-count",
            str(len(field_active_groups)),
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

    records = [
        line[len(MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(MARKER)
    ]
    if len(records) != 1:
        emit_error("evidence", "missing or ambiguous field-UID codesign freeze success record")
        return 82
    try:
        evidence = json.loads(records[0])
    except json.JSONDecodeError as error:
        emit_error("evidence", f"malformed success evidence: {error}")
        return 82

    path_probe = evidence.get("signerPathProbe")
    capability_gid = evidence.get("signingCapabilityGID")
    expected_baseline = sorted(set([field_gid, *field_active_groups]))
    required = (
        evidence.get("schemaVersion") == 1
        and evidence.get("fieldUID") == field_uid
        and evidence.get("fieldPrimaryGID") == field_gid
        and evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
        and evidence.get("capturedFieldBaselineGroups") == expected_baseline
        and evidence.get("fieldActiveGroupsSubsetOfDirectoryServices") is True
        and isinstance(capability_gid, int)
        and capability_gid > 0
        and capability_gid != field_gid
        and evidence.get("fieldDirectoryGroupsContainSigningCapability") is False
        and evidence.get("fieldActiveGroupsContainSigningCapability") is False
        and isinstance(path_probe, dict)
        and path_probe.get("realUID") == field_uid
        and path_probe.get("effectiveUID") == field_uid
        and path_probe.get("realPrimaryGID") == capability_gid
        and path_probe.get("effectivePrimaryGID") == capability_gid
        and path_probe.get("capturedFieldBaselineGroups") == expected_baseline
        and path_probe.get("normalizedSupplementaryGroups") == expected_baseline
        and path_probe.get("fieldBaselinePreservedExact") is True
        and path_probe.get("unexpectedGroupsBeyondFieldBaseline") == []
        and path_probe.get("missingFieldBaselineGroups") == []
        and path_probe.get("writeSucceeded") is True
        and path_probe.get("cleanupSucceeded") is True
        and evidence.get("ordinaryFieldAttackReturnCode") != 0
        and evidence.get("codesignReturnCode") == 0
        and evidence.get("liveCodesignVerifyReturnCode") == 0
        and evidence.get("nonForcedDetachReturnCode") == 0
        and evidence.get("frozenCodesignVerifyReturnCode") == 0
        and evidence.get("rootReadonlyAttackReturnCode") != 0
        and evidence.get("formerSignerReadonlyAttackReturnCode") != 0
        and evidence.get("unsignedTreeSHA256") != evidence.get("signedTreeSHA256")
        and evidence.get("signedTreeSHA256") == evidence.get("readonlyRemountTreeSHA256")
        and evidence.get("appleIdentityExercised") is False
        and evidence.get("provisioningExercised") is False
        and evidence.get("privateTuyaInputExercised") is False
        and evidence.get("productionAcceptanceClaimed") is False
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        emit_error("evidence", f"field-UID codesign freeze success record failed semantic acceptance: {evidence}")
        return 83
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if (
            args.field_active_group_count is None
            or args.field_active_group_count != len(args.field_active_group)
        ):
            emit_error("arguments", "root probe requires one counted pre-sudo active-group vector")
            return 84
        return root_probe(args.field_active_group)
    if args.field_active_group or args.field_active_group_count is not None:
        emit_error("arguments", "root-only active-group arguments are unavailable in field-parent mode")
        return 84
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
