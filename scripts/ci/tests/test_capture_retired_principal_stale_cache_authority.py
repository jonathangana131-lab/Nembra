#!/usr/bin/env python3
"""Classify stale pwd/grp cache after destructive build-principal retirement on macOS.

Validation only. This witness deliberately separates three facts that current #3142
conflates in its final retirement predicate:
- direct local Directory Services user/group records;
- live/zombie process authority under the retired numeric UID;
- stale libc pwd/grp resolution metadata.

It requires a real stale-cache state after direct records and processes are gone, then
proves an ordinary field identity cannot adopt the retired UID/GID/group vector or use
an orphan mode-0600 file owned by that UID. It also requires current production numeric
ID admission to keep the stale cached UID unavailable for reuse. No product/physical
authority is created.
"""
from __future__ import annotations

import argparse
import errno
import grp
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
import time
from types import ModuleType
from typing import Sequence


class ValidationError(RuntimeError):
    pass


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _run(argv: Sequence[str], *, check: bool = False, **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=check,
        **kwargs,
    )


def _ds_record_state(kind: str, name: str) -> tuple[bool, int, str]:
    completed = _run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"])
    detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
    if completed.returncode == 0:
        return True, 0, detail[-800:]
    if "eDSRecordNotFound" in detail or "-14136" in detail:
        return False, completed.returncode, detail[-800:]
    raise ValidationError(
        f"could not classify direct Directory Services {kind} record: "
        f"rc={completed.returncode} detail={detail[-800:]!r}"
    )


def _cached_lookup_state(name: str, uid: int) -> dict[str, object]:
    result: dict[str, object] = {}
    probes = (
        ("userNameResolved", pwd.getpwnam, name, "pw_name"),
        ("uidResolved", pwd.getpwuid, uid, "pw_name"),
        ("groupNameResolved", grp.getgrnam, name, "gr_name"),
        ("gidResolved", grp.getgrgid, uid, "gr_name"),
    )
    for key, lookup, value, attribute in probes:
        try:
            subject = lookup(value)
        except KeyError:
            result[key] = False
        else:
            result[key] = True
            result[key + "As"] = getattr(subject, attribute, "<unknown>")
    return result


def _delete_identity_records(name: str) -> dict[str, int]:
    user = _run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
    group = _run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
    if user.returncode != 0 or group.returncode != 0:
        raise ValidationError(
            "destructive retirement could not delete both direct Directory Services records: "
            f"user={user.returncode} group={group.returncode}"
        )
    _run(["/usr/bin/dscacheutil", "-flushcache"])
    return {"userDeleteReturnCode": user.returncode, "groupDeleteReturnCode": group.returncode}


def _require_direct_records_absent(name: str) -> dict[str, object]:
    user, user_rc, user_tail = _ds_record_state("Users", name)
    group, group_rc, group_tail = _ds_record_state("Groups", name)
    if user or group:
        raise ValidationError(
            f"direct Directory Services records survived deletion: user={user} group={group}"
        )
    return {
        "userDirectoryServiceRecordResolved": user,
        "groupDirectoryServiceRecordResolved": group,
        "userDirectoryServiceReadReturnCode": user_rc,
        "groupDirectoryServiceReadReturnCode": group_rc,
        "userDirectoryServiceReadTail": user_tail,
        "groupDirectoryServiceReadTail": group_tail,
    }


def _field_authority_probe(
    helper: ModuleType,
    *,
    field: pwd.struct_passwd,
    field_groups: Sequence[int],
    retired_name: str,
    retired_uid: int,
    orphan: Path,
) -> dict[str, object]:
    source = r'''
import errno
import json
import os
from pathlib import Path
import pwd
import grp
import subprocess
import sys

name=sys.argv[1]
uid=int(sys.argv[2])
orphan=Path(sys.argv[3])
out={}

def require_denied(key, operation):
    try:
        operation()
    except PermissionError:
        out[key]=True
    except OSError as error:
        if error.errno in (errno.EPERM, errno.EACCES):
            out[key]=True
        else:
            raise
    else:
        out[key]=False

require_denied('setgroupsDenied', lambda: os.setgroups([uid]))
require_denied('setgidDenied', lambda: os.setgid(uid))
require_denied('setuidDenied', lambda: os.setuid(uid))
require_denied('retiredOwnedFileReadDenied', lambda: orphan.read_bytes())
require_denied('retiredOwnedFileWriteDenied', lambda: orphan.write_bytes(b'field-authority-attack'))

for key, lookup, value in (
    ('fieldUserNameLookupResolved', pwd.getpwnam, name),
    ('fieldUIDLookupResolved', pwd.getpwuid, uid),
    ('fieldGroupNameLookupResolved', grp.getgrnam, name),
    ('fieldGIDLookupResolved', grp.getgrgid, uid),
):
    try:
        lookup(value)
    except KeyError:
        out[key]=False
    else:
        out[key]=True

print(json.dumps(out,sort_keys=True,separators=(',',':')))
'''
    completed = subprocess.run(
        ["/usr/bin/python3", "-B", "-I", "-c", source, retired_name, str(retired_uid), str(orphan)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"},
        **helper._structured_credentials(field.pw_uid, field.pw_gid, field_groups),
    )
    if completed.returncode != 0:
        raise ValidationError(
            f"ordinary field authority probe failed unexpectedly: rc={completed.returncode} "
            f"stderr={completed.stderr[-1000:]!r}"
        )
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise ValidationError("ordinary field authority probe emitted malformed JSON") from error
    required_denials = (
        "setgroupsDenied",
        "setgidDenied",
        "setuidDenied",
        "retiredOwnedFileReadDenied",
        "retiredOwnedFileWriteDenied",
    )
    if any(payload.get(key) is not True for key in required_denials):
        raise ValidationError(f"stale cache coincided with ordinary field authority: {payload}")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field-user", required=True)
    parser.add_argument("--production-helper", required=True, type=Path)
    parser.add_argument("--production-parent", required=True)
    args = parser.parse_args()

    if sys.platform != "darwin" or os.geteuid() != 0:
        raise ValidationError("stale-cache retirement classification requires root on real macOS")
    field = pwd.getpwnam(args.field_user)
    if field.pw_uid <= 0 or field.pw_gid <= 0:
        raise ValidationError("field identity must be one non-root account")
    field_groups = tuple(sorted(set(os.getgrouplist(field.pw_name, field.pw_gid))))
    if any(value <= 0 for value in field_groups):
        raise ValidationError("field group vector contains root or invalid authority")

    helper = _load(args.production_helper, "nembra_retired_cache_current_production_helper")
    required_helper = (
        "_structured_credentials",
        "_choose_ephemeral_id",
        "_create_local_build_identity",
        "_process_state_for_uid",
        "_numeric_principal_in_use",
    )
    missing = [name for name in required_helper if not callable(getattr(helper, name, None))]
    if missing:
        raise ValidationError(f"current production helper lacks retirement-classification primitives: {missing!r}")

    root = Path(tempfile.mkdtemp(prefix="nembra-retired-cache-authority.", dir="/private/tmp"))
    os.chown(root, 0, 0)
    os.chmod(root, 0o711)
    retired_name = f"nembracache{os.getpid()}"
    retired_uid: int | None = None
    direct_created = False
    sleeper: subprocess.Popen[str] | None = None
    result: dict[str, object] = {}
    try:
        retired_uid = int(helper._choose_ephemeral_id())
        if retired_uid <= 0 or retired_uid == field.pw_uid or retired_uid in field_groups:
            raise ValidationError("selected retired UID collides with field authority")
        home = root / "build-home"
        helper._create_local_build_identity(retired_name, retired_uid, retired_uid, home)
        direct_created = True

        # Prime every libc identity lookup while the direct records still exist.
        account_by_name = pwd.getpwnam(retired_name)
        account_by_uid = pwd.getpwuid(retired_uid)
        group_by_name = grp.getgrnam(retired_name)
        group_by_gid = grp.getgrgid(retired_uid)
        if (
            account_by_name.pw_uid != retired_uid
            or account_by_uid.pw_name != retired_name
            or group_by_name.gr_gid != retired_uid
            or group_by_gid.gr_name != retired_name
        ):
            raise ValidationError("primed libc identity tuple does not match dedicated principal")

        orphan = root / "retired-owned-private.bin"
        orphan.write_bytes(b"retired-owner-sentinel\n")
        os.chown(orphan, retired_uid, retired_uid)
        os.chmod(orphan, 0o600)

        sleeper = subprocess.Popen(
            ["/bin/sleep", "120"],
            cwd=root,
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "TMPDIR": "/tmp"},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            **helper._structured_credentials(retired_uid, retired_uid, ()),
        )
        time.sleep(0.12)
        live_before, zombies_before = helper._process_state_for_uid(retired_uid)
        if sleeper.pid not in live_before or zombies_before:
            raise ValidationError(
                f"dedicated sleeper did not establish clean live authority: live={live_before} zombies={zombies_before}"
            )

        killed = _run(["/usr/bin/pkill", "-9", "-u", str(retired_uid)])
        if killed.returncode not in (0, 1):
            raise ValidationError(f"retired-UID pkill failed: rc={killed.returncode}")
        sleeper.wait(timeout=2.0)
        live_after_reap, zombies_after_reap = helper._process_state_for_uid(retired_uid)
        if live_after_reap or zombies_after_reap:
            raise ValidationError(
                f"retired UID still owns process authority after explicit reap: "
                f"live={live_after_reap} zombies={zombies_after_reap}"
            )

        delete_commands = _delete_identity_records(retired_name)
        direct_created = False
        direct_state = _require_direct_records_absent(retired_name)
        live_after_delete, zombies_after_delete = helper._process_state_for_uid(retired_uid)
        if live_after_delete or zombies_after_delete:
            raise ValidationError(
                f"retired UID regained process authority after DS deletion: "
                f"live={live_after_delete} zombies={zombies_after_delete}"
            )

        # Reproduce the exact retained-red class: direct records and processes are gone,
        # yet at least one libc pwd/grp query still resolves stale metadata after flush.
        stale_state = _cached_lookup_state(retired_name, retired_uid)
        stale_keys = ("userNameResolved", "uidResolved", "groupNameResolved", "gidResolved")
        stale_observed = any(bool(stale_state.get(key)) for key in stale_keys)
        if not stale_observed:
            deadline = time.monotonic() + 1.5
            while time.monotonic() < deadline and not stale_observed:
                time.sleep(0.05)
                stale_state = _cached_lookup_state(retired_name, retired_uid)
                stale_observed = any(bool(stale_state.get(key)) for key in stale_keys)
        if not stale_observed:
            raise ValidationError(
                "runner did not reproduce retained stale pwd/grp cache metadata after direct retirement"
            )

        # Current production allocation must remain conservative while libc still
        # resolves the retired numeric principal. This prevents orphan-file authority
        # from being transferred through premature UID reuse.
        if helper._numeric_principal_in_use(retired_uid) is not True:
            raise ValidationError("current production would prematurely recycle a stale-cached retired UID")

        field_probe = _field_authority_probe(
            helper,
            field=field,
            field_groups=field_groups,
            retired_name=retired_name,
            retired_uid=retired_uid,
            orphan=orphan,
        )
        if orphan.read_bytes() != b"retired-owner-sentinel\n":
            raise ValidationError("ordinary field authority probe mutated retired-owned sentinel bytes")
        if stat.S_IMODE(orphan.stat().st_mode) != 0o600 or orphan.stat().st_uid != retired_uid:
            raise ValidationError("retired-owned sentinel custody changed during authority probes")

        final_direct = _require_direct_records_absent(retired_name)
        final_live, final_zombies = helper._process_state_for_uid(retired_uid)
        if final_live or final_zombies:
            raise ValidationError(
                f"retired numeric UID gained process authority during field probes: live={final_live} zombies={final_zombies}"
            )

        result = {
            "schema": 1,
            "productionParent": args.production_parent,
            "retiredUID": retired_uid,
            "directDeleteCommands": delete_commands,
            "directStateAfterDelete": direct_state,
            "stalePwdGrpCacheObserved": True,
            "staleLookupState": stale_state,
            "zeroRetiredUIDProcesses": True,
            "productionNumericReuseBlockedWhileCacheStale": True,
            "ordinaryFieldAuthorityProbe": field_probe,
            "ordinaryFieldSetgroupsDenied": True,
            "ordinaryFieldSetgidDenied": True,
            "ordinaryFieldSetuidDenied": True,
            "ordinaryFieldRetiredOwnedReadDenied": True,
            "ordinaryFieldRetiredOwnedWriteDenied": True,
            "retiredOwnedSentinelUnchanged": True,
            "finalDirectState": final_direct,
            "modeledFieldAuthorityDeniedDespiteStaleLookup": True,
            "productionBytesChanged": False,
            "xcodeUsed": False,
            "appleSigningIdentityUsed": False,
            "privateTuyaInputsUsed": False,
            "deviceUsed": False,
            "bluetoothUsed": False,
            "physicalAuthorityCreated": False,
        }
    finally:
        if sleeper is not None and sleeper.poll() is None:
            try:
                sleeper.kill()
            except ProcessLookupError:
                pass
            try:
                sleeper.wait(timeout=1.0)
            except Exception:
                pass
        if retired_uid is not None:
            _run(["/usr/bin/pkill", "-9", "-u", str(retired_uid)])
        if direct_created:
            _run(["/usr/bin/dscl", ".", "-delete", f"/Users/{retired_name}"])
            _run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{retired_name}"])
        _run(["/usr/bin/dscacheutil", "-flushcache"])
        shutil.rmtree(root, ignore_errors=True)

    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
