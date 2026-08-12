#!/usr/bin/env python3
"""Validation-only direct-codesign capability -> APFS freeze bridge.

The accepted dedicated-build-UID oracle proves real Xcode can produce compiler output under an
identity that the field user does not share, then reach a normal non-forced APFS detach and a
byte-identical read-only remount. Production still needs a signing/provisioning bridge because the
real field build currently relies on the invoking user's Apple signing context.

This witness isolates one narrower prerequisite without using an Apple identity or provisioning
profile: can /usr/bin/codesign itself run as the real field UID while carrying one fresh numeric
supplementary GID that alone grants write access to a signing volume, while the same field UID with
its actual pre-sudo active groups remains excluded? After ad-hoc signing completes, the witness
requires a normal non-forced APFS detach, read-only remount, exact tree-fingerprint preservation,
valid code-signature verification, and failed root/former-signer mutation attempts.

A green result is architecture evidence only. It does not prove Apple Development keychain access,
automatic provisioning, embedded.mobileprovision selection, device admission, install, Bluetooth,
Tuya, telemetry, or physical scooter authority.
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
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Iterable

HERE = Path(__file__).resolve().parent
FREEZE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_CODESIGN_CAPABILITY_FREEZE_JSON="
ERROR_MARKER = "NEMBRA_CODESIGN_CAPABILITY_FREEZE_ERROR="


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
        "nembra_codesign_capability_freeze_helper",
        FREEZE_HELPER_PATH,
    )
    if spec is None or spec.loader is None:
        raise ProbeError("could not load accepted APFS freeze validation helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise ProbeError("structured credentials require non-root UID/GID")
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
    raise ProbeError("could not allocate a fresh signing capability GID")


def tree_fingerprint(root: Path) -> str:
    if not root.is_dir() or root.is_symlink():
        raise ProbeError("signed proof bundle is not one real directory")
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
            raise ProbeError(f"unexpected proof-bundle node type: {path}")
        digest.update(kind)
        digest.update(b"\0")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(f"{mode:o}".encode("ascii"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(payload).digest())
        digest.update(b"\0")
    return digest.hexdigest()


def make_unsigned_app(app: Path, capability_gid: int) -> None:
    contents = app / "Contents"
    macos = contents / "MacOS"
    macos.mkdir(parents=True)
    plist = contents / "Info.plist"
    plist.write_text(
        """<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\"><dict>\n"
        "<key>CFBundleExecutable</key><string>SignerProof</string>\n"
        "<key>CFBundleIdentifier</key><string>com.nembra.validation.signerproof</string>\n"
        "<key>CFBundleName</key><string>SignerProof</string>\n"
        "<key>CFBundlePackageType</key><string>APPL</string>\n"
        "<key>CFBundleVersion</key><string>1</string>\n"
        "<key>CFBundleShortVersionString</key><string>1.0</string>\n"
        "</dict></plist>\n""",
        encoding="utf-8",
    )
    executable = macos / "SignerProof"
    compiled = subprocess.run(
        ["/usr/bin/xcrun", "clang", "-x", "c", "-o", str(executable), "-"],
        input="int main(void) { return 0; }\n",
        stdin=subprocess.PIPE,
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


def root_probe(field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "codesign capability probe requires sudo on real macOS")
        return 70
    for tool in ("/usr/bin/codesign", "/usr/bin/hdiutil", "/usr/bin/xcrun"):
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
    account = pwd.getpwuid(field_uid)
    if account.pw_name != field_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo identity does not match the local field account")
        return 71

    directory_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    if any(group <= 0 for group in directory_groups):
        emit_error("identity", "field account carries root or invalid group authority")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)):
        emit_error("identity", "captured active supplementary groups are duplicated")
        return 71
    if any(group <= 0 for group in field_active_groups) or field_gid in field_active_groups:
        emit_error("identity", "captured active supplementary groups are invalid")
        return 71
    if not set(field_active_groups).issubset(directory_groups):
        emit_error("identity", "captured active supplementary groups exceed directory-service membership")
        return 71

    capability_gid = choose_capability_gid(directory_groups)
    if capability_gid in field_active_groups:
        emit_error("identity", "fresh signing capability overlaps active field authority")
        return 71

    helper = load_freeze_helper()
    workspace = Path(tempfile.mkdtemp(prefix="nembra-codesign-capability-freeze.", dir="/private/tmp"))
    image = workspace / "signing.sparseimage"
    mountpoint = workspace / "mount"
    mountpoint.mkdir()
    os.chown(workspace, 0, capability_gid)
    os.chmod(workspace, 0o710)

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
            ["/bin/sh", "-c", 'printf "FIELD_ATTACK\\n" >> "$1"', "sh", str(app / "Contents/Info.plist")],
            env=field_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(field_uid, field_gid, field_active_groups),
        )
        if ordinary_attack.returncode == 0 or tree_fingerprint(app) != unsigned:
            emit_error("field-isolation", "ordinary field identity mutated signing volume without capability")
            return 72

        signer_groups = [*field_active_groups, capability_gid]
        signing = subprocess.run(
            [
                "/usr/bin/codesign",
                "--force",
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
            **structured_credentials(field_uid, field_gid, signer_groups),
        )
        if signing.returncode != 0:
            emit_error(
                "codesign",
                f"direct codesign could not use the one-run filesystem capability: {signing.returncode}",
                signingOutput=(signing.stdout + "\n" + signing.stderr)[-6000:],
            )
            return 73

        verify_live = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if verify_live.returncode != 0:
            emit_error("codesign", "ad-hoc signature did not verify before freeze", verifyOutput=verify_live.stderr[-6000:])
            return 74
        signed = tree_fingerprint(app)
        if signed == unsigned:
            emit_error("codesign", "codesign reported success without changing the proof bundle")
            return 74

        detach = helper.hdiutil_detach(device)
        detach_output = (detach.stdout or "") + "\n" + (detach.stderr or "")
        if detach.returncode != 0:
            emit_error(
                "quiescence",
                "signed output could not reach a normal non-forced APFS detach",
                detachOutput=detach_output[-6000:],
            )
            return 75
        device = None

        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen_app = mountpoint / "SignerProof.app"
        frozen = tree_fingerprint(frozen_app)
        if frozen != signed:
            emit_error("readonly-remount", "signed bundle changed across APFS freeze", signed=signed, frozen=frozen)
            return 76

        verify_frozen = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(frozen_app)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if verify_frozen.returncode != 0:
            emit_error("readonly-remount", "signature failed verification after read-only remount", verifyOutput=verify_frozen.stderr[-6000:])
            return 76

        root_attack = subprocess.run(
            ["/bin/sh", "-c", 'printf "ROOT_AFTER_FREEZE\\n" > "$1/root-attack.txt"', "sh", str(frozen_app)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if root_attack.returncode == 0 or tree_fingerprint(frozen_app) != frozen:
            emit_error("readonly-remount", "root mutated the read-only signed bundle")
            return 77

        former_signer = subprocess.run(
            ["/bin/sh", "-c", 'printf "SIGNER_AFTER_FREEZE\\n" > "$1/signer-attack.txt"', "sh", str(frozen_app)],
            env=field_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **structured_credentials(field_uid, field_gid, signer_groups),
        )
        if former_signer.returncode == 0 or tree_fingerprint(frozen_app) != frozen:
            emit_error("readonly-remount", "former signing capability mutated the read-only bundle")
            return 78

        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "fieldActiveGroupsSubsetOfDirectoryService": set(field_active_groups).issubset(directory_groups),
            "signingCapabilityGID": capability_gid,
            "fieldGroupsContainSigningCapability": capability_gid in directory_groups,
            "fieldActiveGroupsContainSigningCapability": capability_gid in field_active_groups,
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
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, subprocess.CalledProcessError, ProbeError, KeyError) as error:
        emit_error("fixture", f"codesign capability fixture failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if device is not None:
            try:
                helper.hdiutil_detach(device, force=True)
            except Exception:
                pass
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "codesign capability freeze probe requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "field probe requires one stable non-root identity before sudo")
        return 80
    field_active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "field process carries root or invalid active group authority")
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

    active_args = [item for group in field_active_groups for item in ("--field-active-group", str(group))]
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

    records = [line[len(MARKER):] for line in completed.stdout.splitlines() if line.startswith(MARKER)]
    if len(records) != 1:
        emit_error("evidence", "missing or ambiguous codesign capability freeze evidence")
        return 81
    evidence = json.loads(records[0])
    required = (
        evidence.get("fieldUID") == field_uid
        and evidence.get("fieldPrimaryGID") == field_gid
        and evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
        and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
        and evidence.get("fieldGroupsContainSigningCapability") is False
        and evidence.get("fieldActiveGroupsContainSigningCapability") is False
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
        and evidence.get("productionAcceptanceClaimed") is False
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        emit_error("evidence", f"codesign capability evidence failed semantic checks: {evidence}")
        return 82
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires one explicit captured active-group vector")
            return 83
        return root_probe(args.field_active_group)
    if args.field_active_group or args.field_active_group_count is not None:
        emit_error("arguments", "root-only active-group arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
