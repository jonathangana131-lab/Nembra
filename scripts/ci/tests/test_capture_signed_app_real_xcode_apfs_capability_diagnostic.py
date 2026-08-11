#!/usr/bin/env python3
"""Classify real-Xcode access to the ephemeral APFS capability volume.

Validation only. The parent real-Xcode freeze probe reached xcodebuild but failed
opening DerivedData log-store manifests before any detach verdict was possible.
This diagnostic keeps the same field UID / primary GID / one-run supplementary
capability GID and distinguishes:
  * whether those exact credentials can mutate the mounted volume directly;
  * whether an ordinary same-UID process without the capability is excluded;
  * whether real xcodebuild can use the same DerivedData root;
  * what uid/gid/mode/ACL metadata exists around any failing log-store path;
  * whether the exact capability credentials can still access those paths after
    xcodebuild returns.

A classified result is architecture evidence only. It never signs, installs,
launches, scans, or talks to a device.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Any

HERE = Path(__file__).resolve().parent
PARENT_PROBE = HERE / "test_capture_signed_app_real_xcode_unmount_freeze.py"
MARKER = "NEMBRA_REAL_XCODE_APFS_CAPABILITY_DIAGNOSTIC="
ERROR = "NEMBRA_REAL_XCODE_APFS_CAPABILITY_DIAGNOSTIC_ERROR="


class DiagnosticError(RuntimeError):
    pass


def load_parent():
    spec = importlib.util.spec_from_file_location("nembra_real_xcode_apfs_parent", PARENT_PROBE)
    if spec is None or spec.loader is None:
        raise DiagnosticError("could not load exact parent real-Xcode probe")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str) -> int:
    print(ERROR + json.dumps({"kind": kind, "message": message, "physicalAuthorityCreated": False}, sort_keys=True), file=sys.stderr)
    return 70


def run_as(uid: int, gid: int, groups: list[int], command: list[str], *, env: dict[str, str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        user=uid,
        group=gid,
        extra_groups=sorted(set(groups)),
        check=False,
    )


def stat_record(path: Path) -> dict[str, Any]:
    record: dict[str, Any] = {"path": str(path), "exists": False}
    try:
        metadata = path.lstat()
    except OSError as error:
        record["error"] = f"{type(error).__name__}:{error.errno}:{error}"
        return record
    record.update(
        {
            "exists": True,
            "mode": oct(stat.S_IMODE(metadata.st_mode)),
            "uid": metadata.st_uid,
            "gid": metadata.st_gid,
            "inode": metadata.st_ino,
            "device": metadata.st_dev,
            "isDirectory": stat.S_ISDIR(metadata.st_mode),
            "isRegular": stat.S_ISREG(metadata.st_mode),
            "isSymlink": stat.S_ISLNK(metadata.st_mode),
        }
    )
    acl = subprocess.run(
        ["/bin/ls", "-lde", str(path)],
        env={"PATH": "/usr/bin:/bin", "HOME": "/tmp", "LANG": "C", "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    record["lsReturnCode"] = acl.returncode
    record["lsOutput"] = (acl.stdout + acl.stderr)[-2000:]
    return record


def bounded_tree(root: Path, *, limit: int = 120) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if not root.exists():
        return records
    for current, directories, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        records.append(stat_record(current_path))
        if len(records) >= limit:
            break
        relative_depth = len(current_path.relative_to(root).parts)
        if relative_depth >= 4:
            directories[:] = []
        for name in sorted(files):
            records.append(stat_record(current_path / name))
            if len(records) >= limit:
                break
        if len(records) >= limit:
            break
    return records


def write_probe_code() -> str:
    return (
        "import os,sys\n"
        "p=sys.argv[1]\n"
        "try:\n"
        " os.makedirs(p, exist_ok=True)\n"
        " f=os.path.join(p,'probe.txt')\n"
        " with open(f,'a',encoding='utf-8') as h: h.write('probe\\n')\n"
        " print('WRITE_OK',os.geteuid(),os.getegid(),*os.getgroups())\n"
        "except BaseException as e:\n"
        " print('WRITE_FAIL',type(e).__name__,getattr(e,'errno',None),str(e))\n"
        " raise\n"
    )


def read_probe_code() -> str:
    return (
        "import os,sys\n"
        "p=sys.argv[1]\n"
        "try:\n"
        " with open(p,'rb') as h: b=h.read(64)\n"
        " print('READ_OK',len(b),os.geteuid(),os.getegid(),*os.getgroups())\n"
        "except BaseException as e:\n"
        " print('READ_FAIL',type(e).__name__,getattr(e,'errno',None),str(e))\n"
        " raise\n"
    )


def root_probe(package_root: Path) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        return emit_error("environment", "root diagnostic requires sudo on real macOS")
    parent = load_parent()
    helper = parent.load_freeze_helper()
    try:
        uid = int(os.environ["SUDO_UID"])
        gid = int(os.environ["SUDO_GID"])
        user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        return emit_error("identity", f"missing sudo invoking identity: {error}")
    if uid <= 0 or gid <= 0:
        return emit_error("identity", "diagnostic requires non-root invoking uid/gid")
    account = pwd.getpwuid(uid)
    if account.pw_name != user or account.pw_gid != gid:
        return emit_error("identity", "sudo identity does not match local account database")

    normal_groups = sorted(set(os.getgrouplist(account.pw_name, gid)))
    if 0 in normal_groups:
        return emit_error("identity", "normal field identity unexpectedly includes gid 0")
    capability_gid = helper.choose_capability_gid(normal_groups)
    capability_groups = [capability_gid]
    ordinary_groups: list[int] = []
    environment = {
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
            environment[name] = value

    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-apfs-capability.", dir="/private/tmp"))
    image = workspace / "diagnostic.sparseimage"
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

        identity = run_as(uid, gid, capability_groups, ["/usr/bin/id", "-a"], env=environment)
        if identity.returncode != 0:
            return emit_error("credential-launch", "capability identity could not execute id")

        direct_root = mountpoint / "DirectCapabilityProbe"
        direct_before = run_as(
            uid,
            gid,
            capability_groups,
            ["/usr/bin/python3", "-I", "-c", write_probe_code(), str(direct_root)],
            env=environment,
        )
        ordinary_before = run_as(
            uid,
            gid,
            ordinary_groups,
            ["/usr/bin/python3", "-I", "-c", write_probe_code(), str(mountpoint / "OrdinaryProbe")],
            env=environment,
        )
        if direct_before.returncode != 0:
            return emit_error("capability-volume", "exact capability credentials cannot directly write mounted volume")
        if ordinary_before.returncode == 0:
            return emit_error("same-uid-isolation", "ordinary same-UID credentials can write mounted volume")

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
        build = run_as(uid, gid, capability_groups, command, env=environment, cwd=package_root)

        candidate_directories = [
            derived / "Logs" / "Build",
            derived / "Logs",
            derived,
            mountpoint,
        ]
        nearest = next((path for path in candidate_directories if path.is_dir() and not path.is_symlink()), mountpoint)
        direct_after = run_as(
            uid,
            gid,
            capability_groups,
            ["/usr/bin/python3", "-I", "-c", write_probe_code(), str(nearest / "DirectAfterXcode")],
            env=environment,
        )
        ordinary_after = run_as(
            uid,
            gid,
            ordinary_groups,
            ["/usr/bin/python3", "-I", "-c", write_probe_code(), str(nearest / "OrdinaryAfterXcode")],
            env=environment,
        )

        manifests = sorted(derived.glob("Logs/*/LogStoreManifest.plist")) if derived.exists() else []
        manifest_probes: list[dict[str, Any]] = []
        for manifest in manifests[:12]:
            capability_read = run_as(
                uid,
                gid,
                capability_groups,
                ["/usr/bin/python3", "-I", "-c", read_probe_code(), str(manifest)],
                env=environment,
            )
            ordinary_read = run_as(
                uid,
                gid,
                ordinary_groups,
                ["/usr/bin/python3", "-I", "-c", read_probe_code(), str(manifest)],
                env=environment,
            )
            manifest_probes.append(
                {
                    "path": str(manifest),
                    "capabilityReadReturnCode": capability_read.returncode,
                    "capabilityReadOutput": (capability_read.stdout + capability_read.stderr)[-1500:],
                    "ordinaryReadReturnCode": ordinary_read.returncode,
                    "ordinaryReadOutput": (ordinary_read.stdout + ordinary_read.stderr)[-1500:],
                }
            )

        evidence = {
            "schemaVersion": 1,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "normalGroups": normal_groups,
            "capabilityGID": capability_gid,
            "normalGroupsContainCapability": capability_gid in normal_groups,
            "capabilityIdentity": identity.stdout.strip(),
            "directBeforeReturnCode": direct_before.returncode,
            "directBeforeOutput": (direct_before.stdout + direct_before.stderr)[-2000:],
            "ordinaryBeforeReturnCode": ordinary_before.returncode,
            "ordinaryBeforeOutput": (ordinary_before.stdout + ordinary_before.stderr)[-2000:],
            "xcodebuildReturnCode": build.returncode,
            "xcodebuildOutputTail": "\n".join(build.stdout.splitlines()[-140:]) + "\n" + "\n".join(build.stderr.splitlines()[-80:]),
            "nearestPostXcodeDirectory": str(nearest),
            "directAfterReturnCode": direct_after.returncode,
            "directAfterOutput": (direct_after.stdout + direct_after.stderr)[-2000:],
            "ordinaryAfterReturnCode": ordinary_after.returncode,
            "ordinaryAfterOutput": (ordinary_after.stdout + ordinary_after.stderr)[-2000:],
            "manifestProbes": manifest_probes,
            "derivedTree": bounded_tree(derived),
            "mountpoint": stat_record(mountpoint),
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
        return emit_error("environment", "diagnostic requires macOS")
    sudo = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sudo.returncode != 0:
        return emit_error("environment", "runner lacks noninteractive sudo")

    parent = load_parent()
    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-apfs-capability-package-") as temporary:
        package = Path(temporary)
        parent.make_package(package)
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
        records = [line[len(MARKER):] for line in completed.stdout.splitlines() if line.startswith(MARKER)]
        if len(records) != 1:
            return emit_error("evidence", "missing or ambiguous capability diagnostic record")
        evidence = json.loads(records[0])
        required = (
            evidence.get("directBeforeReturnCode") == 0
            and evidence.get("ordinaryBeforeReturnCode") != 0
            and evidence.get("directAfterReturnCode") == 0
            and evidence.get("ordinaryAfterReturnCode") != 0
            and evidence.get("normalGroupsContainCapability") is False
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            return emit_error("evidence", f"diagnostic authority controls failed: {evidence}")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    args = parser.parse_args()
    if args.root_probe:
        if args.package_root is None:
            return emit_error("arguments", "--package-root required")
        return root_probe(args.package_root)
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
