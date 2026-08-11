#!/usr/bin/env python3
"""Probe retained nested-directory-FD authority after a normal APFS detach.

Validation-only child of #3019. The parent mechanically observed that a live
O_DIRECTORY descriptor did not keep non-forced APFS detach busy. This probe asks
the missing authority question: if detach succeeds while that descriptor remains
open, can the escaped same-UID process still create persistent bundle entries via
fd-relative open? No signing, install, device, Bluetooth, Tuya, or physical action
occurs here.
"""
from __future__ import annotations
import argparse, importlib.util, json, os, pwd, shutil, subprocess, sys, tempfile, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
FREEZE_HELPER_PATH = HERE / "test_capture_signed_app_unmount_freeze_probe.py"
MARKER = "NEMBRA_POST_DETACH_DIRFD_JSON="
ERROR_MARKER = "NEMBRA_POST_DETACH_DIRFD_ERROR="

class ProbeError(RuntimeError): pass

def load_helper():
    spec = importlib.util.spec_from_file_location("nembra_unmount_freeze", FREEZE_HELPER_PATH)
    if spec is None or spec.loader is None: raise ProbeError("could not load corrected unmount-freeze helper")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {"kind": kind, "message": message, "physicalAuthorityCreated": False}
    payload.update(extra); print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)

def structured_credentials(uid: int, gid: int, groups: list[int]) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise ProbeError("structured credentials require one non-root uid/gid")
    normalized = sorted({int(group) for group in groups if int(group) != gid})
    if any(group <= 0 for group in normalized):
        raise ProbeError("structured supplementary groups contain root or invalid authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}

def retained_dirfd_code() -> str:
    return r'''
import os
from pathlib import Path
import sys
bundle = Path(sys.argv[1]); bundle.mkdir(parents=True, exist_ok=True)
(bundle / "accepted.bin").write_bytes(b"ORIGINAL_BUILD_OUTPUT\n")
dirfd = os.open(bundle, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0))
print("READY", flush=True)
try:
    if sys.stdin.buffer.read(1) != b"W": raise SystemExit(91)
    fd = os.open("late-entry.bin", os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600, dir_fd=dirfd)
    try: os.write(fd, b"DIRFD_POST_LOCK_WRITE\n"); os.fsync(fd)
    finally: os.close(fd)
    print("WROTE", flush=True)
    command = sys.stdin.buffer.read(1)
    if command == b"P":
        try:
            fd = os.open("post-detach-entry.bin", os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600, dir_fd=dirfd)
            try: os.write(fd, b"DIRFD_POST_DETACH_WRITE\n"); os.fsync(fd)
            finally: os.close(fd)
            print("POSTDETACH_OK", flush=True)
        except OSError as error:
            print(f"POSTDETACH_ERR:{error.errno}:{error.strerror}", flush=True)
        command = sys.stdin.buffer.read(1)
    if command != b"C": raise SystemExit(92)
finally: os.close(dirfd)
print("CLOSED", flush=True)
'''

def read_line(process: subprocess.Popen[str]) -> str:
    if process.stdout is None: raise ProbeError("writer stdout unavailable")
    line = process.stdout.readline()
    if line: return line.strip()
    stderr = process.stderr.read() if process.stderr is not None else ""
    raise ProbeError(f"writer exited {process.poll()}: {stderr.strip()}")

def send(process: subprocess.Popen[str], command: str) -> None:
    if process.stdin is None: raise ProbeError("writer stdin unavailable")
    process.stdin.write(command); process.stdin.flush()

def detach_is_resource_busy(completed: subprocess.CompletedProcess[str]) -> bool:
    if completed.returncode == 0:
        return False
    diagnostic = ((completed.stdout or "") + "\n" + (completed.stderr or "")).casefold()
    return "resource busy" in diagnostic

def root_probe(field_uid_claim: int, field_gid_claim: int, field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "root probe requires sudo on real macOS"); return 70
    helper = load_helper()
    try: uid, gid, user = int(os.environ["SUDO_UID"]), int(os.environ["SUDO_GID"]), os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error: emit_error("identity", str(error)); return 71
    if uid != field_uid_claim or gid != field_gid_claim:
        emit_error("identity", "sudo identity differs from exact pre-sudo invoking uid/gid"); return 71
    account = pwd.getpwuid(uid)
    if uid <= 0 or gid <= 0 or account.pw_name != user or account.pw_gid != gid:
        emit_error("identity", "sudo identity mismatch"); return 71
    normal_groups = sorted(set(os.getgrouplist(account.pw_name, gid)))
    if any(group <= 0 for group in normal_groups):
        emit_error("identity", "field directory-service groups contain root or invalid authority"); return 71
    if len(field_active_groups) != len(set(field_active_groups)) or any(group <= 0 for group in field_active_groups):
        emit_error("identity", "captured active supplementary-group vector is invalid"); return 71
    if gid in field_active_groups:
        emit_error("identity", "captured active supplementary groups must keep the primary gid separate"); return 71
    if not set(field_active_groups).issubset(set(normal_groups)):
        emit_error("identity", "captured active supplementary groups exceed directory-service membership"); return 71
    capability_gid = helper.choose_capability_gid(normal_groups)
    if capability_gid in field_active_groups:
        emit_error("identity", "fresh capability gid overlaps active field authority"); return 71
    capability_groups = sorted(set(field_active_groups) | {capability_gid})
    workspace = Path(tempfile.mkdtemp(prefix="nembra-post-detach-dirfd.", dir="/private/tmp"))
    image, mountpoint = workspace / "origin.sparseimage", workspace / "mount"; mountpoint.mkdir()
    os.chown(workspace, 0, capability_gid); os.chmod(workspace, 0o710)
    device = None; writer = None
    try:
        helper.hdiutil_create(image); device = helper.hdiutil_attach(image, mountpoint, readonly=False)
        os.chown(mountpoint, 0, capability_gid); os.chmod(mountpoint, 0o770)
        bundle = mountpoint / "DerivedData/Build/Products/Debug-iphoneos/Nembra Capture.app"
        env = {"HOME": account.pw_dir, "USER": account.pw_name, "LOGNAME": account.pw_name, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": "/tmp", "LANG": "C", "LC_ALL": "C"}
        try:
            writer = subprocess.Popen(["/usr/bin/python3", "-I", "-c", retained_dirfd_code(), str(bundle)], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True, **structured_credentials(uid, gid, capability_groups))
        except (OSError, subprocess.SubprocessError, ProbeError) as error:
            emit_error("credential-launch", f"directory-FD writer launch failed: {type(error).__name__}: {error}"); return 72
        if read_line(writer) != "READY": raise ProbeError("writer did not arm")
        os.chown(mountpoint, 0, 0); os.chmod(mountpoint, 0o700)
        try:
            fresh = subprocess.run(["/bin/sh", "-c", 'printf x > "$1"', "sh", str(bundle / "fresh-path-entry.bin")], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **structured_credentials(uid, gid, field_active_groups), check=False)
        except (OSError, subprocess.SubprocessError, ProbeError) as error:
            emit_error("credential-launch", f"field negative-control launch failed: {type(error).__name__}: {error}"); return 72
        if fresh.returncode == 0: emit_error("pathname-isolation", "fresh path write survived lock"); return 73
        send(writer, "W")
        if read_line(writer) != "WROTE": raise ProbeError("post-lock dirfd write not demonstrated")
        first_detach = helper.hdiutil_detach(device)
        detach_text = ((first_detach.stdout or "") + "\n" + (first_detach.stderr or "")).strip()
        detach_was_busy = detach_is_resource_busy(first_detach)
        if first_detach.returncode != 0 and not detach_was_busy:
            emit_error(
                "detach-classification",
                "first non-forced detach failed for a non-busy reason",
                firstDetachReturnCode=first_detach.returncode,
                firstDetachOutput=detach_text,
            )
            return 74
        post_result = "NOT_ATTEMPTED_BUSY_DETACH"
        if detach_was_busy:
            send(writer, "C")
            if read_line(writer) != "CLOSED": raise ProbeError("writer did not close")
            writer.wait(timeout=5)
            closed_detach = helper.hdiutil_detach(device)
            if closed_detach.returncode != 0: emit_error("quiescence", "detach remained busy after dirfd close"); return 75
            device = None
        else:
            device = None; send(writer, "P"); post_result = read_line(writer); send(writer, "C")
            if read_line(writer) != "CLOSED": raise ProbeError("writer did not close after post-detach probe")
            writer.wait(timeout=5)
        if writer.returncode != 0: emit_error("writer", f"writer exited {writer.returncode}"); return 76
        device = helper.hdiutil_attach(image, mountpoint, readonly=True)
        frozen = mountpoint / "DerivedData/Build/Products/Debug-iphoneos/Nembra Capture.app"
        if (frozen / "late-entry.bin").read_bytes() != b"DIRFD_POST_LOCK_WRITE\n": emit_error("readonly-remount", "pre-detach bytes changed"); return 77
        post_path = frozen / "post-detach-entry.bin"; persisted = post_path.exists()
        if post_result == "POSTDETACH_OK" or persisted:
            emit_error("authority-survived-detach", "retained dirfd preserved fd-relative mutation authority after detach", detachOutput=detach_text, postDetachResult=post_result, postDetachPersisted=persisted)
            return 78
        if not detach_was_busy and not post_result.startswith("POSTDETACH_ERR:"):
            emit_error("post-detach-probe", "ambiguous result", result=post_result); return 79
        root_create = subprocess.run(["/bin/sh", "-c", 'printf x > "$1"', "sh", str(frozen / "root-after-freeze.bin")], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        try:
            former = subprocess.run(["/bin/sh", "-c", 'printf x > "$1"', "sh", str(frozen / "cap-after-freeze.bin")], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **structured_credentials(uid, gid, capability_groups), check=False)
        except (OSError, subprocess.SubprocessError, ProbeError) as error:
            emit_error("credential-launch", f"former-capability negative-control launch failed: {type(error).__name__}: {error}"); return 72
        if root_create.returncode == 0 or former.returncode == 0: emit_error("readonly-remount", "read-only remount admitted a new entry"); return 80
        evidence = {"schemaVersion": 2, "fieldUID": uid, "fieldPrimaryGID": gid, "fieldActiveSupplementaryGroups": field_active_groups, "fieldActiveGroupsSubsetOfDirectoryService": set(field_active_groups).issubset(set(normal_groups)), "fieldActiveGroupsContainCapability": capability_gid in field_active_groups, "capabilityGID": capability_gid, "normalGroupsContainCapability": capability_gid in normal_groups, "freshPathAttackReturnCode": fresh.returncode, "firstDetachReturnCode": first_detach.returncode, "firstDetachOutput": detach_text, "detachWasBusy": detach_was_busy, "postDetachResult": post_result, "postDetachPersisted": persisted, "rootReadonlyCreateReturnCode": root_create.returncode, "formerCapabilityReadonlyCreateReturnCode": former.returncode, "physicalAuthorityCreated": False}
        print(MARKER + json.dumps(evidence, sort_keys=True)); return 0
    except (ProbeError, subprocess.TimeoutExpired, OSError, subprocess.SubprocessError) as error: emit_error("probe", str(error)); return 81
    finally:
        if writer is not None and writer.poll() is None:
            try: send(writer, "C")
            except Exception: pass
            try: writer.terminate(); writer.wait(timeout=2)
            except Exception:
                try: writer.kill(); writer.wait()
                except Exception: pass
        if device is not None: helper.hdiutil_detach(device, force=True)
        shutil.rmtree(workspace, ignore_errors=True)

def parent_probe() -> int:
    if sys.platform != "darwin": emit_error("environment", "requires macOS"); return 82
    field_uid, field_euid = os.getuid(), os.geteuid()
    field_gid, field_egid = os.getgid(), os.getegid()
    if field_uid <= 0 or field_gid <= 0 or field_uid != field_euid or field_gid != field_egid:
        emit_error("identity", "field parent requires one stable non-root invoking uid/gid"); return 82
    field_active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "field parent carries root or invalid active supplementary authority"); return 82
    active_group_args = [item for group in field_active_groups for item in ("--field-active-group", str(group))]
    completed = subprocess.run(["/usr/bin/sudo", "-n", "/usr/bin/python3", "-I", str(Path(__file__).resolve()), "--root-probe", "--field-uid", str(field_uid), "--field-primary-gid", str(field_gid), "--field-active-group-count", str(len(field_active_groups)), *active_group_args], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    sys.stdout.write(completed.stdout); sys.stderr.write(completed.stderr)
    if completed.returncode != 0: return completed.returncode
    records = [line[len(MARKER):] for line in completed.stdout.splitlines() if line.startswith(MARKER)]
    if len(records) != 1: emit_error("evidence", "missing/ambiguous evidence"); return 83
    e = json.loads(records[0])
    busy_evidence = e.get("detachWasBusy") is True and "resource busy" in str(e.get("firstDetachOutput", "")).casefold()
    safe = e.get("fieldUID") == field_uid and e.get("fieldPrimaryGID") == field_gid and e.get("fieldActiveSupplementaryGroups") == field_active_groups and e.get("fieldActiveGroupsSubsetOfDirectoryService") is True and e.get("fieldActiveGroupsContainCapability") is False and e.get("freshPathAttackReturnCode") != 0 and e.get("postDetachPersisted") is False and e.get("rootReadonlyCreateReturnCode") != 0 and e.get("formerCapabilityReadonlyCreateReturnCode") != 0 and e.get("normalGroupsContainCapability") is False and e.get("physicalAuthorityCreated") is False and (busy_evidence or (e.get("detachWasBusy") is False and str(e.get("postDetachResult", "")).startswith("POSTDETACH_ERR:")))
    if not safe: emit_error("evidence", f"semantic checks failed: {e}"); return 84
    return 0

def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--root-probe", action="store_true"); parser.add_argument("--field-uid", type=int); parser.add_argument("--field-primary-gid", type=int); parser.add_argument("--field-active-group", action="append", type=int, default=[]); parser.add_argument("--field-active-group-count", type=int); args = parser.parse_args()
    if args.root_probe:
        if args.field_uid is None or args.field_primary_gid is None or args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires exact pre-sudo uid/gid and one counted active supplementary-group vector"); return 85
        return root_probe(args.field_uid, args.field_primary_gid, args.field_active_group)
    if args.field_uid is not None or args.field_primary_gid is not None or args.field_active_group or args.field_active_group_count is not None:
        emit_error("arguments", "root-only identity arguments are unavailable in field parent mode"); return 85
    return parent_probe()
if __name__ == "__main__": raise SystemExit(main())
