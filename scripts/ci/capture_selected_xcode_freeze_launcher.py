#!/usr/bin/env python3
"""Privileged lifecycle launcher for the Capture selected-Xcode freeze.

This launcher is intended to be executed from exact Git-object bytes inside the
same sudo process that first enters privileged authority. It invalidates the
invoking field user's cached sudo authority before any frozen Xcode is exposed,
recovers only cryptographically/classifiably stale prior freeze namespaces, then
executes the accepted freeze helper in-memory. A durable root-owned lifecycle
record makes janitor loss/reboot recoverable on the next privileged entry.

No device discovery, installation, Bluetooth, Tuya, telemetry, signing, or scooter
action occurs here.
"""

from __future__ import annotations

import argparse
import base64
import grp
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import stat
import subprocess
import sys
from typing import Iterable, Sequence

FREEZE_PREFIX = "NembraSelectedXcodeFreeze."
LIFECYCLE_NAME = ".nembra-freeze-lifecycle.json"
CLOSED_ENV = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": "/tmp",
    "LANG": "C",
    "LC_ALL": "C",
}


class FreezeLauncherError(RuntimeError):
    pass


def _git_blob_oid(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def _decode_verified_git_blob(encoded: str, expected_blob: str, label: str) -> bytes:
    if re.fullmatch(r"[0-9a-f]{40}", expected_blob) is None:
        raise FreezeLauncherError(f"{label} expected Git blob identity is malformed")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except Exception as error:
        raise FreezeLauncherError(f"{label} transport is not strict base64") from error
    if _git_blob_oid(raw) != expected_blob:
        raise FreezeLauncherError(f"{label} bytes do not match the accepted Git blob")
    return raw


def _structured_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    normalized = sorted({int(value) for value in groups if int(value) != gid})
    if uid <= 0 or gid <= 0 or any(value <= 0 for value in normalized):
        raise FreezeLauncherError("field credential vector is invalid")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def _invoking_field_identity() -> tuple[str, int, int, str, tuple[int, ...]]:
    raw_user = os.environ.get("SUDO_USER", "")
    raw_uid = os.environ.get("SUDO_UID", "")
    raw_gid = os.environ.get("SUDO_GID", "")
    if not raw_user or raw_user == "root" or not raw_uid.isdigit() or not raw_gid.isdigit():
        raise FreezeLauncherError("sudo did not bind one non-root invoking field identity")
    uid = int(raw_uid)
    gid = int(raw_gid)
    if uid <= 0 or gid <= 0:
        raise FreezeLauncherError("invoking field identity is invalid")
    account = pwd.getpwnam(raw_user)
    if account.pw_uid != uid or account.pw_gid != gid:
        raise FreezeLauncherError("sudo identity disagrees with Directory Services")
    groups = tuple(sorted({int(value) for value in os.getgrouplist(raw_user, gid)}))
    if gid not in groups or any(value <= 0 for value in groups):
        raise FreezeLauncherError("invoking field group baseline is invalid")
    return raw_user, uid, gid, account.pw_dir, groups


def _group_names(groups: Sequence[int]) -> tuple[str, ...]:
    names: list[str] = []
    for gid in sorted(set(int(value) for value in groups)):
        try:
            names.append(grp.getgrgid(gid).gr_name)
        except KeyError as error:
            raise FreezeLauncherError(f"could not resolve invoking group {gid}") from error
    return tuple(names)


def _field_environment(user: str, home: str) -> dict[str, str]:
    environment = dict(CLOSED_ENV)
    environment.update({"USER": user, "LOGNAME": user, "HOME": home, "TMPDIR": "/tmp"})
    return environment


def _sudo_policy_exposes_passwordless_authority(policy: str, group_names: Sequence[str]) -> bool:
    if "NOPASSWD:" in policy or "!authenticate" in policy:
        return True
    exempt_groups = {
        match.group(1).strip("'\"")
        for match in re.finditer(
            r"(?:^|[\s,])exempt_group\s*=\s*([^\s,]+)",
            policy,
            flags=re.MULTILINE,
        )
    }
    return bool(exempt_groups.intersection(group_names))


def _invalidate_invoker_sudo(
    user: str,
    uid: int,
    gid: int,
    groups: Sequence[int],
    home: str,
) -> None:
    environment = _field_environment(user, home)
    listing = subprocess.run(
        ["/usr/bin/sudo", "-ll", "-U", user],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if listing.returncode != 0:
        raise FreezeLauncherError("could not inspect invoking-user sudo policy before freeze custody")
    policy = (listing.stdout or "") + "\n" + (listing.stderr or "")
    if _sudo_policy_exposes_passwordless_authority(policy, _group_names(groups)):
        raise FreezeLauncherError(
            "invoking-user sudo policy exposes passwordless authority; selected-Xcode freeze cannot be isolated"
        )

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
        raise FreezeLauncherError("could not invalidate invoking-user sudo timestamp before freeze custody")
    for argv in (("/usr/bin/sudo", "-n", "/usr/bin/true"), ("/usr/bin/sudo", "-n", "-l")):
        probe = subprocess.run(
            list(argv),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            **credentials,
        )
        if probe.returncode == 0:
            raise FreezeLauncherError(
                "noninteractive sudo remains available after invalidation; selected-Xcode freeze cannot be exposed"
            )


def _ps_value(pid: int, key: str) -> str:
    if pid <= 1:
        raise FreezeLauncherError("field process identity is invalid")
    completed = subprocess.run(
        ["/bin/ps", "-o", f"{key}=", "-p", str(pid)],
        env=CLOSED_ENV,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise FreezeLauncherError("field process identity could not be inspected")
    return completed.stdout.strip()


def _field_start_identity(field_pid: int, field_uid: int) -> str:
    raw_uid = _ps_value(field_pid, "uid")
    if not raw_uid.isdigit() or int(raw_uid) != field_uid:
        raise FreezeLauncherError("claimed field shell PID is not owned by the invoking field UID")
    return _ps_value(field_pid, "lstart")


def _same_field_process(pid: int, uid: int, start_identity: str) -> bool:
    try:
        raw_uid = _ps_value(pid, "uid")
        current_start = _ps_value(pid, "lstart")
    except FreezeLauncherError:
        return False
    return raw_uid.isdigit() and int(raw_uid) == uid and current_start == start_identity


def _freeze_namespace(path: Path) -> bool:
    if path.parent != Path("/Library") or not path.name.startswith(FREEZE_PREFIX):
        return False
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return False
    return (
        stat.S_ISDIR(metadata.st_mode)
        and not stat.S_ISLNK(metadata.st_mode)
        and metadata.st_uid == 0
        and not (metadata.st_mode & 0o022)
    )


def _read_lifecycle(namespace: Path) -> dict[str, object]:
    lifecycle = namespace / LIFECYCLE_NAME
    try:
        metadata = os.lstat(lifecycle)
    except FileNotFoundError as error:
        raise FreezeLauncherError(
            f"unclassified stale freeze {namespace}; exact manual recovery is required before another freeze"
        ) from error
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode) or metadata.st_uid != 0:
        raise FreezeLauncherError(f"stale freeze lifecycle metadata lost root regular-file custody: {namespace}")
    if metadata.st_mode & 0o077:
        raise FreezeLauncherError(f"stale freeze lifecycle metadata is not private root custody: {namespace}")
    fd = os.open(lifecycle, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        raw = os.read(fd, 64 * 1024)
        if os.read(fd, 1):
            raise FreezeLauncherError(f"stale freeze lifecycle metadata is unexpectedly large: {namespace}")
    finally:
        os.close(fd)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FreezeLauncherError(f"stale freeze lifecycle metadata is malformed: {namespace}") from error
    if not isinstance(payload, dict):
        raise FreezeLauncherError(f"stale freeze lifecycle metadata is not an object: {namespace}")
    if payload.get("schemaVersion") != 1 or payload.get("namespace") != str(namespace):
        raise FreezeLauncherError(f"stale freeze lifecycle metadata is not bound to its namespace: {namespace}")
    field_pid = payload.get("fieldPid")
    field_uid = payload.get("fieldUID")
    field_start = payload.get("fieldStartIdentity")
    source_sha = payload.get("sourceSHA")
    helper_blob = payload.get("helperGitBlob")
    if not isinstance(field_pid, int) or field_pid <= 1:
        raise FreezeLauncherError(f"stale freeze lifecycle field PID is invalid: {namespace}")
    if not isinstance(field_uid, int) or field_uid <= 0:
        raise FreezeLauncherError(f"stale freeze lifecycle field UID is invalid: {namespace}")
    if not isinstance(field_start, str) or not field_start:
        raise FreezeLauncherError(f"stale freeze lifecycle start identity is invalid: {namespace}")
    if not isinstance(source_sha, str) or re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise FreezeLauncherError(f"stale freeze lifecycle source SHA is invalid: {namespace}")
    if not isinstance(helper_blob, str) or re.fullmatch(r"[0-9a-f]{40}", helper_blob) is None:
        raise FreezeLauncherError(f"stale freeze lifecycle helper blob is invalid: {namespace}")
    return payload


def _recover_stale_freezes() -> None:
    for entry in sorted(Path("/Library").iterdir(), key=lambda value: value.name):
        if not entry.name.startswith(FREEZE_PREFIX):
            continue
        if not _freeze_namespace(entry):
            raise FreezeLauncherError(
                f"freeze-prefixed subject is not one root/no-write real namespace: {entry}; manual recovery required"
            )
        payload = _read_lifecycle(entry)
        if _same_field_process(
            int(payload["fieldPid"]),
            int(payload["fieldUID"]),
            str(payload["fieldStartIdentity"]),
        ):
            raise FreezeLauncherError(f"an admitted selected-Xcode freeze is still active: {entry}")
        shutil.rmtree(entry)
        if entry.exists():
            raise FreezeLauncherError(f"stale selected-Xcode freeze could not be reclaimed: {entry}")


def _write_lifecycle(
    namespace: Path,
    *,
    field_pid: int,
    field_uid: int,
    field_start: str,
    source_sha: str,
    helper_blob: str,
    janitor_pid: int,
) -> None:
    if not _freeze_namespace(namespace):
        raise FreezeLauncherError("admitted freeze namespace lost root/no-write custody before lifecycle sealing")
    payload = {
        "schemaVersion": 1,
        "namespace": str(namespace),
        "fieldPid": field_pid,
        "fieldUID": field_uid,
        "fieldStartIdentity": field_start,
        "sourceSHA": source_sha,
        "helperGitBlob": helper_blob,
        "janitorPid": janitor_pid,
        "physicalAuthorityCreated": False,
    }
    raw = (json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    lifecycle = namespace / LIFECYCLE_NAME
    fd = os.open(lifecycle, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o400)
    try:
        os.write(fd, raw)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chown(lifecycle, 0, 0)
    os.chmod(lifecycle, 0o400)
    metadata = os.lstat(lifecycle)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o400:
        raise FreezeLauncherError("freeze lifecycle record publication metadata is invalid")


def _load_freeze_helper(encoded: str, expected_blob: str) -> dict[str, object]:
    raw = _decode_verified_git_blob(encoded, expected_blob, "selected-Xcode freeze helper")
    namespace: dict[str, object] = {
        "__name__": "nembra_selected_xcode_freeze",
        "__file__": "<accepted-selected-xcode-freeze-helper>",
    }
    exec(
        compile(raw, "<accepted-selected-xcode-freeze-helper>", "exec", dont_inherit=True),
        namespace,
    )
    if not callable(namespace.get("freeze_selected_xcode")) or not callable(namespace.get("_safe_cleanup")):
        raise FreezeLauncherError("accepted selected-Xcode freeze helper exposes no required callable contract")
    return namespace


def run(field_pid: int, source_sha: str, helper_encoded: str, helper_blob: str) -> tuple[Path, Path, dict[str, Path], int]:
    if os.geteuid() != 0 or sys.platform != "darwin":
        raise FreezeLauncherError("selected-Xcode privileged launcher requires root on macOS")
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise FreezeLauncherError("accepted source SHA is malformed")

    _, field_uid, field_gid, field_home, field_groups = _invoking_field_identity()
    field_user = os.environ["SUDO_USER"]
    field_start = _field_start_identity(field_pid, field_uid)

    # The current sudo process is already root. Revoke the caller's reusable
    # timestamp before stale recovery, COW construction, or any 0755 publication.
    _invalidate_invoker_sudo(field_user, field_uid, field_gid, field_groups, field_home)
    _recover_stale_freezes()

    helper = _load_freeze_helper(helper_encoded, helper_blob)
    freeze = helper["freeze_selected_xcode"]
    safe_cleanup = helper["_safe_cleanup"]
    result = freeze(field_pid)  # type: ignore[operator]
    namespace, developer, tools, janitor_pid = result
    try:
        _write_lifecycle(
            namespace,
            field_pid=field_pid,
            field_uid=field_uid,
            field_start=field_start,
            source_sha=source_sha,
            helper_blob=helper_blob,
            janitor_pid=janitor_pid,
        )
    except Exception:
        try:
            os.kill(janitor_pid, signal.SIGKILL)
        except OSError:
            pass
        safe_cleanup(namespace)  # type: ignore[operator]
        raise
    return namespace, developer, tools, janitor_pid


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Launch one selected-Xcode freeze behind a single revoked-sudo authority boundary")
    parser.add_argument("--field-pid", required=True, type=int)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--helper-base64", required=True)
    parser.add_argument("--helper-blob", required=True)
    return parser.parse_args(list(argv))


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parse(sys.argv[1:] if argv is None else argv)
        namespace, developer, tools, janitor_pid = run(
            args.field_pid,
            args.source_sha.lower(),
            args.helper_base64,
            args.helper_blob.lower(),
        )
        values = [
            str(namespace),
            str(developer),
            str(tools["xcodebuild"]),
            str(tools["xctrace"]),
            str(tools["devicectl"]),
            str(janitor_pid),
        ]
        if any("\t" in value or "\n" in value for value in values):
            raise FreezeLauncherError("selected-Xcode launcher result contains malformed separators")
        sys.stdout.write("\t".join(values) + "\n")
        return 0
    except (OSError, KeyError, subprocess.SubprocessError, FreezeLauncherError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
