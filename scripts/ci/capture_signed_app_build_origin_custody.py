#!/usr/bin/env python3
"""Bind the physical install subject to exact compiler output through an APFS freeze.

The field user never receives writable compiler-output pathname authority. Root creates
one ephemeral local build identity, mounts a private APFS sparse image writable only by
that identity, runs the guarded build there, removes fresh pathname authority when the
build returns, and requires a normal non-forced detach before compiler-output bytes can
become authoritative. The app is fingerprinted only from a read-only remount, then copied
into the canonical root-owned install stage.

This helper is executed from exact accepted Git bytes by the field installer. It creates
no device, Bluetooth, Tuya, telemetry, command, or physical authority by itself.
"""

from __future__ import annotations

import argparse
import base64
import errno
import grp
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Iterable, Sequence

WORKSPACE_PREFIX = "nembra-authenticated-capture-origin."
STAGE_PREFIX = "nembra-authenticated-capture-install."
IMAGE_NAME = "compiler-output.sparseimage"
MOUNT_NAME = "compiler-output"
APFS_VOLUME_NAME = "NembraCaptureOrigin"
DEFAULT_APP_RELATIVE = Path("Build/Products/Debug-iphoneos/Nembra Capture.app")
DERIVED_PLACEHOLDER = "__NEMBRA_PROTECTED_DERIVED__"
GROUP_ATTESTOR_MARKER = "NEMBRA_BUILD_IDENTITY_GROUPS="


class BuildOriginCustodyError(RuntimeError):
    pass


def _require_real_private_tmp() -> Path:
    root = Path("/private/tmp")
    try:
        metadata = root.lstat()
    except OSError as error:
        raise BuildOriginCustodyError("/private/tmp is unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise BuildOriginCustodyError("/private/tmp is not one real directory")
    return root


def _invoking_identity() -> tuple[str, int, int, str, tuple[int, ...]]:
    if os.geteuid() != 0:
        raise BuildOriginCustodyError("build-origin custody must run as root through sudo")
    raw_uid = os.environ.get("SUDO_UID", "")
    raw_gid = os.environ.get("SUDO_GID", "")
    sudo_user = os.environ.get("SUDO_USER", "")
    if not raw_uid.isdigit() or not raw_gid.isdigit() or not sudo_user:
        raise BuildOriginCustodyError("sudo did not expose one invoking-user identity")
    uid = int(raw_uid)
    gid = int(raw_gid)
    if uid <= 0:
        raise BuildOriginCustodyError("root may not be the field-build invoking identity")
    if gid <= 0:
        raise BuildOriginCustodyError("root group may not be the field-build invoking primary group")
    account = pwd.getpwuid(uid)
    if account.pw_name != sudo_user or account.pw_gid != gid:
        raise BuildOriginCustodyError("sudo invoking identity does not match the local account database")
    groups = tuple(sorted(set(os.getgrouplist(account.pw_name, gid))))
    if any(value <= 0 for value in groups):
        raise BuildOriginCustodyError("invoking-user supplementary groups contain root or invalid authority")
    return account.pw_name, uid, gid, account.pw_dir, groups


def _structured_credentials(
    uid: int,
    gid: int,
    extra_groups: Iterable[int],
) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise BuildOriginCustodyError("structured child credentials require non-root user and group identity")
    normalized = sorted({int(value) for value in extra_groups if int(value) != gid})
    if any(value <= 0 for value in normalized):
        raise BuildOriginCustodyError("structured child supplementary groups contain invalid authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def _attest_build_identity_groups(
    name: str,
    uid: int,
    gid: int,
    field_groups: Sequence[int],
    environment: dict[str, str],
    cwd: Path,
) -> tuple[int, ...]:
    baseline = tuple(sorted(set(os.getgrouplist(name, gid))))
    if gid not in baseline or any(value <= 0 for value in baseline):
        raise BuildOriginCustodyError("fresh build Directory Services group baseline is invalid")
    if uid <= 0 or gid <= 0 or uid == os.getuid():
        raise BuildOriginCustodyError("fresh build identity is not isolated from root authority")

    child_source = (
        "import json,os,pwd;"
        "print('NEMBRA_BUILD_IDENTITY_GROUPS='+json.dumps({"
        "'uid':os.getuid(),'euid':os.geteuid(),'gid':os.getgid(),'egid':os.getegid(),"
        "'groups':sorted(set(os.getgroups())),'user':pwd.getpwuid(os.getuid()).pw_name},sort_keys=True))"
    )
    completed = subprocess.run(
        ["/usr/bin/python3", "-B", "-I", "-c", child_source],
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **_structured_credentials(uid, gid, ()),
    )
    records = [
        line[len(GROUP_ATTESTOR_MARKER):]
        for line in (completed.stdout or "").splitlines()
        if line.startswith(GROUP_ATTESTOR_MARKER)
    ]
    if completed.returncode != 0 or len(records) != 1:
        detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
        raise BuildOriginCustodyError(
            "could not attest effective dedicated-build credentials"
            + (f": {detail[-1200:]}" if detail else "")
        )
    try:
        payload = json.loads(records[0])
    except json.JSONDecodeError as error:
        raise BuildOriginCustodyError("dedicated-build credential attestor emitted malformed JSON") from error
    if not isinstance(payload, dict):
        raise BuildOriginCustodyError("dedicated-build credential attestor emitted no object")

    identity_exact = (
        payload.get("uid") == uid
        and payload.get("euid") == uid
        and payload.get("gid") == gid
        and payload.get("egid") == gid
        and payload.get("user") == name
    )
    raw_groups = payload.get("groups")
    if not isinstance(raw_groups, list) or any(not isinstance(value, int) for value in raw_groups):
        raise BuildOriginCustodyError("dedicated-build credential attestor emitted an invalid group vector")
    effective = {value for value in raw_groups if value != gid}
    expected = {value for value in baseline if value != gid}
    field_only = set(int(value) for value in field_groups).difference(baseline)
    if not identity_exact:
        raise BuildOriginCustodyError("dedicated-build child did not retain its exact UID/GID identity")
    if effective != expected:
        raise BuildOriginCustodyError(
            "dedicated-build child effective groups diverged from its Directory Services baseline"
        )
    if effective.intersection(field_only):
        raise BuildOriginCustodyError("field-only group authority leaked into the dedicated-build child")
    return baseline


def _run_exec_bound_build(
    command: Sequence[str],
    *,
    name: str,
    uid: int,
    gid: int,
    baseline_groups: Sequence[int],
    environment: dict[str, str],
    cwd: Path,
) -> subprocess.CompletedProcess[str]:
    if not command or not os.path.isabs(command[0]):
        raise BuildOriginCustodyError("guarded build command must start with one absolute executable path")
    normalized_baseline = sorted({int(value) for value in baseline_groups if int(value) != gid})
    if any(value <= 0 for value in normalized_baseline):
        raise BuildOriginCustodyError("exec-bound build baseline contains invalid group authority")

    exec_environment = dict(environment)
    exec_environment.update(
        {
            "NEMBRA_EXEC_ATTEST_EXPECTED_UID": str(uid),
            "NEMBRA_EXEC_ATTEST_EXPECTED_GID": str(gid),
            "NEMBRA_EXEC_ATTEST_EXPECTED_USER": name,
            "NEMBRA_EXEC_ATTEST_EXPECTED_GROUPS_JSON": json.dumps(normalized_baseline),
        }
    )
    launcher = r'''
import json
import os
import pwd
import sys

keys = (
    "NEMBRA_EXEC_ATTEST_EXPECTED_UID",
    "NEMBRA_EXEC_ATTEST_EXPECTED_GID",
    "NEMBRA_EXEC_ATTEST_EXPECTED_USER",
    "NEMBRA_EXEC_ATTEST_EXPECTED_GROUPS_JSON",
)
uid = int(os.environ[keys[0]])
gid = int(os.environ[keys[1]])
user = os.environ[keys[2]]
expected = sorted(set(json.loads(os.environ[keys[3]])))
real_uid = os.getuid()
real_gid = os.getgid()
try:
    resolved = pwd.getpwuid(real_uid).pw_name
except KeyError:
    resolved = "<unresolved>"
distinct = sorted(group for group in set(os.getgroups()) if group != gid)
identity_exact = (
    real_uid == uid
    and os.geteuid() == uid
    and real_gid == gid
    and os.getegid() == gid
    and resolved == user
)
if not identity_exact or distinct != expected:
    print("ERROR: exec-bound dedicated-build credential attestation failed", file=sys.stderr, flush=True)
    raise SystemExit(86)
for key in keys:
    os.environ.pop(key, None)
command = sys.argv[2:] if len(sys.argv) > 1 and sys.argv[1] == "--" else sys.argv[1:]
if not command or not os.path.isabs(command[0]):
    print("ERROR: exec-bound guarded command is not absolute", file=sys.stderr, flush=True)
    raise SystemExit(86)
os.execve(command[0], command, os.environ)
raise SystemExit(86)
'''
    return subprocess.run(
        ["/usr/bin/python3", "-B", "-I", "-c", launcher, "--", *command],
        cwd=cwd,
        env=exec_environment,
        stdin=None,
        stdout=sys.stderr,
        stderr=sys.stderr,
        text=True,
        check=False,
        **_structured_credentials(uid, gid, ()),
    )


def _group_names(groups: Sequence[int]) -> tuple[str, ...]:
    names: list[str] = []
    for gid in sorted(set(int(value) for value in groups)):
        if gid <= 0:
            raise BuildOriginCustodyError("cannot inspect sudo policy for root or invalid group authority")
        try:
            names.append(grp.getgrgid(gid).gr_name)
        except KeyError as error:
            raise BuildOriginCustodyError(
                f"could not resolve invoking group {gid} while inspecting sudo policy"
            ) from error
    return tuple(names)


def _sudo_policy_exposes_passwordless_authority(
    policy_output: str,
    invoking_group_names: Sequence[str],
) -> bool:
    if "NOPASSWD:" in policy_output or "!authenticate" in policy_output:
        return True
    exempt_groups = {
        match.group(1).strip("'\"")
        for match in re.finditer(
            r"(?:^|[\s,])exempt_group\s*=\s*([^\s,]+)",
            policy_output,
            flags=re.MULTILINE,
        )
    }
    return bool(exempt_groups.intersection(invoking_group_names))


def _field_environment(user: str, home: str) -> dict[str, str]:
    environment = {
        "HOME": home,
        "USER": user,
        "LOGNAME": user,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
    }
    for key in ("LANG", "LC_ALL", "LC_CTYPE", "TERM", "__CF_USER_TEXT_ENCODING"):
        value = os.environ.get(key)
        if value:
            environment[key] = value
    return environment


def _inspect_invoker_sudo_policy(
    user: str,
    groups: Sequence[int],
    environment: dict[str, str],
) -> None:
    policy_environment = dict(environment)
    policy_environment["LANG"] = "C"
    policy_environment["LC_ALL"] = "C"
    listing = subprocess.run(
        ["/usr/bin/sudo", "-ll", "-U", user],
        env=policy_environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if listing.returncode != 0:
        detail = (listing.stderr or "").strip()
        raise BuildOriginCustodyError(
            "could not inspect invoking-user sudo policy before build custody"
            + (f": {detail}" if detail else "")
        )
    policy_output = (listing.stdout or "") + "\n" + (listing.stderr or "")
    if _sudo_policy_exposes_passwordless_authority(policy_output, _group_names(groups)):
        raise BuildOriginCustodyError(
            "invoking-user sudo policy exposes passwordless privileged authority; "
            "build-origin isolation cannot be established"
        )


def _invalidate_invoker_sudo(
    user: str,
    uid: int,
    gid: int,
    groups: Sequence[int],
    environment: dict[str, str],
) -> None:
    _inspect_invoker_sudo_policy(user, groups, environment)
    credentials = _structured_credentials(uid, gid, groups)
    revoke = subprocess.run(
        ["/usr/bin/sudo", "-K"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    if revoke.returncode != 0:
        raise BuildOriginCustodyError("could not invalidate invoking-user sudo timestamp before build custody")
    command_probe = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    list_probe = subprocess.run(
        ["/usr/bin/sudo", "-n", "-l"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    if command_probe.returncode == 0 or list_probe.returncode == 0:
        raise BuildOriginCustodyError(
            "noninteractive sudo remains available after invalidation; build-origin isolation cannot be established"
        )


def _replace_derived_placeholder(command: Sequence[str], derived_root: Path) -> list[str]:
    if not command:
        raise BuildOriginCustodyError("no guarded build command was supplied")
    matches = sum(argument.count(DERIVED_PLACEHOLDER) for argument in command)
    if matches != 1:
        raise BuildOriginCustodyError(
            "guarded build command must contain exactly one protected DerivedData placeholder"
        )
    return [argument.replace(DERIVED_PLACEHOLDER, str(derived_root)) for argument in command]


def _validate_app_relative(path: Path) -> Path:
    if path.is_absolute() or not path.parts or any(part in ("", ".", "..") for part in path.parts):
        raise BuildOriginCustodyError("app-relative path must remain strictly beneath protected DerivedData")
    return path


def _assert_real_ancestry(root: Path, relative: Path) -> Path:
    current = root
    for component in relative.parts:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise BuildOriginCustodyError(f"expected build output is missing: {current}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise BuildOriginCustodyError(f"build-output ancestry contains a symlink: {current}")
    if not current.is_dir():
        raise BuildOriginCustodyError("build output app is not one real directory")
    return current


def _load_fingerprint_helper(encoded: str):
    try:
        source = base64.b64decode(encoded, validate=True)
    except Exception as error:
        raise BuildOriginCustodyError("accepted install-custody helper transport is malformed") from error
    namespace = {
        "__name__": "nembra_signed_app_install_custody",
        "__file__": "<accepted-signed-app-install-custody>",
    }
    try:
        exec(compile(source, "<accepted-signed-app-install-custody>", "exec", dont_inherit=True), namespace)
    except Exception as error:
        raise BuildOriginCustodyError("accepted install-custody helper could not be loaded") from error
    fingerprint = namespace.get("fingerprint")
    if not callable(fingerprint):
        raise BuildOriginCustodyError("accepted install-custody helper exposes no fingerprint function")
    return fingerprint


def _id_in_use(candidate: int) -> bool:
    try:
        pwd.getpwuid(candidate)
        return True
    except KeyError:
        pass
    try:
        grp.getgrgid(candidate)
        return True
    except KeyError:
        return False


def _process_state_for_uid(uid: int) -> tuple[tuple[int, ...], tuple[int, ...]]:
    if uid <= 0:
        raise BuildOriginCustodyError("cannot inspect process authority for root or invalid UID")
    completed = subprocess.run(
        ["/bin/ps", "-axo", "pid=,uid=,state="],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise BuildOriginCustodyError(
            "could not inspect numeric build-principal process authority"
            + (f": {detail[-1000:]}" if detail else "")
        )
    live: list[int] = []
    zombies: list[int] = []
    for raw_line in completed.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 3:
            raise BuildOriginCustodyError("process authority inventory was malformed")
        try:
            pid = int(parts[0])
            owner = int(parts[1])
        except ValueError as error:
            raise BuildOriginCustodyError("process authority inventory contained non-numeric identity") from error
        if pid <= 0 or owner < 0 or not parts[2]:
            raise BuildOriginCustodyError("process authority inventory contained invalid identity/state")
        if owner != uid:
            continue
        if parts[2].upper().startswith("Z"):
            zombies.append(pid)
        else:
            live.append(pid)
    return tuple(sorted(live)), tuple(sorted(zombies))


def _numeric_principal_in_use(candidate: int) -> bool:
    if candidate <= 0 or _id_in_use(candidate):
        return True
    live, zombies = _process_state_for_uid(candidate)
    return bool(live or zombies)


def _choose_ephemeral_id() -> int:
    start = 52000 + (os.getpid() % 7000)
    for candidate in range(start, 62000):
        if not _numeric_principal_in_use(candidate):
            return candidate
    for candidate in range(52000, start):
        if not _numeric_principal_in_use(candidate):
            return candidate
    raise BuildOriginCustodyError("could not allocate one isolated ephemeral build UID/GID")


def _run_root_checked(argv: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


def _identity_lookup_survivors(name: str, uid: int) -> tuple[str, ...]:
    survivors: list[str] = []
    checks = (
        (pwd.getpwnam, name, "build user name"),
        (pwd.getpwuid, uid, "build user UID"),
        (grp.getgrnam, name, "build group name"),
        (grp.getgrgid, uid, "build group GID"),
    )
    for lookup, key, label in checks:
        try:
            lookup(key)
        except KeyError:
            continue
        survivors.append(label)
    return tuple(survivors)


def _wait_for_no_live_uid(uid: int, *, timeout: float = 6.0) -> tuple[int, ...]:
    if uid <= 0:
        raise BuildOriginCustodyError("cannot verify process retirement for a missing build UID")
    deadline = time.monotonic() + timeout
    latest_live: tuple[int, ...] = ()
    latest_zombies: tuple[int, ...] = ()
    while True:
        latest_live, latest_zombies = _process_state_for_uid(uid)
        if not latest_live:
            return latest_zombies
        if time.monotonic() >= deadline:
            raise BuildOriginCustodyError(
                "live build-principal processes survived retirement: "
                f"live_pids={list(latest_live)} zombie_pids={list(latest_zombies)}"
            )
        time.sleep(0.05)


def _direct_local_identity_record_exists(kind: str, name: str) -> bool:
    completed = subprocess.run(
        ["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
    if completed.returncode == 0:
        return True
    if "eDSRecordNotFound" in detail or "-14136" in detail:
        return False
    raise BuildOriginCustodyError(
        f"could not classify direct Directory Services {kind} record: "
        f"rc={completed.returncode} detail={detail[-800:]!r}"
    )


def _assert_local_build_identity_retired(name: str, uid: int, *, timeout: float = 6.0) -> None:
    if uid <= 0:
        raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")
    deadline = time.monotonic() + timeout
    latest_live: tuple[int, ...] = ()
    latest_zombies: tuple[int, ...] = ()
    latest_user_record = True
    latest_group_record = True
    while True:
        latest_live, latest_zombies = _process_state_for_uid(uid)
        latest_user_record = _direct_local_identity_record_exists("Users", name)
        latest_group_record = _direct_local_identity_record_exists("Groups", name)
        if not latest_live and not latest_zombies and not latest_user_record and not latest_group_record:
            return
        if time.monotonic() >= deadline:
            break
        subprocess.run(
            ["/usr/bin/dscacheutil", "-flushcache"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        time.sleep(0.05)
    raise BuildOriginCustodyError(
        "ephemeral build destructive authority survived retirement: "
        f"live_pids={list(latest_live)} zombie_pids={list(latest_zombies)} "
        f"user_record={latest_user_record} group_record={latest_group_record}"
    )


def _remove_local_build_identity(name: str, uid: int | None, *, require_absent: bool = False) -> None:
    if sys.platform != "darwin":
        return
    if require_absent and (uid is None or uid <= 0):
        raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")
    if uid is not None and uid > 0:
        killed = subprocess.run(
            ["/usr/bin/pkill", "-9", "-u", str(uid), ".*"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if require_absent and killed.returncode not in (0, 1):
            raise BuildOriginCustodyError(
                f"could not request initial build-principal process retirement: pkill exit {killed.returncode}"
            )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)
    if require_absent:
        final_kill = subprocess.run(
            ["/usr/bin/pkill", "-9", "-u", str(uid), ".*"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if final_kill.returncode not in (0, 1):
            raise BuildOriginCustodyError(
                f"could not request final build-principal process retirement: pkill exit {final_kill.returncode}"
            )
        _assert_local_build_identity_retired(name, uid)


def _create_local_build_identity(name: str, uid: int, gid: int, home: Path) -> None:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise BuildOriginCustodyError("ephemeral build identity creation requires root on macOS")
    if uid <= 0 or gid <= 0 or uid != gid:
        raise BuildOriginCustodyError("ephemeral build identity requires one positive dedicated UID/GID")
    for kind in ("Users", "Groups"):
        existing = subprocess.run(
            ["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if existing.returncode == 0:
            raise BuildOriginCustodyError("ephemeral build identity name already exists")
    try:
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(gid)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Capture Build"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(gid)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", str(home)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Capture Build"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"])
        subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)
        account = pwd.getpwnam(name)
        group = grp.getgrnam(name)
        if account.pw_uid != uid or account.pw_gid != gid or group.gr_gid != gid:
            raise BuildOriginCustodyError("directory services did not materialize the exact build identity")
    except Exception:
        _remove_local_build_identity(name, uid, require_absent=True)
        raise


def _create_apfs_image(image: Path) -> None:
    completed = subprocess.run(
        [
            "/usr/bin/hdiutil",
            "create",
            "-quiet",
            "-size",
            "6g",
            "-type",
            "SPARSE",
            "-fs",
            "APFS",
            "-volname",
            APFS_VOLUME_NAME,
            str(image),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise BuildOriginCustodyError(
            "could not create isolated APFS compiler-output image" + (f": {detail}" if detail else "")
        )


def _attach_apfs(image: Path, mountpoint: Path, *, readonly: bool) -> str:
    command = [
        "/usr/bin/hdiutil",
        "attach",
        "-plist",
        "-nobrowse",
        "-owners",
        "on",
        "-mountpoint",
        str(mountpoint),
    ]
    if readonly:
        command.append("-readonly")
    command.append(str(image))
    completed = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise BuildOriginCustodyError(
            "could not attach isolated APFS compiler-output image" + (f": {detail}" if detail else "")
        )
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise BuildOriginCustodyError("hdiutil attach returned malformed plist output") from error
    for entity in payload.get("system-entities", []):
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise BuildOriginCustodyError("hdiutil attach returned no exact mounted compiler-output device")


def _detach_apfs(device: str, *, force: bool = False) -> subprocess.CompletedProcess[str]:
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


def _build_environment(user: str, home: Path) -> dict[str, str]:
    """Return the complete caller-independent environment admitted to the build guard.

    Toolchain selection belongs to the separately accepted command/selected-Xcode
    boundary. Ambient root or field selectors must not regain compiler authority.
    """
    temp = home / "tmp"
    temp.mkdir(parents=True, exist_ok=True)
    return {
        "HOME": str(home),
        "USER": user,
        "LOGNAME": user,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": str(temp),
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8",
    }


def _copy_to_stage(source_app: Path, private_tmp: Path) -> tuple[Path, Path]:
    stage_root = Path(tempfile.mkdtemp(prefix=STAGE_PREFIX, dir=private_tmp))
    os.chown(stage_root, 0, 0)
    os.chmod(stage_root, 0o700)
    stage_app = stage_root / "Nembra Capture.app"
    subprocess.run(
        ["/usr/bin/ditto", "--noacl", str(source_app), str(stage_app)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    acl = subprocess.run(
        ["/usr/bin/find", str(stage_root), "-acl", "-print", "-quit"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()
    if acl:
        raise BuildOriginCustodyError(f"protected stage retained an ACL: {acl}")
    for current_root, directories, files in os.walk(stage_root, topdown=False, followlinks=False):
        current = Path(current_root)
        for name in files:
            os.chown(current / name, 0, 0, follow_symlinks=False)
        for name in directories:
            os.chown(current / name, 0, 0, follow_symlinks=False)
        os.chown(current, 0, 0, follow_symlinks=False)
    os.chmod(stage_root, 0o755)
    return stage_root, stage_app


def _require_readonly_mount(mountpoint: Path) -> None:
    probe = mountpoint / ".nembra-root-readonly-probe"
    try:
        descriptor = os.open(probe, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError as error:
        if error.errno != errno.EROFS:
            raise BuildOriginCustodyError(
                f"read-only compiler-output probe failed ambiguously: errno={error.errno}"
            ) from error
        return
    else:
        os.close(descriptor)
        try:
            probe.unlink()
        except OSError:
            pass
        raise BuildOriginCustodyError("compiler-output image remained root-writable after read-only remount")


def run_custodied_build(
    command: Sequence[str],
    *,
    app_relative: Path,
    fingerprint_helper_base64: str,
    private_read_lease: object | None = None,
) -> tuple[Path, str]:
    if sys.platform != "darwin":
        raise BuildOriginCustodyError("APFS build-origin custody requires macOS")
    private_tmp = _require_real_private_tmp()
    field_user, field_uid, field_gid, field_home, field_groups = _invoking_identity()
    field_env = _field_environment(field_user, field_home)
    _invalidate_invoker_sudo(field_user, field_uid, field_gid, field_groups, field_env)

    fingerprint = _load_fingerprint_helper(fingerprint_helper_base64)
    workspace = Path(tempfile.mkdtemp(prefix=WORKSPACE_PREFIX, dir=private_tmp))
    image = workspace / IMAGE_NAME
    mountpoint = workspace / MOUNT_NAME
    home = workspace / "home"
    stage_root: Path | None = None
    writable_device: str | None = None
    readonly_device: str | None = None
    build_uid: int | None = None
    build_gid: int | None = None
    build_name = f"nembrabuild{os.getpid()}"
    identity_created = False
    private_read_lease_granted = False

    try:
        build_uid = _choose_ephemeral_id()
        build_gid = build_uid
        if build_uid == field_uid or build_gid in field_groups:
            raise BuildOriginCustodyError("ephemeral build identity overlaps field-user authority")

        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        mountpoint.mkdir()
        home.mkdir()
        os.chown(home, build_uid, build_gid)
        os.chmod(home, 0o700)

        _create_local_build_identity(build_name, build_uid, build_gid, home)
        identity_created = True
        build_env = _build_environment(build_name, home)
        os.chown(home / "tmp", build_uid, build_gid)
        os.chmod(home / "tmp", 0o700)
        build_groups = _attest_build_identity_groups(
            build_name,
            build_uid,
            build_gid,
            field_groups,
            build_env,
            home,
        )

        _create_apfs_image(image)
        writable_device = _attach_apfs(image, mountpoint, readonly=False)
        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)

        derived_root = mountpoint / "DerivedData"
        guarded_command = _replace_derived_placeholder(command, derived_root)

        if private_read_lease is not None:
            grant = getattr(private_read_lease, "grant", None)
            revoke = getattr(private_read_lease, "revoke", None)
            if not callable(grant) or not callable(revoke):
                raise BuildOriginCustodyError(
                    "private read-lease object does not expose exact grant/revoke lifecycle"
                )
            grant(build_name)
            private_read_lease_granted = True

        build = _run_exec_bound_build(
            guarded_command,
            name=build_name,
            uid=build_uid,
            gid=build_gid,
            baseline_groups=build_groups,
            environment=build_env,
            cwd=Path(os.getcwd()),
        )

        if private_read_lease_granted:
            private_read_lease.revoke()
            private_read_lease_granted = False

        # Revoke fresh pathname authority before interpreting status. Authority is
        # admitted only after the following normal non-forced quiescence boundary.
        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = _detach_apfs(writable_device)
        detach_detail = ((detach.stdout or "") + "\n" + (detach.stderr or "")).strip()
        if detach.returncode != 0:
            raise BuildOriginCustodyError(
                "compiler-output filesystem did not reach normal non-forced quiescence"
                + (f": {detach_detail}" if detach_detail else "")
            )
        writable_device = None

        if build.returncode != 0:
            raise BuildOriginCustodyError(
                f"exec-bound guarded field build failed with exit status {build.returncode}"
            )

        readonly_device = _attach_apfs(image, mountpoint, readonly=True)
        _require_readonly_mount(mountpoint)
        frozen_derived = mountpoint / "DerivedData"
        source_app = _assert_real_ancestry(frozen_derived, _validate_app_relative(app_relative))
        source_fingerprint = str(fingerprint(source_app))
        if len(source_fingerprint) != 64 or any(
            character not in "0123456789abcdef" for character in source_fingerprint
        ):
            raise BuildOriginCustodyError("build-produced app fingerprint is malformed")

        stage_root, stage_app = _copy_to_stage(source_app, private_tmp)
        staged_fingerprint = str(fingerprint(stage_app))
        if staged_fingerprint != source_fingerprint:
            raise BuildOriginCustodyError("protected stage differs from the read-only compiler-output app")

        frozen_detach = _detach_apfs(readonly_device)
        frozen_detail = ((frozen_detach.stdout or "") + "\n" + (frozen_detach.stderr or "")).strip()
        if frozen_detach.returncode != 0:
            raise BuildOriginCustodyError(
                "read-only compiler-output image could not detach after protected staging"
                + (f": {frozen_detail}" if frozen_detail else "")
            )
        readonly_device = None
        return stage_root, source_fingerprint
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or "").strip()
        raise BuildOriginCustodyError(
            "protected signed-app staging command failed" + (f": {detail}" if detail else "")
        ) from error
    finally:
        failed_before_cleanup = sys.exc_info()[0] is not None
        retirement_error: BuildOriginCustodyError | None = None
        lease_error: BuildOriginCustodyError | None = None
        # Forced detach is cleanup-only after acceptance has already failed. It is
        # never an authority-producing transition.
        if readonly_device is not None:
            _detach_apfs(readonly_device, force=True)
        if writable_device is not None:
            _detach_apfs(writable_device, force=True)
        if private_read_lease_granted:
            try:
                private_read_lease.revoke()
                private_read_lease_granted = False
            except Exception as error:
                lease_error = BuildOriginCustodyError(
                    f"private read lease did not revoke before build-principal retirement: {error}"
                )
        if identity_created:
            try:
                _remove_local_build_identity(build_name, build_uid, require_absent=True)
            except BuildOriginCustodyError as error:
                retirement_error = error
        shutil.rmtree(workspace, ignore_errors=True)
        if (
            failed_before_cleanup
            or lease_error is not None
            or retirement_error is not None
        ) and stage_root is not None:
            shutil.rmtree(stage_root, ignore_errors=True)
        if lease_error is not None:
            raise lease_error
        if retirement_error is not None:
            raise retirement_error


def _parse_args(argv: Sequence[str]) -> tuple[Path, str, list[str]]:
    parser = argparse.ArgumentParser(
        description=(
            "Build the signed Capture app inside dedicated-UID APFS compiler-output custody "
            "and return its protected stage."
        )
    )
    parser.add_argument("--app-relative", default=str(DEFAULT_APP_RELATIVE))
    parser.add_argument("--install-custody-helper-base64", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    return Path(args.app_relative), args.install_custody_helper_base64, command


def main(argv: Sequence[str] | None = None) -> int:
    try:
        app_relative, helper_source, command = _parse_args(sys.argv[1:] if argv is None else argv)
        stage_root, fingerprint = run_custodied_build(
            command,
            app_relative=app_relative,
            fingerprint_helper_base64=helper_source,
        )
        sys.stdout.write(f"{stage_root}\t{fingerprint}\n")
        return 0
    except BuildOriginCustodyError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
