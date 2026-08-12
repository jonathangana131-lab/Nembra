#!/usr/bin/env python3
"""Validation-only APFS ownership-enforced pathname revocation probe.

The dedicated-UID retained-authority matrix reached its real authority oracle on
macOS and proved that the current default APFS attach shape does not let root
revoke the former build identity's *fresh pathname* authority merely by chowning
and chmodding the mounted volume root. Production currently relies on exactly
that pre-detach transition.

This probe changes only one filesystem condition: attach the sparse APFS image
with ``hdiutil attach -owners on``. It then requires:
- a fresh dedicated UID/GID can create compiler-output bytes while owning the
  mounted volume root;
- root can observe the exact granted ownership/mode;
- root chown(0,0)+chmod(0700) is reflected by lstat;
- after that transition the same former build identity cannot create a fresh
  pathname or update the existing pathname by name;
- the forbidden fresh path does not appear;
- normal, non-forced detach succeeds.

This is architecture evidence only. It does not build/sign/install Nembra, touch
private Tuya inputs, access a keychain, scan Bluetooth, or create physical authority.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PARENT_PATH = HERE / "test_capture_signed_app_real_xcode_dedicated_uid_freeze.py"
MARKER = "NEMBRA_APFS_OWNERS_ON_REVOCATION_JSON="
ERROR_MARKER = "NEMBRA_APFS_OWNERS_ON_REVOCATION_ERROR="


class ProbeError(RuntimeError):
    pass


def load_parent():
    spec = importlib.util.spec_from_file_location("nembra_apfs_owners_parent", PARENT_PATH)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load accepted dedicated-UID identity helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "kind": kind,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def metadata(path: Path) -> dict[str, int]:
    value = path.lstat()
    return {
        "uid": value.st_uid,
        "gid": value.st_gid,
        "mode": stat.S_IMODE(value.st_mode),
    }


def attach_owners_on(image: Path, mountpoint: Path) -> str:
    completed = subprocess.run(
        [
            "/usr/bin/hdiutil",
            "attach",
            "-plist",
            "-nobrowse",
            "-owners",
            "on",
            "-mountpoint",
            str(mountpoint),
            str(image),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise ProbeError(
            "ownership-enforced APFS attach failed: "
            + completed.stderr.decode("utf-8", errors="replace")[-3000:]
        )
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise ProbeError(f"ownership-enforced attach emitted malformed plist: {error}") from error
    for entity in payload.get("system-entities", []):
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise ProbeError("ownership-enforced attach returned no exact mounted device")


def detach(device: str, *, force: bool = False) -> subprocess.CompletedProcess[str]:
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


def child_run(parent, uid: int, gid: int, argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **parent.structured_credentials(uid, gid, []),
    )


def root_probe(field_uid: int, field_gid: int) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "APFS owners-on revocation probe requires sudo on real macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing exact sudo invoking identity: {error}")
        return 71
    if sudo_uid != field_uid or sudo_gid != field_gid or field_uid <= 0 or field_gid <= 0:
        emit_error(
            "identity",
            "root probe is not exact-bound to the pre-sudo field UID/GID",
            sudoUID=sudo_uid,
            sudoGID=sudo_gid,
            fieldUID=field_uid,
            fieldPrimaryGID=field_gid,
        )
        return 71

    parent = load_parent()
    workspace = Path(tempfile.mkdtemp(prefix="nembra-apfs-owners-on.", dir="/private/tmp"))
    image = workspace / "CompilerOutput.sparseimage"
    mountpoint = workspace / "mount"
    home = workspace / "home"
    build_name = f"nembraowners{os.getpid()}"
    build_uid: int | None = None
    device: str | None = None
    identity_created = False
    evidence: dict[str, object] = {
        "schemaVersion": 1,
        "fieldUID": field_uid,
        "fieldPrimaryGID": field_gid,
        "attachOwners": "on",
        "physicalAuthorityCreated": False,
    }
    try:
        build_uid = parent.choose_ephemeral_id()
        build_gid = build_uid
        if build_uid == field_uid or build_gid == field_gid:
            raise ProbeError("fresh dedicated identity overlaps field UID/GID")

        mountpoint.mkdir()
        home.mkdir()
        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        os.chown(home, build_uid, build_gid)
        os.chmod(home, 0o700)
        parent.create_local_build_identity(build_name, build_uid, build_gid, home)
        identity_created = True
        evidence["buildUser"] = build_name
        evidence["buildUID"] = build_uid
        evidence["buildPrimaryGID"] = build_gid

        create = subprocess.run(
            [
                "/usr/bin/hdiutil",
                "create",
                "-quiet",
                "-size",
                "256m",
                "-type",
                "SPARSE",
                "-fs",
                "APFS",
                "-volname",
                "NembraOwnersOnProbe",
                str(image),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if create.returncode != 0:
            raise ProbeError(f"APFS image creation failed: {create.stderr[-3000:]}")

        device = attach_owners_on(image, mountpoint)
        evidence["device"] = device
        mount_lines = subprocess.run(
            ["/sbin/mount"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        ).stdout.splitlines()
        evidence["mountLine"] = next((line for line in mount_lines if str(mountpoint) in line), "")

        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)
        evidence["grantedMountMetadata"] = metadata(mountpoint)
        if evidence["grantedMountMetadata"] != {"uid": build_uid, "gid": build_gid, "mode": 0o700}:
            raise ProbeError("root did not observe exact build-owned mounted-root metadata")

        admitted = mountpoint / "compiler-output.txt"
        initial = child_run(parent, build_uid, build_gid, ["/usr/bin/touch", str(admitted)])
        evidence["initialBuildWriteReturnCode"] = initial.returncode
        evidence["initialBuildWriteStderr"] = initial.stderr[-1200:]
        if initial.returncode != 0 or not admitted.exists():
            raise ProbeError("dedicated build identity could not create initial output with ownership enabled")

        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        evidence["revokedMountMetadata"] = metadata(mountpoint)
        if evidence["revokedMountMetadata"] != {"uid": 0, "gid": 0, "mode": 0o700}:
            raise ProbeError("root-owned pathname revocation was not reflected by mounted-root lstat")

        forbidden = mountpoint / "former-build-fresh-path.txt"
        fresh_attack = child_run(parent, build_uid, build_gid, ["/usr/bin/touch", str(forbidden)])
        existing_attack = child_run(parent, build_uid, build_gid, ["/usr/bin/touch", str(admitted)])
        evidence["freshPathAttackReturnCode"] = fresh_attack.returncode
        evidence["freshPathAttackStderr"] = fresh_attack.stderr[-1200:]
        evidence["existingPathAttackReturnCode"] = existing_attack.returncode
        evidence["existingPathAttackStderr"] = existing_attack.stderr[-1200:]
        evidence["forbiddenFreshPathExists"] = forbidden.exists()

        if fresh_attack.returncode == 0 or forbidden.exists():
            raise ProbeError("former build identity retained fresh pathname creation after owners-on revocation")
        if existing_attack.returncode == 0:
            raise ProbeError("former build identity retained existing-path mutation after owners-on revocation")

        normal_detach = detach(device)
        evidence["normalDetachReturnCode"] = normal_detach.returncode
        evidence["normalDetachOutput"] = ((normal_detach.stdout or "") + "\n" + (normal_detach.stderr or ""))[-3000:]
        if normal_detach.returncode != 0:
            raise ProbeError("ownership-enforced APFS image did not detach normally after revocation")
        device = None

        evidence["accepted"] = True
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, ProbeError, subprocess.SubprocessError) as error:
        evidence["accepted"] = False
        emit_error("probe", f"ownership-enforced revocation failed: {type(error).__name__}: {error}", evidence=evidence)
        return 79
    finally:
        if device is not None:
            detach(device, force=True)
        if identity_created:
            parent.remove_local_build_identity(build_name, build_uid)
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "APFS owners-on revocation probe requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent requires one stable non-root invoking UID/GID")
        return 80
    if subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode != 0:
        emit_error("environment", "runner lacks noninteractive sudo required for validation")
        return 80
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
            "--field-uid",
            str(field_uid),
            "--field-primary-gid",
            str(field_gid),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    return completed.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-primary-gid", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.field_uid is None or args.field_primary_gid is None:
            emit_error("arguments", "root probe requires exact pre-sudo UID/GID")
            return 83
        return root_probe(args.field_uid, args.field_primary_gid)
    if args.field_uid is not None or args.field_primary_gid is not None:
        emit_error("arguments", "root-only identity arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
