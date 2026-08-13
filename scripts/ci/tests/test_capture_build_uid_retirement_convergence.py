#!/usr/bin/env python3
"""Validation-only convergence oracle for Capture dedicated build-UID retirement.

The production parent remains untouched in Git. In the default runner mode this test:
- proves the checked-out production helper is the exact parent blob;
- materializes a candidate helper only in the ephemeral Actions workspace;
- runs one synthetic dedicated-UID/ordinary-field authority witness through sudo;
- runs the existing unchanged real-Xcode APFS custody fixture;
- restores the exact production helper bytes before returning.

A lingering launchd user domain is never called absent. It is classified as residual
bootstrap metadata only if live UID process authority stays quiescent, direct local
Directory Services records are gone, ordinary field authority probes are denied, and
numeric UID reuse stays blocked for as long as that domain remains observable.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import time
from types import ModuleType
from typing import Sequence


class ValidationError(RuntimeError):
    pass


REPO_ROOT = Path(__file__).resolve().parents[3]
HELPER = REPO_ROOT / "scripts/ci/capture_signed_app_build_origin_custody.py"
REAL_XCODE_TEST = REPO_ROOT / "scripts/ci/tests/test_capture_signed_app_real_xcode_group_custody.py"
LAUNCH_MARKER = "NEMBRA_BUILD_UID_LAUNCH_DOMAIN_RETIREMENT_JSON="
RETIRE_MARKER = "NEMBRA_BUILD_UID_RETIREMENT_JSON="
FIELD_MARKER = "NEMBRA_LIGHTWEIGHT_FIELD_AUTHORITY_JSON="
REAL_MARKER = "NEMBRA_REAL_XCODE_ORIGIN_JSON="
ERROR_MARKER = "NEMBRA_REAL_XCODE_ORIGIN_ERROR="


def _run(argv: Sequence[str], *, check: bool = False, **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        stdin=kwargs.pop("stdin", subprocess.DEVNULL),
        stdout=kwargs.pop("stdout", subprocess.PIPE),
        stderr=kwargs.pop("stderr", subprocess.PIPE),
        text=kwargs.pop("text", True),
        check=check,
        **kwargs,
    )


def _git(*args: str) -> str:
    completed = _run(
        [
            "/usr/bin/env",
            "GIT_NO_REPLACE_OBJECTS=1",
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
            "/usr/bin/git",
            "-c",
            "core.hooksPath=/dev/null",
            *args,
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        raise ValidationError(f"git command failed: {args!r}: {completed.stderr[-800:]!r}")
    return completed.stdout.strip()


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _materialize_candidate(expected_parent: str) -> bytes:
    original = HELPER.read_bytes()
    expected_blob = _git("rev-parse", f"{expected_parent}:scripts/ci/capture_signed_app_build_origin_custody.py")
    current_blob = _git("hash-object", str(HELPER))
    if current_blob != expected_blob:
        raise ValidationError(
            f"production helper is not exact parent blob: expected={expected_blob} actual={current_blob}"
        )
    source = original.decode("utf-8")

    numeric_anchor = '''def _numeric_principal_in_use(candidate: int) -> bool:\n    if candidate <= 0 or _id_in_use(candidate):\n        return True\n    live, zombies = _process_state_for_uid(candidate)\n    return bool(live or zombies)\n\n\n'''
    numeric_replacement = '''def _numeric_principal_in_use(candidate: int) -> bool:\n    if candidate <= 0 or _id_in_use(candidate):\n        return True\n    live, zombies = _process_state_for_uid(candidate)\n    if live or zombies:\n        return True\n    if sys.platform == "darwin":\n        domain_present, _, _ = _launch_domain_state(candidate)\n        if domain_present:\n            return True\n    return False\n\n\n'''
    if source.count(numeric_anchor) != 1:
        raise ValidationError("current exact numeric-principal anchor was not found once")
    source = source.replace(numeric_anchor, numeric_replacement)

    assert_anchor = '''def _assert_local_build_identity_retired(name: str, uid: int, *, timeout: float = 6.0) -> None:\n    if uid <= 0:\n        raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")\n    zombies = _wait_for_no_live_uid(uid, timeout=timeout)\n    deadline = time.monotonic() + timeout\n    latest_lookups: tuple[str, ...] = ()\n    while True:\n        latest_lookups = _identity_lookup_survivors(name, uid)\n        if not latest_lookups:\n            return\n        if time.monotonic() >= deadline:\n            break\n        subprocess.run(\n            ["/usr/bin/dscacheutil", "-flushcache"],\n            stdin=subprocess.DEVNULL,\n            stdout=subprocess.DEVNULL,\n            stderr=subprocess.DEVNULL,\n            check=False,\n        )\n        time.sleep(0.05)\n    raise BuildOriginCustodyError(\n        "ephemeral build identity survived retirement: "\n        f"zombie_pids={list(zombies)} identity_lookups={list(latest_lookups)}"\n    )\n\n\n'''
    if source.count(assert_anchor) != 1:
        raise ValidationError("current exact retirement assertion anchor was not found once")

    helpers = '''def _launch_domain_state(uid: int) -> tuple[bool, int, str]:\n    if uid <= 0:\n        raise BuildOriginCustodyError("cannot inspect launch domain for root or invalid UID")\n    target = f"user/{uid}"\n    completed = subprocess.run(\n        ["/bin/launchctl", "print", target],\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.PIPE,\n        text=True,\n        check=False,\n    )\n    detail = (completed.stderr or "").strip()\n    if completed.returncode == 0:\n        return True, 0, ""\n    absent_markers = (\n        "Could not find domain",\n        "Could not find service",\n        "No such process",\n        "No such file or directory",\n    )\n    if any(marker in detail for marker in absent_markers):\n        return False, completed.returncode, detail[-1000:]\n    raise BuildOriginCustodyError(\n        f"could not classify dedicated build launch domain: exit {completed.returncode}"\n        + (f": {detail[-1000:]}" if detail else ": empty diagnostic")\n    )\n\n\ndef _request_local_build_launch_domain_retirement(uid: int) -> tuple[bool, int | None]:\n    present, _, _ = _launch_domain_state(uid)\n    if not present:\n        return False, None\n    target = f"user/{uid}"\n    bootout = subprocess.run(\n        ["/bin/launchctl", "bootout", target],\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.PIPE,\n        stderr=subprocess.PIPE,\n        text=True,\n        check=False,\n    )\n    if bootout.returncode != 0:\n        detail = (bootout.stderr or "").strip()\n        raise BuildOriginCustodyError(\n            f"could not request dedicated build launch-domain retirement: exit {bootout.returncode}"\n            + (f": {detail[-1000:]}" if detail else "")\n        )\n    return True, bootout.returncode\n\n\ndef _classify_local_build_launch_domain_after_retirement(\n    uid: int,\n    requested: tuple[bool, int | None],\n    *,\n    quiescence: float = 2.0,\n) -> None:\n    domain_present_before, initial_bootout_rc = requested\n    present_after_zero_live_and_ds_delete, _, _ = _launch_domain_state(uid)\n    second_bootout_rc: int | None = None\n    second_bootout_tearing_down = False\n    if present_after_zero_live_and_ds_delete:\n        target = f"user/{uid}"\n        second = subprocess.run(\n            ["/bin/launchctl", "bootout", target],\n            stdin=subprocess.DEVNULL,\n            stdout=subprocess.PIPE,\n            stderr=subprocess.PIPE,\n            text=True,\n            check=False,\n        )\n        second_bootout_rc = second.returncode\n        detail = (second.stderr or "").strip()\n        if second.returncode == 124 and detail == "Boot-out failed: 124: Domain is tearing down":\n            second_bootout_tearing_down = True\n        elif second.returncode != 0:\n            raise BuildOriginCustodyError(\n                f"could not classify post-delete dedicated build launch domain: exit {second.returncode}"\n                + (f": {detail[-1000:]}" if detail else "")\n            )\n\n    deadline = time.monotonic() + quiescence\n    polls = 0\n    domain_absent_observed = False\n    latest_zombies: tuple[int, ...] = ()\n    final_domain_present = present_after_zero_live_and_ds_delete\n    while True:\n        polls += 1\n        live, latest_zombies = _process_state_for_uid(uid)\n        if live:\n            raise BuildOriginCustodyError(\n                "retired build UID regained live process authority during launch-domain quiescence: "\n                f"live_pids={list(live)}"\n            )\n        final_domain_present, _, _ = _launch_domain_state(uid)\n        if not final_domain_present:\n            domain_absent_observed = True\n        if time.monotonic() >= deadline:\n            break\n        time.sleep(0.05)\n\n    numeric_reuse_blocked = _numeric_principal_in_use(uid)\n    if final_domain_present and not numeric_reuse_blocked:\n        raise BuildOriginCustodyError(\n            "lingering launch-domain metadata would permit premature numeric principal reuse"\n        )\n    print(\n        "NEMBRA_BUILD_UID_LAUNCH_DOMAIN_RETIREMENT_JSON="\n        + json.dumps(\n            {\n                "schema": 5,\n                "uid": uid,\n                "domainPresentBefore": domain_present_before,\n                "initialBootoutReturnCode": initial_bootout_rc,\n                "domainPresentAfterZeroLiveAndDSDelete": present_after_zero_live_and_ds_delete,\n                "secondBootoutReturnCode": second_bootout_rc,\n                "secondBootoutTearingDownObserved": second_bootout_tearing_down,\n                "zeroLiveProvedBeforeDSDelete": True,\n                "directRecordDeletionRequestedBeforeDomainClassification": True,\n                "zeroLiveQuiescenceSeconds": quiescence,\n                "zeroLiveQuiescenceProved": True,\n                "zombieUIDProcessesAtClassification": list(latest_zombies),\n                "domainAbsentObservedDuringQuiescence": domain_absent_observed,\n                "domainLingeringAtRetirement": final_domain_present,\n                "numericReuseBlockedAtRetirement": numeric_reuse_blocked,\n                "physicalAuthorityCreated": False,\n            },\n            sort_keys=True,\n            separators=(",", ":"),\n        ),\n        file=sys.stderr,\n    )\n\n\ndef _direct_local_record_present(kind: str, name: str) -> bool:\n    completed = subprocess.run(\n        ["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"],\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.PIPE,\n        stderr=subprocess.PIPE,\n        text=True,\n        check=False,\n    )\n    if completed.returncode == 0:\n        return True\n    detail = ((completed.stdout or "") + "\\n" + (completed.stderr or "")).strip()\n    if "eDSRecordNotFound" in detail or "-14136" in detail:\n        return False\n    raise BuildOriginCustodyError(\n        f"could not classify direct Directory Services {kind} record: exit {completed.returncode}"\n        + (f": {detail[-1000:]}" if detail else ": empty diagnostic")\n    )\n\n\ndef _assert_local_build_identity_retired(name: str, uid: int, *, timeout: float = 6.0) -> None:\n    if uid <= 0:\n        raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")\n    zombies = _wait_for_no_live_uid(uid, timeout=timeout)\n    deadline = time.monotonic() + timeout\n    while True:\n        user_present = _direct_local_record_present("Users", name)\n        group_present = _direct_local_record_present("Groups", name)\n        if not user_present and not group_present:\n            stale_lookups = _identity_lookup_survivors(name, uid)\n            if stale_lookups and not _numeric_principal_in_use(uid):\n                raise BuildOriginCustodyError(\n                    "stale retired identity metadata would permit premature numeric principal reuse"\n                )\n            print(\n                "NEMBRA_BUILD_UID_RETIREMENT_JSON="\n                + json.dumps(\n                    {\n                        "schema": 2,\n                        "uid": uid,\n                        "directUserRecordPresent": False,\n                        "directGroupRecordPresent": False,\n                        "liveUIDProcesses": [],\n                        "zombieUIDProcesses": list(zombies),\n                        "staleLookupCount": len(stale_lookups),\n                        "numericReuseBlockedWhileStale": bool(stale_lookups),\n                        "physicalAuthorityCreated": False,\n                    },\n                    sort_keys=True,\n                    separators=(",", ":"),\n                ),\n                file=sys.stderr,\n            )\n            return\n        if time.monotonic() >= deadline:\n            raise BuildOriginCustodyError(\n                "direct local build identity survived retirement: "\n                f"user_record={user_present} group_record={group_present} zombie_pids={list(zombies)}"\n            )\n        subprocess.run(\n            ["/usr/bin/dscacheutil", "-flushcache"],\n            stdin=subprocess.DEVNULL,\n            stdout=subprocess.DEVNULL,\n            stderr=subprocess.DEVNULL,\n            check=False,\n        )\n        time.sleep(0.05)\n\n\n'''
    source = source.replace(assert_anchor, helpers)

    remove_anchor = '''def _remove_local_build_identity(name: str, uid: int | None, *, require_absent: bool = False) -> None:\n    if sys.platform != "darwin":\n        return\n    if uid is not None and uid > 0:\n        killed = subprocess.run(\n            ["/usr/bin/pkill", "-9", "-u", str(uid), ".*"],\n            stdin=subprocess.DEVNULL,\n            stdout=subprocess.DEVNULL,\n            stderr=subprocess.DEVNULL,\n            check=False,\n        )\n        if require_absent and killed.returncode not in (0, 1):\n            raise BuildOriginCustodyError(\n                f"could not request build-principal process retirement: pkill exit {killed.returncode}"\n            )\n        if require_absent:\n            _wait_for_no_live_uid(uid)\n    subprocess.run(\n        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n        check=False,\n    )\n    subprocess.run(\n        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n        check=False,\n    )\n    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)\n    if require_absent:\n        if uid is None:\n            raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")\n        _assert_local_build_identity_retired(name, uid)\n\n\n'''
    remove_replacement = '''def _remove_local_build_identity(name: str, uid: int | None, *, require_absent: bool = False) -> None:\n    if sys.platform != "darwin":\n        return\n    launch_retirement: tuple[bool, int | None] | None = None\n    if uid is not None and uid > 0:\n        if require_absent:\n            launch_retirement = _request_local_build_launch_domain_retirement(uid)\n        killed = subprocess.run(\n            ["/usr/bin/pkill", "-9", "-u", str(uid), ".*"],\n            stdin=subprocess.DEVNULL,\n            stdout=subprocess.DEVNULL,\n            stderr=subprocess.DEVNULL,\n            check=False,\n        )\n        if require_absent and killed.returncode not in (0, 1):\n            raise BuildOriginCustodyError(\n                f"could not request build-principal process retirement: pkill exit {killed.returncode}"\n            )\n        if require_absent:\n            _wait_for_no_live_uid(uid)\n    subprocess.run(\n        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n        check=False,\n    )\n    subprocess.run(\n        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n        check=False,\n    )\n    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)\n    if require_absent:\n        if uid is None:\n            raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")\n        if launch_retirement is None:\n            raise BuildOriginCustodyError("launch-domain retirement state was not captured")\n        _classify_local_build_launch_domain_after_retirement(uid, launch_retirement)\n        _assert_local_build_identity_retired(name, uid)\n\n\n'''
    if source.count(remove_anchor) != 1:
        raise ValidationError("current exact build-identity removal anchor was not found once")
    source = source.replace(remove_anchor, remove_replacement)
    compile(source, str(HELPER), "exec", dont_inherit=True)
    HELPER.write_text(source, encoding="utf-8")
    return original


def _field_probe(module: ModuleType, *, field: pwd.struct_passwd, field_groups: Sequence[int], uid: int, sentinel: Path) -> dict[str, object]:
    source = "\n".join(
        [
            "import json, os, subprocess, sys",
            "from pathlib import Path",
            "uid=int(sys.argv[1]); sentinel=Path(sys.argv[2]); out={}",
            "def denied(key, operation):",
            "    try: operation()",
            "    except PermissionError: out[key]=True",
            "    except OSError as error:",
            "        if error.errno in (1,13): out[key]=True",
            "        else: raise",
            "    else: out[key]=False",
            "denied('setgroupsDenied', lambda: os.setgroups([uid]))",
            "denied('setgidDenied', lambda: os.setgid(uid))",
            "denied('setuidDenied', lambda: os.setuid(uid))",
            "denied('retiredOwnedReadDenied', lambda: sentinel.read_bytes())",
            "denied('retiredOwnedWriteDenied', lambda: sentinel.write_bytes(b'field-attack'))",
            "asuser=subprocess.run(['/bin/launchctl','asuser',str(uid),'/usr/bin/true'],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,check=False)",
            "out['launchctlAsuserDenied']=asuser.returncode != 0",
            "out['launchctlAsuserReturnCode']=asuser.returncode",
            "print(json.dumps(out,sort_keys=True,separators=(',',':')))",
        ]
    )
    completed = subprocess.run(
        ["/usr/bin/python3", "-B", "-I", "-c", source, str(uid), str(sentinel)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        env={
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": field.pw_dir,
            "USER": field.pw_name,
            "LOGNAME": field.pw_name,
            "LANG": "C",
            "LC_ALL": "C",
        },
        **module._structured_credentials(field.pw_uid, field.pw_gid, field_groups),
    )
    if completed.returncode != 0:
        raise ValidationError(
            f"ordinary-field authority probe failed unexpectedly: rc={completed.returncode} stderr={completed.stderr[-800:]!r}"
        )
    payload = json.loads(completed.stdout)
    required = (
        "setgroupsDenied",
        "setgidDenied",
        "setuidDenied",
        "retiredOwnedReadDenied",
        "retiredOwnedWriteDenied",
        "launchctlAsuserDenied",
    )
    if any(payload.get(key) is not True for key in required):
        raise ValidationError(f"ordinary field retained retired-principal authority: {payload}")
    return payload


def _lightweight_root() -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise ValidationError("lightweight retirement oracle requires root on macOS")
    field_name = os.environ.get("SUDO_USER", "")
    if not field_name:
        raise ValidationError("sudo did not identify the invoking field account")
    field = pwd.getpwnam(field_name)
    field_groups = tuple(sorted(set(os.getgrouplist(field.pw_name, field.pw_gid))))
    if field.pw_uid <= 0 or field.pw_gid <= 0 or any(value <= 0 for value in field_groups):
        raise ValidationError("field authority vector is invalid")

    module = _load(HELPER, "nembra_retirement_convergence_candidate")
    uid = int(module._choose_ephemeral_id())
    name = f"nembralight{uid}"
    root = Path(tempfile.mkdtemp(prefix="nembra-light-retirement.", dir="/private/tmp"))
    home = root / "home"
    home.mkdir(mode=0o700)
    sentinel = root / "retired-owned.bin"
    child: subprocess.Popen[bytes] | None = None
    created = False
    try:
        module._create_local_build_identity(name, uid, uid, home)
        created = True
        sentinel.write_bytes(b"retired-owner-sentinel\n")
        os.chown(sentinel, uid, uid)
        os.chmod(sentinel, 0o600)
        child = subprocess.Popen(
            ["/bin/sleep", "120"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "LANG": "C", "LC_ALL": "C"},
            **module._structured_credentials(uid, uid, ()),
        )
        time.sleep(0.15)
        live, _ = module._process_state_for_uid(uid)
        if child.pid not in live:
            raise ValidationError(f"lightweight dedicated UID process was not observable: {live}")

        module._remove_local_build_identity(name, uid, require_absent=True)
        created = False
        try:
            child.wait(timeout=2.0)
        except subprocess.TimeoutExpired as error:
            raise ValidationError("retired lightweight process did not reap") from error
        live, zombies = module._process_state_for_uid(uid)
        if live or zombies:
            raise ValidationError(f"lightweight retired UID still has process entries: live={live} zombies={zombies}")

        domain_present, _, _ = module._launch_domain_state(uid)
        if domain_present and not module._numeric_principal_in_use(uid):
            raise ValidationError("lingering launch domain did not block numeric UID reuse after child reap")

        payload = _field_probe(
            module,
            field=field,
            field_groups=field_groups,
            uid=uid,
            sentinel=sentinel,
        )
        if sentinel.read_bytes() != b"retired-owner-sentinel\n":
            raise ValidationError("ordinary-field probe changed retired-owned sentinel")
        authority = {
            "schema": 1,
            "domainLingeringAfterChildReap": domain_present,
            "numericReuseBlockedIfDomainLingering": (not domain_present) or module._numeric_principal_in_use(uid),
            "setgroupsDenied": True,
            "setgidDenied": True,
            "setuidDenied": True,
            "retiredOwnedReadDenied": True,
            "retiredOwnedWriteDenied": True,
            "launchctlAsuserDenied": True,
            "launchctlAsuserReturnCode": payload["launchctlAsuserReturnCode"],
            "physicalAuthorityCreated": False,
        }
        print(FIELD_MARKER + json.dumps(authority, sort_keys=True, separators=(",", ":")))
        print("NEMBRA_LIGHTWEIGHT_BUILD_UID_RETIREMENT_ACCEPTED physicalAuthorityCreated=false")
        return 0
    finally:
        if child is not None and child.poll() is None:
            child.kill()
            try:
                child.wait(timeout=1.0)
            except Exception:
                pass
        if created:
            module._remove_local_build_identity(name, uid, require_absent=False)
        shutil.rmtree(root, ignore_errors=True)


def _records(lines: Sequence[str], marker: str) -> list[dict[str, object]]:
    return [json.loads(line[len(marker) :]) for line in lines if line.startswith(marker)]


def _validate_lightweight(log: str) -> None:
    lines = log.splitlines()
    launch = _records(lines, LAUNCH_MARKER)
    field = _records(lines, FIELD_MARKER)
    retire = _records(lines, RETIRE_MARKER)
    if len(launch) != 1 or len(field) != 1 or len(retire) != 1:
        raise ValidationError(
            f"expected one lightweight launch/field/retirement marker, found {len(launch)}/{len(field)}/{len(retire)}"
        )
    item = launch[0]
    if not (
        item.get("schema") == 5
        and item.get("zeroLiveProvedBeforeDSDelete") is True
        and item.get("directRecordDeletionRequestedBeforeDomainClassification") is True
        and item.get("zeroLiveQuiescenceProved") is True
        and item.get("physicalAuthorityCreated") is False
    ):
        raise ValidationError(f"lightweight launch-domain evidence failed: {item}")
    if item.get("domainLingeringAtRetirement") and item.get("numericReuseBlockedAtRetirement") is not True:
        raise ValidationError("lingering launch domain was not reuse-blocked at retirement")
    authority = field[0]
    for key in (
        "setgroupsDenied",
        "setgidDenied",
        "setuidDenied",
        "retiredOwnedReadDenied",
        "retiredOwnedWriteDenied",
        "launchctlAsuserDenied",
        "numericReuseBlockedIfDomainLingering",
    ):
        if authority.get(key) is not True:
            raise ValidationError(f"ordinary field authority gate failed: {key}: {authority}")


def _validate_real_xcode(log: str) -> None:
    lines = log.splitlines()
    if any(line.startswith(ERROR_MARKER) for line in lines):
        raise ValidationError("real-Xcode fixture emitted an authority error marker")
    real = _records(lines, REAL_MARKER)
    launch = _records(lines, LAUNCH_MARKER)
    retire = _records(lines, RETIRE_MARKER)
    if len(real) != 1 or not launch or not retire:
        raise ValidationError(
            f"missing real-Xcode/launch/retirement evidence: {len(real)}/{len(launch)}/{len(retire)}"
        )
    evidence = real[0]
    required = (
        evidence.get("schemaVersion") == 5
        and evidence.get("buildEffectiveGroupAuthorityAttested") is True
        and evidence.get("execBoundCredentialAttestationUsed") is True
        and evidence.get("buildIdentityDistinctFromField") is True
        and evidence.get("xcodebuildReturnCode") == 0
        and evidence.get("nonForcedDetachReturnCode") == 0
        and evidence.get("readonlyNonForcedDetachReturnCode") == 0
        and evidence.get("buildPrincipalRetired") is True
        and evidence.get("compilerProductSHA256") == evidence.get("readonlyRemountSHA256")
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        raise ValidationError(f"real-Xcode authority evidence failed: {evidence}")
    for item in launch:
        if not (
            item.get("schema") == 5
            and item.get("zeroLiveProvedBeforeDSDelete") is True
            and item.get("directRecordDeletionRequestedBeforeDomainClassification") is True
            and item.get("zeroLiveQuiescenceProved") is True
            and item.get("physicalAuthorityCreated") is False
        ):
            raise ValidationError(f"real-Xcode launch-domain evidence failed: {item}")
        if item.get("domainLingeringAtRetirement") and item.get("numericReuseBlockedAtRetirement") is not True:
            raise ValidationError(f"real-Xcode lingering domain is reusable: {item}")
    for item in retire:
        if not (
            item.get("schema") == 2
            and item.get("directUserRecordPresent") is False
            and item.get("directGroupRecordPresent") is False
            and item.get("liveUIDProcesses") == []
            and item.get("physicalAuthorityCreated") is False
        ):
            raise ValidationError(f"real-Xcode direct retirement evidence failed: {item}")
        if item.get("staleLookupCount") and item.get("numericReuseBlockedWhileStale") is not True:
            raise ValidationError(f"real-Xcode stale identity metadata is reusable: {item}")


def _default(expected_parent: str, output_dir: Path) -> int:
    if sys.platform != "darwin" or os.geteuid() == 0:
        raise ValidationError("default convergence runner requires one non-root macOS field account")
    output_dir.mkdir(parents=True, exist_ok=True)
    original = _materialize_candidate(expected_parent)
    try:
        lightweight = _run(
            ["/usr/bin/sudo", "/usr/bin/python3", "-B", "-I", str(Path(__file__).resolve()), "--lightweight-root"],
            cwd=REPO_ROOT,
        )
        light_log = (lightweight.stdout or "") + (lightweight.stderr or "")
        (output_dir / "build-uid-lightweight-retirement.log").write_text(light_log, encoding="utf-8")
        if lightweight.returncode != 0:
            raise ValidationError(
                f"lightweight retirement oracle failed: rc={lightweight.returncode} tail={light_log[-1600:]!r}"
            )
        _validate_lightweight(light_log)

        real = _run(["/usr/bin/python3", "-B", "-I", str(REAL_XCODE_TEST)], cwd=REPO_ROOT)
        real_log = (real.stdout or "") + (real.stderr or "")
        (output_dir / "build-uid-retirement-convergence-real-xcode.log").write_text(real_log, encoding="utf-8")
        (output_dir / "build-uid-retirement-convergence-real-xcode.status").write_text(
            f"{real.returncode}\n", encoding="utf-8"
        )
        if real.returncode != 0:
            raise ValidationError(f"real-Xcode retirement oracle failed: rc={real.returncode} tail={real_log[-1800:]!r}")
        _validate_real_xcode(real_log)

        summary = {
            "schema": 1,
            "productionParent": expected_parent,
            "lightweightAccepted": True,
            "ordinaryFieldAuthorityDenied": True,
            "realXcodeAccepted": True,
            "candidateProductionBytesPersisted": False,
            "physicalAuthorityCreated": False,
        }
        (output_dir / "build-uid-retirement-convergence-summary.json").write_text(
            json.dumps(summary, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        print("BUILD_UID_RETIREMENT_CONVERGENCE_ACCEPTED physicalAuthorityCreated=false")
        return 0
    finally:
        HELPER.write_bytes(original)
        restored_blob = _git("hash-object", str(HELPER))
        expected_blob = _git("rev-parse", f"{expected_parent}:scripts/ci/capture_signed_app_build_origin_custody.py")
        if restored_blob != expected_blob:
            raise ValidationError(
                f"production helper restoration failed: expected={expected_blob} actual={restored_blob}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-parent")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--lightweight-root", action="store_true")
    args = parser.parse_args()
    if args.lightweight_root:
        return _lightweight_root()
    if not args.expected_parent or args.output_dir is None:
        parser.error("default mode requires --expected-parent and --output-dir")
    if len(args.expected_parent) != 40 or any(ch not in "0123456789abcdef" for ch in args.expected_parent):
        raise ValidationError("expected parent must be one lowercase 40-hex SHA")
    return _default(args.expected_parent, args.output_dir)


if __name__ == "__main__":
    raise SystemExit(main())
