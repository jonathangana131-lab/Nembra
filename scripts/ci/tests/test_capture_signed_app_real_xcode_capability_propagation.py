#!/usr/bin/env python3
"""Classify real-Xcode authority propagation inside the APFS output fixture.

Validation only. This child answers why #3066 reaches xcodebuild but receives
permission errors from Xcode's own DerivedData log stores. It does not weaken
same-UID isolation, detach policy, signing, or production custody.
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

HERE = Path(__file__).resolve().parent
PARENT_PATH = HERE / "test_capture_signed_app_real_xcode_unmount_freeze.py"
MARKER = "NEMBRA_REAL_XCODE_CAPABILITY_DIAGNOSTIC_JSON="
ERROR = "NEMBRA_REAL_XCODE_CAPABILITY_DIAGNOSTIC_ERROR="


def load_parent():
    spec = importlib.util.spec_from_file_location("nembra_real_xcode_unmount_parent", PARENT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load #3066 real-Xcode parent")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def metadata(path: Path) -> dict[str, object]:
    try:
        value = os.lstat(path)
    except OSError as exc:
        return {"path": str(path), "exists": False, "errno": exc.errno}
    return {
        "path": str(path),
        "exists": True,
        "mode": stat.S_IMODE(value.st_mode),
        "uid": value.st_uid,
        "gid": value.st_gid,
        "size": value.st_size,
        "isDirectory": stat.S_ISDIR(value.st_mode),
        "isRegular": stat.S_ISREG(value.st_mode),
        "isSymlink": stat.S_ISLNK(value.st_mode),
    }


def run_python_identity(parent, *, uid: int, gid: int, groups: list[int], target: Path) -> subprocess.CompletedProcess[str]:
    code = r'''
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_bytes(b"capability-control\n")
with p.open("rb") as handle:
    observed = handle.read()
print(json.dumps({
    "uid": os.getuid(),
    "euid": os.geteuid(),
    "gid": os.getgid(),
    "egid": os.getegid(),
    "groups": sorted(os.getgroups()),
    "bytes": observed.decode("utf-8"),
}, sort_keys=True))
'''
    return subprocess.run(
        ["/usr/bin/python3", "-I", "-c", code, str(target)],
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/tmp", "TMPDIR": "/tmp", "LANG": "C", "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        **parent.structured_credentials(uid, gid, groups),
        check=False,
    )


def run_read_probe(parent, *, uid: int, gid: int, groups: list[int], path: Path) -> subprocess.CompletedProcess[str]:
    code = r'''
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    with p.open("rb") as handle:
        handle.read(1)
    outcome = {"readable": True}
except OSError as exc:
    outcome = {"readable": False, "errno": exc.errno}
outcome.update({"uid": os.getuid(), "gid": os.getgid(), "groups": sorted(os.getgroups())})
print(json.dumps(outcome, sort_keys=True))
'''
    return subprocess.run(
        ["/usr/bin/python3", "-I", "-c", code, str(path)],
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/tmp", "TMPDIR": "/tmp", "LANG": "C", "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        **parent.structured_credentials(uid, gid, groups),
        check=False,
    )


def root_probe(package_root: Path) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        print(ERROR + json.dumps({"kind": "environment", "message": "root macOS required"}), file=sys.stderr)
        return 70
    parent = load_parent()
    helper = parent.load_freeze_helper()
    try:
        uid = int(os.environ["SUDO_UID"])
        gid = int(os.environ["SUDO_GID"])
        user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as exc:
        print(ERROR + json.dumps({"kind": "identity", "message": str(exc)}), file=sys.stderr)
        return 71
    account = pwd.getpwuid(uid)
    if uid <= 0 or account.pw_name != user or account.pw_gid != gid:
        print(ERROR + json.dumps({"kind": "identity", "message": "invalid invoking identity"}), file=sys.stderr)
        return 71

    normal_groups = sorted(set(os.getgrouplist(account.pw_name, gid)))
    capability_gid = helper.choose_capability_gid(normal_groups)
    workspace = Path(tempfile.mkdtemp(prefix="nembra-real-xcode-capability.", dir="/private/tmp"))
    image = workspace / "xcode-capability.sparseimage"
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

        cap_control = mountpoint / "capability-control.bin"
        cap = run_python_identity(parent, uid=uid, gid=gid, groups=[capability_gid], target=cap_control)
        if cap.returncode != 0:
            print(ERROR + json.dumps({"kind": "capability-control", "stderr": cap.stderr[-4000:]}), file=sys.stderr)
            return 72
        cap_identity = json.loads(cap.stdout.strip())
        if cap_identity.get("uid") != uid or cap_identity.get("gid") != gid or capability_gid not in cap_identity.get("groups", []):
            print(ERROR + json.dumps({"kind": "capability-control", "identity": cap_identity}), file=sys.stderr)
            return 72

        ordinary_target = mountpoint / "ordinary-control.bin"
        ordinary = run_python_identity(parent, uid=uid, gid=gid, groups=[], target=ordinary_target)
        if ordinary.returncode == 0:
            print(ERROR + json.dumps({"kind": "same-uid-isolation", "message": "ordinary same UID entered protected mount"}), file=sys.stderr)
            return 73

        derived = mountpoint / "DerivedData"
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
        command = [
            "/usr/bin/xcodebuild", "-scheme", "OriginUnmountProof", "-configuration", "Debug",
            "-sdk", "macosx", "-destination", "generic/platform=macOS", "-derivedDataPath", str(derived),
            "CODE_SIGNING_ALLOWED=NO", "COMPILER_INDEX_STORE_ENABLE=NO", "build",
        ]
        build = subprocess.run(
            command,
            cwd=package_root,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            **parent.structured_credentials(uid, gid, [capability_gid]),
            check=False,
        )

        interesting = [workspace, mountpoint, cap_control, derived, derived / "Logs"]
        for category in ("Build", "Localization", "Launch"):
            interesting.append(derived / "Logs" / category)
            interesting.append(derived / "Logs" / category / "LogStoreManifest.plist")
        path_metadata = [metadata(path) for path in interesting]

        manifest_probes: list[dict[str, object]] = []
        for path in (derived / "Logs").glob("*/LogStoreManifest.plist") if (derived / "Logs").is_dir() else []:
            probe = run_read_probe(parent, uid=uid, gid=gid, groups=[capability_gid], path=path)
            record: dict[str, object] = {"path": str(path), "returnCode": probe.returncode}
            if probe.stdout.strip():
                try:
                    record["result"] = json.loads(probe.stdout.strip())
                except json.JSONDecodeError:
                    record["stdout"] = probe.stdout[-1000:]
            if probe.stderr.strip():
                record["stderr"] = probe.stderr[-1000:]
            manifest_probes.append(record)

        output = build.stdout or ""
        permission_signature = "LogStoreManifest.plist" in output and (
            "permission to view it" in output or "Code=1" in output or "Operation not permitted" in output
        )
        if build.returncode == 0:
            classification = "xcode-capability-compatible"
        elif permission_signature and manifest_probes and all(
            bool((item.get("result") or {}).get("readable")) for item in manifest_probes
        ):
            classification = "xcode-internal-authority-propagation-loss"
        elif permission_signature:
            classification = "protected-path-permission-failure"
        else:
            classification = "other-xcode-failure"

        evidence = {
            "schemaVersion": 1,
            "classification": classification,
            "fieldUID": uid,
            "fieldPrimaryGID": gid,
            "normalGroups": normal_groups,
            "capabilityGID": capability_gid,
            "capabilityControlIdentity": cap_identity,
            "ordinaryControlReturnCode": ordinary.returncode,
            "xcodebuildReturnCode": build.returncode,
            "xcodePermissionSignature": permission_signature,
            "pathMetadata": path_metadata,
            "manifestReadProbes": manifest_probes,
            "buildOutputTail": "\n".join(output.splitlines()[-140:]),
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
        print(ERROR + json.dumps({"kind": "environment", "message": "macOS required"}), file=sys.stderr)
        return 80
    parent = load_parent()
    if subprocess.run(["/usr/bin/sudo", "-n", "/usr/bin/true"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        print(ERROR + json.dumps({"kind": "environment", "message": "noninteractive sudo unavailable"}), file=sys.stderr)
        return 80
    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-capability-package-") as temporary:
        package = Path(temporary)
        parent.make_package(package)
        completed = subprocess.run(
            ["/usr/bin/sudo", "-n", "/usr/bin/python3", "-I", str(Path(__file__).resolve()), "--root-probe", "--package-root", str(package)],
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
            print(ERROR + json.dumps({"kind": "evidence", "message": "missing/ambiguous diagnostic record"}), file=sys.stderr)
            return 81
        evidence = json.loads(records[0])
        if evidence.get("physicalAuthorityCreated") is not False:
            return 82
        if evidence.get("ordinaryControlReturnCode") == 0:
            return 82
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    args = parser.parse_args()
    if args.root_probe:
        if args.package_root is None:
            return 83
        return root_probe(args.package_root)
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
