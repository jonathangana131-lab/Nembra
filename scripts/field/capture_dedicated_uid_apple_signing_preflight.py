#!/usr/bin/env python3
"""Classify Apple Development signing feasibility for Capture's fresh build UID.

Validation only. This probe reproduces the current #3142 fresh hidden user/group and
fresh HOME credential topology on the private field Mac, then asks whether that exact
identity can discover and use an already-installed Apple Development identity to sign
one harmless local executable copy.

It deliberately does NOT run xcodebuild, Automatic provisioning, private Tuya input,
device discovery/install, Bluetooth, or any scooter operation. Raw certificate labels,
certificate fingerprints, keychain output, and codesign diagnostics never leave the
fresh child. The public receipt is classification-only and redacted.
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
import subprocess
import sys
import tempfile
import time
from typing import Any

PRODUCTION_PARENT = "c4996ea91cc3482ca8a8d661fd1436a2eee745df"
RELATIVE_PATH = "scripts/field/capture_dedicated_uid_apple_signing_preflight.py"
SUCCESS_MARKER = "NEMBRA_DEDICATED_UID_APPLE_SIGNING_JSON="
ERROR_MARKER = "NEMBRA_DEDICATED_UID_APPLE_SIGNING_ERROR="
SELF_SOURCE_B64 = ""
APPLE_IDENTITY_RE = re.compile(
    r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"Apple Development:[^"]+"\s*$'
)


class PreflightError(RuntimeError):
    pass


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "kind": kind,
        "message": message,
        "productionAcceptanceClaimed": False,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def git_blob_oid(payload: bytes) -> str:
    framed = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    return hashlib.sha1(framed).hexdigest()


def parse_apple_development_fingerprints(output: str) -> list[str]:
    """Return unique signing fingerprints without retaining human identity labels."""
    result: list[str] = []
    for line in output.splitlines():
        match = APPLE_IDENTITY_RE.match(line)
        if match is None:
            continue
        fingerprint = match.group(1).upper()
        if fingerprint not in result:
            result.append(fingerprint)
    return result


def run(
    argv: list[str],
    *,
    env: dict[str, str] | None = None,
    timeout: float | None = None,
    user: int | None = None,
    group: int | None = None,
    extra_groups: list[int] | None = None,
) -> subprocess.CompletedProcess[str]:
    kwargs: dict[str, Any] = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "text": True,
        "check": False,
    }
    if env is not None:
        kwargs["env"] = env
    if timeout is not None:
        kwargs["timeout"] = timeout
    if user is not None:
        kwargs["user"] = user
    if group is not None:
        kwargs["group"] = group
    if extra_groups is not None:
        kwargs["extra_groups"] = extra_groups
    return subprocess.run(argv, **kwargs)


def flush_directory_cache() -> None:
    run(["/usr/bin/dscacheutil", "-flushcache"])


def ds_record_exists(kind: str, name: str) -> bool:
    completed = run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"])
    if completed.returncode == 0:
        return True
    combined = (completed.stdout or "") + "\n" + (completed.stderr or "")
    if "eDSRecordNotFound" in combined or "-14136" in combined:
        return False
    raise PreflightError(
        f"could not classify local Directory Services {kind} record (rc={completed.returncode})"
    )


def uid_process_state(uid: int) -> tuple[list[int], list[int]]:
    completed = run(["/bin/ps", "-axo", "pid=,uid=,state="])
    if completed.returncode != 0:
        raise PreflightError("could not inspect the process table for dedicated UID cleanup")
    live: list[int] = []
    zombies: list[int] = []
    for raw in completed.stdout.splitlines():
        fields = raw.split()
        if len(fields) < 3:
            continue
        try:
            pid = int(fields[0])
            owner = int(fields[1])
        except ValueError:
            continue
        if owner != uid:
            continue
        if fields[2].upper().startswith("Z"):
            zombies.append(pid)
        else:
            live.append(pid)
    return sorted(live), sorted(zombies)


def id_is_available(candidate: int) -> bool:
    try:
        pwd.getpwuid(candidate)
        return False
    except KeyError:
        pass
    try:
        grp.getgrgid(candidate)
        return False
    except KeyError:
        return True


def choose_ephemeral_id() -> int:
    start = 52000 + (os.getpid() % 7000)
    for candidate in list(range(start, 62000)) + list(range(52000, start)):
        if candidate > 0 and id_is_available(candidate):
            return candidate
    raise PreflightError("could not allocate a fresh dedicated UID/GID")


def create_identity(name: str, uid: int, home: Path) -> None:
    for kind in ("Users", "Groups"):
        if run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"]).returncode == 0:
            raise PreflightError("dedicated preflight principal name already exists")

    commands = (
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"],
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(uid)],
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Capture Signing Probe"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(uid)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", str(home)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Capture Signing Probe"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"],
    )
    for command in commands:
        completed = run(command)
        if completed.returncode != 0:
            raise PreflightError("Directory Services could not materialize the dedicated signing probe")
    flush_directory_cache()

    deadline = time.monotonic() + 4.0
    while time.monotonic() < deadline:
        try:
            account = pwd.getpwnam(name)
            group_entry = grp.getgrnam(name)
        except KeyError:
            flush_directory_cache()
            time.sleep(0.05)
            continue
        if account.pw_uid == uid and account.pw_gid == uid and group_entry.gr_gid == uid:
            return
        raise PreflightError("dedicated signing probe materialized with the wrong numeric identity")
    raise PreflightError("dedicated signing probe did not become resolvable")


def remove_identity_strict(name: str, uid: int) -> dict[str, object]:
    pkill = run(["/usr/bin/pkill", "-9", "-u", str(uid)])
    if pkill.returncode not in (0, 1):
        raise PreflightError(f"dedicated UID process retirement failed (rc={pkill.returncode})")

    user_delete = run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
    group_delete = run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
    if user_delete.returncode != 0 or group_delete.returncode != 0:
        raise PreflightError(
            "dedicated signing probe deletion failed "
            f"(user_rc={user_delete.returncode}, group_rc={group_delete.returncode})"
        )
    flush_directory_cache()

    deadline = time.monotonic() + 8.0
    cached_absent = False
    direct_absent = False
    live: list[int] = []
    zombies: list[int] = []
    while time.monotonic() < deadline:
        direct_absent = not ds_record_exists("Users", name) and not ds_record_exists("Groups", name)
        live, zombies = uid_process_state(uid)
        cached_flags: list[bool] = []
        for lookup, value in (
            (pwd.getpwnam, name),
            (grp.getgrnam, name),
            (pwd.getpwuid, uid),
            (grp.getgrgid, uid),
        ):
            try:
                lookup(value)
            except KeyError:
                cached_flags.append(False)
            else:
                cached_flags.append(True)
        cached_absent = not any(cached_flags)
        if direct_absent and not live and not zombies and cached_absent:
            break
        flush_directory_cache()
        time.sleep(0.05)

    if not direct_absent or live or zombies:
        raise PreflightError(
            "dedicated signing probe retained authoritative identity/process state after cleanup"
        )
    return {
        "pkillReturnCode": pkill.returncode,
        "userDeleteReturnCode": user_delete.returncode,
        "groupDeleteReturnCode": group_delete.returncode,
        "directoryServiceRecordsAbsent": direct_absent,
        "liveUIDProcesses": live,
        "zombieUIDProcesses": zombies,
        "cachedIdentityLookupsAbsent": cached_absent,
    }


def dedicated_environment(name: str, home: Path) -> dict[str, str]:
    temp = home / "tmp"
    temp.mkdir(parents=True, exist_ok=True)
    environment = {
        "HOME": str(home),
        "USER": name,
        "LOGNAME": name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": str(temp),
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8",
    }
    return environment


def _dedicated_child(config: dict[str, object]) -> int:
    expected_uid = int(config["uid"])
    expected_gid = int(config["gid"])
    expected_name = str(config["name"])
    expected_groups = sorted(int(value) for value in config["groups"])
    fixture = Path(str(config["fixture"]))

    observed_groups = sorted(group for group in os.getgroups() if group != expected_gid)
    account = pwd.getpwuid(os.geteuid())
    if (
        os.getuid() != expected_uid
        or os.geteuid() != expected_uid
        or os.getgid() != expected_gid
        or os.getegid() != expected_gid
        or account.pw_name != expected_name
        or observed_groups != expected_groups
    ):
        print(
            SUCCESS_MARKER
            + json.dumps(
                {
                    "classification": "credential_topology_red",
                    "credentialTopologyExact": False,
                    "identityDetailsRedacted": True,
                    "productionAcceptanceClaimed": False,
                    "physicalAuthorityCreated": False,
                },
                sort_keys=True,
            )
        )
        return 41

    identity_probe = run(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        env=dict(os.environ),
        timeout=15.0,
    )
    if identity_probe.returncode != 0:
        receipt = {
            "classification": "security_tool_red",
            "credentialTopologyExact": True,
            "securityFindIdentityReturnCode": identity_probe.returncode,
            "appleDevelopmentIdentityCount": 0,
            "signingAttempted": False,
            "signingSucceeded": False,
            "strictVerifySucceeded": False,
            "appleDevelopmentAuthorityPresent": False,
            "identityDetailsRedacted": True,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(SUCCESS_MARKER + json.dumps(receipt, sort_keys=True))
        return 42

    fingerprints = parse_apple_development_fingerprints(identity_probe.stdout + "\n" + identity_probe.stderr)
    if not fingerprints:
        receipt = {
            "classification": "dedicated_uid_apple_identity_absent",
            "credentialTopologyExact": True,
            "securityFindIdentityReturnCode": 0,
            "appleDevelopmentIdentityCount": 0,
            "signingAttempted": False,
            "signingSucceeded": False,
            "strictVerifySucceeded": False,
            "appleDevelopmentAuthorityPresent": False,
            "identityDetailsRedacted": True,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(SUCCESS_MARKER + json.dumps(receipt, sort_keys=True))
        return 0

    signing_succeeded = False
    strict_verify = False
    authority_present = False
    signing_timeout = False
    signing_return_code: int | None = None
    for fingerprint in fingerprints:
        fixture.unlink(missing_ok=True)
        with open("/usr/bin/true", "rb") as source, open(fixture, "wb") as destination:
            shutil.copyfileobj(source, destination)
        fixture.chmod(0o700)
        try:
            signed = run(
                [
                    "/usr/bin/codesign",
                    "--force",
                    "--sign",
                    fingerprint,
                    "--timestamp=none",
                    str(fixture),
                ],
                env=dict(os.environ),
                timeout=20.0,
            )
        except subprocess.TimeoutExpired:
            signing_timeout = True
            continue
        signing_return_code = signed.returncode
        if signed.returncode != 0:
            continue
        signing_succeeded = True
        verified = run(
            ["/usr/bin/codesign", "--verify", "--strict", str(fixture)],
            env=dict(os.environ),
            timeout=10.0,
        )
        strict_verify = verified.returncode == 0
        details = run(
            ["/usr/bin/codesign", "-d", "--verbose=4", str(fixture)],
            env=dict(os.environ),
            timeout=10.0,
        )
        detail_text = details.stdout + "\n" + details.stderr
        authority_present = "Authority=Apple Development:" in detail_text
        if strict_verify and authority_present:
            break

    fixture.unlink(missing_ok=True)
    feasible = signing_succeeded and strict_verify and authority_present
    receipt = {
        "classification": (
            "dedicated_uid_apple_signing_feasible"
            if feasible
            else "dedicated_uid_apple_identity_visible_but_signing_unusable"
        ),
        "credentialTopologyExact": True,
        "securityFindIdentityReturnCode": 0,
        "appleDevelopmentIdentityCount": len(fingerprints),
        "signingAttempted": True,
        "signingTimedOut": signing_timeout,
        "lastSigningReturnCode": signing_return_code,
        "signingSucceeded": signing_succeeded,
        "strictVerifySucceeded": strict_verify,
        "appleDevelopmentAuthorityPresent": authority_present,
        "identityDetailsRedacted": True,
        "productionAcceptanceClaimed": False,
        "physicalAuthorityCreated": False,
    }
    print(SUCCESS_MARKER + json.dumps(receipt, sort_keys=True))
    return 0 if feasible else 43


def root_probe(expected_head: str, field_uid: int, field_gid: int) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "dedicated-UID Apple signing preflight requires root on macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing invoking sudo identity: {error}")
        return 71
    if sudo_uid != field_uid or sudo_gid != field_gid or field_uid <= 0 or field_gid <= 0:
        emit_error("identity", "root probe is not bound to the exact pre-sudo field UID/GID")
        return 71
    field_account = pwd.getpwuid(field_uid)
    if field_account.pw_name != sudo_user or field_account.pw_gid != field_gid:
        emit_error("identity", "sudo tuple does not resolve to the exact invoking field account")
        return 71

    uid = choose_ephemeral_id()
    name = f"nembrasign{os.getpid()}"
    workspace = Path(tempfile.mkdtemp(prefix="nembra-dedicated-signing-preflight.", dir="/private/tmp"))
    home = workspace / "home"
    fixture = home / "nembra-signing-fixture"
    identity_started = False
    evidence: dict[str, object] | None = None
    cleanup: dict[str, object] | None = None
    child_rc: int | None = None
    try:
        os.chmod(workspace, 0o710)
        home.mkdir()
        os.chown(workspace, 0, uid)
        os.chown(home, uid, uid)
        os.chmod(home, 0o700)
        create_identity(name, uid, home)
        identity_started = True
        env = dedicated_environment(name, home)
        os.chown(home / "tmp", uid, uid)
        os.chmod(home / "tmp", 0o700)
        baseline = sorted(group for group in os.getgrouplist(name, uid) if group != uid)

        if not SELF_SOURCE_B64:
            raise PreflightError("exact self source was not bound into the privileged probe")
        child_loader = (
            "import base64,json,sys;"
            "source=base64.b64decode(sys.argv[1],validate=True);"
            "ns={'__name__':'nembra_dedicated_signing_child','__file__':'<accepted-dedicated-signing-preflight>'};"
            "exec(compile(source,'<accepted-dedicated-signing-preflight>','exec',dont_inherit=True),ns);"
            "raise SystemExit(ns['_dedicated_child'](json.loads(sys.argv[2])))"
        )
        config = json.dumps(
            {
                "uid": uid,
                "gid": uid,
                "name": name,
                "groups": baseline,
                "fixture": str(fixture),
            },
            sort_keys=True,
        )
        try:
            child = run(
                ["/usr/bin/python3", "-B", "-I", "-c", child_loader, SELF_SOURCE_B64, config],
                env=env,
                timeout=55.0,
                user=uid,
                group=uid,
                extra_groups=[],
            )
        except subprocess.TimeoutExpired:
            raise PreflightError("dedicated signing child exceeded the bounded noninteractive window")
        child_rc = child.returncode
        markers = [line for line in child.stdout.splitlines() if line.startswith(SUCCESS_MARKER)]
        if len(markers) != 1:
            raise PreflightError("dedicated signing child produced no unique redacted evidence record")
        evidence = json.loads(markers[0][len(SUCCESS_MARKER):])
        if not evidence.get("identityDetailsRedacted"):
            raise PreflightError("dedicated signing child did not assert identity redaction")
        if evidence.get("productionAcceptanceClaimed") or evidence.get("physicalAuthorityCreated"):
            raise PreflightError("dedicated signing child crossed the validation truth boundary")
    except Exception as error:
        emit_error("probe", f"dedicated-UID Apple signing preflight failed: {type(error).__name__}: {error}")
        child_rc = 79
    finally:
        if identity_started:
            try:
                cleanup = remove_identity_strict(name, uid)
            except Exception as cleanup_error:
                emit_error(
                    "cleanup",
                    f"dedicated signing principal could not be retired cleanly: {type(cleanup_error).__name__}: {cleanup_error}",
                )
                child_rc = 80
        else:
            # A mid-creation failure can still leave a partial record. Remove both names
            # independently and verify direct absence before leaving the privileged phase.
            try:
                run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
                run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
                flush_directory_cache()
                if ds_record_exists("Users", name) or ds_record_exists("Groups", name):
                    raise PreflightError("partial dedicated signing principal survived fallback cleanup")
            except Exception as cleanup_error:
                emit_error(
                    "cleanup",
                    f"partial dedicated signing principal cleanup failed: {type(cleanup_error).__name__}: {cleanup_error}",
                )
                child_rc = 80
        shutil.rmtree(workspace, ignore_errors=True)

    if evidence is None or cleanup is None or child_rc is None:
        return child_rc or 79
    receipt = {
        "schemaVersion": 1,
        "exactValidationHead": expected_head,
        "exactProductionParent": PRODUCTION_PARENT,
        "topology": "fresh-dedicated-uid-gid-and-home",
        "fieldUIDUsedForSigning": False,
        "dedicatedUIDUsedForSigning": True,
        "dedicatedHomeUsedForSigning": True,
        "credentialTopologyExact": bool(evidence.get("credentialTopologyExact")),
        "classification": evidence.get("classification"),
        "securityFindIdentityReturnCode": evidence.get("securityFindIdentityReturnCode"),
        "appleDevelopmentIdentityCount": evidence.get("appleDevelopmentIdentityCount"),
        "signingAttempted": evidence.get("signingAttempted"),
        "signingTimedOut": evidence.get("signingTimedOut", False),
        "lastSigningReturnCode": evidence.get("lastSigningReturnCode"),
        "signingSucceeded": evidence.get("signingSucceeded"),
        "strictVerifySucceeded": evidence.get("strictVerifySucceeded"),
        "appleDevelopmentAuthorityPresent": evidence.get("appleDevelopmentAuthorityPresent"),
        "identityDetailsRedacted": True,
        "cleanup": cleanup,
        "xcodebuildExercised": False,
        "automaticProvisioningExercised": False,
        "privateTuyaInputExercised": False,
        "deviceDiscoveryExercised": False,
        "deviceInstallExercised": False,
        "bluetoothExercised": False,
        "productionBytesChanged": False,
        "productionAcceptanceClaimed": False,
        "physicalAuthorityCreated": False,
    }
    print(SUCCESS_MARKER + json.dumps(receipt, sort_keys=True))
    # An absent/unusable identity is a substantive red classification, so keep a
    # nonzero field-preflight status. The receipt remains available for diagnosis.
    return 0 if evidence.get("classification") == "dedicated_uid_apple_signing_feasible" else (child_rc or 81)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def parent_probe(expected_head: str) -> int:
    if sys.platform != "darwin":
        emit_error("environment", "run this preflight only on the private macOS field machine")
        return 82
    if os.getuid() <= 0 or os.geteuid() != os.getuid() or os.getegid() != os.getgid():
        emit_error("identity", "invoke the preflight as one ordinary non-root field account")
        return 82
    if re.fullmatch(r"[0-9a-fA-F]{40}", expected_head) is None:
        emit_error("arguments", "--expected-head must be one exact 40-hex accepted validation SHA")
        return 83
    expected_head = expected_head.lower()
    root = repo_root()
    physical_source = Path(__file__).read_bytes()

    head = run(["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"])
    if head.returncode != 0 or head.stdout.strip().lower() != expected_head:
        emit_error("source", "checkout HEAD does not equal the requested exact validation head")
        return 84
    status = run(["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"])
    if status.returncode != 0 or status.stdout.strip():
        emit_error("source", "field checkout is not clean")
        return 84
    ancestor = run(["/usr/bin/git", "-C", str(root), "merge-base", PRODUCTION_PARENT, expected_head])
    if ancestor.returncode != 0 or ancestor.stdout.strip().lower() != PRODUCTION_PARENT:
        emit_error("source", "validation head is not an exact descendant of the pinned production parent")
        return 84
    blob = run(["/usr/bin/git", "-C", str(root), "rev-parse", f"{expected_head}:{RELATIVE_PATH}"])
    accepted_blob = blob.stdout.strip().lower()
    if blob.returncode != 0 or re.fullmatch(r"[0-9a-f]{40}", accepted_blob) is None:
        emit_error("source", "accepted preflight blob identity is unavailable")
        return 84
    if git_blob_oid(physical_source) != accepted_blob:
        emit_error("source", "physical preflight bytes differ from the exact accepted Git blob")
        return 84
    if run(["/usr/bin/sudo", "-n", "/usr/bin/true"]).returncode != 0:
        emit_error("environment", "noninteractive sudo is required only for ephemeral principal lifecycle")
        return 85

    encoded = base64.b64encode(physical_source).decode("ascii")
    loader = (
        "import base64,sys;"
        "source=base64.b64decode(sys.argv[1],validate=True);"
        "ns={'__name__':'nembra_dedicated_signing_root','__file__':'<accepted-dedicated-signing-preflight>'};"
        "exec(compile(source,'<accepted-dedicated-signing-preflight>','exec',dont_inherit=True),ns);"
        "ns['SELF_SOURCE_B64']=sys.argv[1];"
        "raise SystemExit(ns['root_probe'](sys.argv[2],int(sys.argv[3]),int(sys.argv[4])))"
    )
    completed = run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            "-c",
            loader,
            encoded,
            expected_head,
            str(os.getuid()),
            str(os.getgid()),
        ],
        timeout=90.0,
    )
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    return completed.returncode


def self_test() -> int:
    synthetic = "\n".join(
        [
            '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Example Person (ABCDE12345)"',
            '  2) 89ABCDEF0123456789ABCDEF0123456789ABCDEF "Apple Distribution: Example Person (ABCDE12345)"',
            '  3) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Duplicate (FGHIJ67890)"',
            "     2 valid identities found",
        ]
    )
    parsed = parse_apple_development_fingerprints(synthetic)
    if parsed != ["0123456789ABCDEF0123456789ABCDEF01234567"]:
        raise AssertionError(f"Apple Development parser produced unexpected result: {parsed}")
    if parse_apple_development_fingerprints("0 valid identities found"):
        raise AssertionError("zero-identity output was not classified as empty")
    public_shape = {
        "classification": "dedicated_uid_apple_identity_absent",
        "appleDevelopmentIdentityCount": 0,
        "identityDetailsRedacted": True,
    }
    encoded = json.dumps(public_shape, sort_keys=True)
    if "Example Person" in encoded or "ABCDE12345" in encoded or parsed[0] in encoded:
        raise AssertionError("synthetic identity detail escaped into public evidence")
    print("dedicated UID Apple signing preflight self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-head")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.expected_head:
        emit_error("arguments", "pass --expected-head with the exact accepted validation SHA")
        return 83
    return parent_probe(args.expected_head)


if __name__ == "__main__":
    raise SystemExit(main())
