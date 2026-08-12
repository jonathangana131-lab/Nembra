#!/usr/bin/env python3
"""Validation-only Apple Development signing-context bridge.

Exact parent #3137 proves that the real field UID can keep its exact field-group baseline while a
fresh primary GID alone grants pathname access to a root-hidden signing subject, and that direct
ad-hoc codesign can then quiesce through the accepted APFS freeze boundary.

This child asks one narrower next question on the same real-macOS surface: can that exact field-UID
+ fresh-primary-GID process see and use an installed Apple Development signing identity/private key
without restoring ordinary field pathname authority? The selected identity is never emitted raw;
only counts and one-way hashes of identity/team tokens are retained.

A green result proves signing-context feasibility only. It does not prove Automatic provisioning,
private Tuya input custody, embedded.mobileprovision selection, iOS entitlements, install, device,
Bluetooth, telemetry, commands, Final-GO, or physical scooter authority.
"""
from __future__ import annotations

import argparse
import grp
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Iterable

MARKER = "NEMBRA_FIELD_UID_APPLE_SIGNING_JSON="
ERROR_MARKER = "NEMBRA_FIELD_UID_APPLE_SIGNING_ERROR="
CHILD_MARKER = "NEMBRA_FIELD_UID_APPLE_SIGNING_CHILD_JSON="


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


def credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise ProbeError("credential transition requires positive non-root UID/GID")
    normalized = sorted({int(group) for group in groups if int(group) != gid})
    if any(group <= 0 for group in normalized):
        raise ProbeError("credential transition contains invalid/root supplementary authority")
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
    raise ProbeError("could not allocate a fresh signing pathname GID")


def tree_fingerprint(root: Path) -> str:
    digest = hashlib.sha256()
    if not root.is_dir() or root.is_symlink():
        raise ProbeError("Apple signing subject is not one real directory")
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        rel = path.relative_to(root).as_posix().encode("utf-8")
        info = path.lstat()
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            kind, payload = b"L", os.readlink(path).encode("utf-8")
        elif stat.S_ISDIR(info.st_mode):
            kind, payload = b"D", b""
        elif stat.S_ISREG(info.st_mode):
            kind, payload = b"F", path.read_bytes()
        else:
            raise ProbeError(f"unexpected signing-subject node type: {path}")
        digest.update(kind + b"\0" + rel + b"\0")
        digest.update(f"{mode:o}".encode("ascii") + b"\0")
        digest.update(hashlib.sha256(payload).digest() + b"\0")
    return digest.hexdigest()


def make_unsigned_app(app: Path, capability_gid: int) -> None:
    contents = app / "Contents"
    macos = contents / "MacOS"
    macos.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(
        plistlib.dumps(
            {
                "CFBundleExecutable": "AppleSignerProof",
                "CFBundleIdentifier": "com.nembra.validation.applesignerproof",
                "CFBundleName": "AppleSignerProof",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
            },
            fmt=plistlib.FMT_XML,
            sort_keys=True,
        )
    )
    executable = macos / "AppleSignerProof"
    compiled = subprocess.run(
        ["/usr/bin/xcrun", "clang", "-x", "c", "-o", str(executable), "-"],
        input="int main(void) { return 0; }\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if compiled.returncode != 0:
        raise ProbeError("could not compile Apple-signing Mach-O fixture: " + compiled.stderr.strip())
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


def signer_child_code() -> str:
    return r'''
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

app = Path(sys.argv[1])
probe = app / "Contents" / "apple-signer-path-probe.tmp"
record = {
    "realUID": os.getuid(),
    "effectiveUID": os.geteuid(),
    "realPrimaryGID": os.getgid(),
    "effectivePrimaryGID": os.getegid(),
    "rawSupplementaryGroups": sorted(os.getgroups()),
    "pathWriteSucceeded": False,
    "pathCleanupSucceeded": False,
    "appleDevelopmentIdentityCount": 0,
    "codesignReturnCode": None,
}
try:
    probe.write_text("NEMBRA_APPLE_SIGNER_PATH_PROBE\n", encoding="utf-8")
    record["pathWriteSucceeded"] = True
    probe.unlink()
    record["pathCleanupSucceeded"] = True
except OSError as error:
    record["pathWriteErrno"] = error.errno
    record["pathWriteError"] = str(error)
    print("NEMBRA_FIELD_UID_APPLE_SIGNING_CHILD_JSON=" + json.dumps(record, sort_keys=True))
    raise SystemExit(72)

identities = subprocess.run(
    ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    check=False,
)
record["securityFindIdentityReturnCode"] = identities.returncode
identity_pattern = re.compile(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(Apple Development:[^"]+)"\s*$')
candidates = []
for line in identities.stdout.splitlines():
    match = identity_pattern.match(line)
    if match:
        candidates.append((match.group(1).upper(), match.group(2)))
candidates = sorted(set(candidates))
record["appleDevelopmentIdentityCount"] = len(candidates)
if not candidates:
    record["identityDiscoveryErrorPresent"] = bool(identities.stderr.strip())
    print("NEMBRA_FIELD_UID_APPLE_SIGNING_CHILD_JSON=" + json.dumps(record, sort_keys=True))
    raise SystemExit(73)

fingerprint, label = candidates[0]
record["selectedIdentityFingerprintSHA256"] = hashlib.sha256(fingerprint.encode("ascii")).hexdigest()
record["selectedIdentityLabelSHA256"] = hashlib.sha256(label.encode("utf-8")).hexdigest()

def redact(text):
    value = text.replace(fingerprint, "<identity-fingerprint>")
    for other_fingerprint, other_label in candidates:
        value = value.replace(other_fingerprint, "<identity-fingerprint>")
        value = value.replace(other_label, "Apple Development:<redacted>")
    value = re.sub(r'Apple Development:[^\n"]+', 'Apple Development:<redacted>', value)
    return value[-4000:]

signed = subprocess.run(
    ["/usr/bin/codesign", "--force", "--sign", fingerprint, "--timestamp=none", str(app)],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    check=False,
)
record["codesignReturnCode"] = signed.returncode
if signed.returncode != 0:
    record["codesignDiagnostic"] = redact((signed.stdout or "") + "\n" + (signed.stderr or ""))
    print("NEMBRA_FIELD_UID_APPLE_SIGNING_CHILD_JSON=" + json.dumps(record, sort_keys=True))
    raise SystemExit(74)

inspection = subprocess.run(
    ["/usr/bin/codesign", "-d", "--verbose=4", str(app)],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    check=False,
)
combined = (inspection.stdout or "") + "\n" + (inspection.stderr or "")
record["signatureInspectionReturnCode"] = inspection.returncode
record["appleDevelopmentAuthorityPresent"] = "Authority=Apple Development:" in combined
record["adHocSignaturePresent"] = "Signature=adhoc" in combined
identifier_match = re.search(r'^Identifier=(.+)$', combined, re.MULTILINE)
record["signedIdentifier"] = identifier_match.group(1).strip() if identifier_match else None
team_match = re.search(r'^TeamIdentifier=([^\n]+)$', combined, re.MULTILINE)
team = team_match.group(1).strip() if team_match else ""
record["teamIdentifierPresent"] = bool(team and team != "not set")
record["teamIdentifierSHA256"] = hashlib.sha256(team.encode("utf-8")).hexdigest() if team else None
print("NEMBRA_FIELD_UID_APPLE_SIGNING_CHILD_JSON=" + json.dumps(record, sort_keys=True))
raise SystemExit(0)
'''


def run_signer_child(
    app: Path,
    *,
    environment: dict[str, str],
    field_uid: int,
    capability_gid: int,
) -> tuple[int, dict[str, object], str]:
    completed = subprocess.run(
        ["/usr/bin/python3", "-B", "-I", "-c", signer_child_code(), str(app)],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **credentials(field_uid, capability_gid, []),
    )
    records = [
        line[len(CHILD_MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(CHILD_MARKER)
    ]
    if len(records) != 1:
        raise ProbeError(
            "Apple signing child did not return one canonical record: "
            + (completed.stdout + "\n" + completed.stderr)[-4000:]
        )
    try:
        record = json.loads(records[0])
    except json.JSONDecodeError as error:
        raise ProbeError("Apple signing child returned malformed JSON") from error
    if not isinstance(record, dict):
        raise ProbeError("Apple signing child returned a non-object record")
    diagnostic = (completed.stderr or "")[-2000:]
    return completed.returncode, record, diagnostic


def root_probe(field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "Apple Development signing root probe requires sudo on macOS")
        return 70
    for tool in ("/usr/bin/codesign", "/usr/bin/security", "/usr/bin/xcrun", "/usr/bin/python3"):
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
        emit_error("identity", "field identity must be non-root")
        return 71
    try:
        account = pwd.getpwuid(field_uid)
    except KeyError:
        emit_error("identity", "field UID has no local account")
        return 71
    if account.pw_name != field_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo identity does not match the local field account")
        return 71

    directory_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    if any(group <= 0 for group in directory_groups):
        emit_error("identity", "field account exposes root/invalid Directory Services group")
        return 71
    if any(group <= 0 for group in field_active_groups) or field_gid in field_active_groups:
        emit_error("identity", "captured pre-sudo active group vector is invalid")
        return 71
    if not set(field_active_groups).issubset(directory_groups):
        emit_error("identity", "captured active groups exceed Directory Services membership")
        return 71
    field_baseline = sorted(set([field_gid, *field_active_groups]))
    capability_gid = choose_capability_gid([*directory_groups, field_gid])

    workspace = Path(tempfile.mkdtemp(prefix="nembra-field-uid-apple-signing.", dir="/private/tmp"))
    app = workspace / "AppleSignerProof.app"
    try:
        os.chown(workspace, 0, capability_gid)
        os.chmod(workspace, 0o710)
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
            **credentials(field_uid, field_gid, field_active_groups),
        )
        if ordinary_attack.returncode == 0 or tree_fingerprint(app) != unsigned:
            emit_error("field-isolation", "ordinary field identity mutated Apple signing subject")
            return 72

        child_rc, signer, child_stderr = run_signer_child(
            app,
            environment=field_environment,
            field_uid=field_uid,
            capability_gid=capability_gid,
        )
        raw_groups = signer.get("rawSupplementaryGroups")
        if not isinstance(raw_groups, list) or any(not isinstance(group, int) for group in raw_groups):
            emit_error("signer-identity", "signing child did not expose one integer kernel group vector", signer=signer)
            return 73
        normalized = sorted({group for group in raw_groups if group != capability_gid})
        unexpected = sorted(set(normalized).difference(field_baseline))
        missing = sorted(set(field_baseline).difference(normalized))
        signer["capturedFieldBaselineGroups"] = field_baseline
        signer["normalizedSupplementaryGroups"] = normalized
        signer["unexpectedGroupsBeyondFieldBaseline"] = unexpected
        signer["missingFieldBaselineGroups"] = missing
        signer["fieldBaselinePreservedExact"] = not unexpected and not missing
        identity_ok = (
            signer.get("realUID") == field_uid
            and signer.get("effectiveUID") == field_uid
            and signer.get("realPrimaryGID") == capability_gid
            and signer.get("effectivePrimaryGID") == capability_gid
            and not unexpected
            and not missing
            and signer.get("pathWriteSucceeded") is True
            and signer.get("pathCleanupSucceeded") is True
        )
        if not identity_ok:
            emit_error("signer-identity", "Apple signing child violated field-baseline + fresh-primary-GID contract", signer=signer)
            return 73
        if child_rc != 0:
            kind = "apple-identity-unavailable" if child_rc == 73 else "apple-codesign"
            emit_error(
                kind,
                f"Apple signing child failed after credential/path attestation: {child_rc}",
                signer=signer,
                childDiagnostic=child_stderr,
            )
            return child_rc

        signed = tree_fingerprint(app)
        verify = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        semantic = (
            signer.get("appleDevelopmentIdentityCount", 0) >= 1
            and isinstance(signer.get("selectedIdentityFingerprintSHA256"), str)
            and len(signer.get("selectedIdentityFingerprintSHA256")) == 64
            and isinstance(signer.get("selectedIdentityLabelSHA256"), str)
            and len(signer.get("selectedIdentityLabelSHA256")) == 64
            and signer.get("codesignReturnCode") == 0
            and signer.get("signatureInspectionReturnCode") == 0
            and signer.get("appleDevelopmentAuthorityPresent") is True
            and signer.get("adHocSignaturePresent") is False
            and signer.get("signedIdentifier") == "com.nembra.validation.applesignerproof"
            and signer.get("teamIdentifierPresent") is True
            and isinstance(signer.get("teamIdentifierSHA256"), str)
            and len(signer.get("teamIdentifierSHA256")) == 64
            and verify.returncode == 0
            and signed != unsigned
        )
        if not semantic:
            emit_error(
                "apple-signature-semantics",
                "Apple signing child did not produce one verifiable non-ad-hoc Apple Development signature",
                signer=signer,
                verifyReturnCode=verify.returncode,
                verifyDiagnostic=verify.stderr[-3000:],
            )
            return 75

        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "capturedFieldBaselineGroups": field_baseline,
            "signingCapabilityGID": capability_gid,
            "fieldDirectoryGroupsContainSigningCapability": capability_gid in directory_groups,
            "fieldActiveGroupsContainSigningCapability": capability_gid in field_active_groups,
            "ordinaryFieldAttackReturnCode": ordinary_attack.returncode,
            "signer": signer,
            "strictVerifyReturnCode": verify.returncode,
            "unsignedTreeSHA256": unsigned,
            "appleSignedTreeSHA256": signed,
            "identityDetailsRedacted": True,
            "automaticProvisioningExercised": False,
            "privateTuyaInputExercised": False,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except Exception as error:
        emit_error("fixture", f"Apple Development signing fixture failed: {type(error).__name__}: {error}")
        return 80
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "Apple Development signing probe requires macOS")
        return 81
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "field parent requires one stable non-root UID/GID")
        return 81
    field_active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "field parent carries root/invalid active group authority")
        return 81
    if subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 81

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
        emit_error("evidence", "missing or ambiguous Apple signing success record")
        return 82
    evidence = json.loads(records[0])
    signer = evidence.get("signer")
    expected_baseline = sorted(set([field_gid, *field_active_groups]))
    capability_gid = evidence.get("signingCapabilityGID")
    required = (
        evidence.get("schemaVersion") == 1
        and evidence.get("fieldUID") == field_uid
        and evidence.get("fieldPrimaryGID") == field_gid
        and evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
        and evidence.get("capturedFieldBaselineGroups") == expected_baseline
        and isinstance(capability_gid, int)
        and capability_gid > 0
        and capability_gid != field_gid
        and evidence.get("fieldDirectoryGroupsContainSigningCapability") is False
        and evidence.get("fieldActiveGroupsContainSigningCapability") is False
        and evidence.get("ordinaryFieldAttackReturnCode") != 0
        and isinstance(signer, dict)
        and signer.get("realUID") == field_uid
        and signer.get("effectiveUID") == field_uid
        and signer.get("realPrimaryGID") == capability_gid
        and signer.get("effectivePrimaryGID") == capability_gid
        and signer.get("capturedFieldBaselineGroups") == expected_baseline
        and signer.get("normalizedSupplementaryGroups") == expected_baseline
        and signer.get("fieldBaselinePreservedExact") is True
        and signer.get("unexpectedGroupsBeyondFieldBaseline") == []
        and signer.get("missingFieldBaselineGroups") == []
        and signer.get("pathWriteSucceeded") is True
        and signer.get("pathCleanupSucceeded") is True
        and signer.get("appleDevelopmentIdentityCount", 0) >= 1
        and signer.get("codesignReturnCode") == 0
        and signer.get("signatureInspectionReturnCode") == 0
        and signer.get("appleDevelopmentAuthorityPresent") is True
        and signer.get("adHocSignaturePresent") is False
        and signer.get("signedIdentifier") == "com.nembra.validation.applesignerproof"
        and signer.get("teamIdentifierPresent") is True
        and evidence.get("strictVerifyReturnCode") == 0
        and evidence.get("unsignedTreeSHA256") != evidence.get("appleSignedTreeSHA256")
        and evidence.get("identityDetailsRedacted") is True
        and evidence.get("automaticProvisioningExercised") is False
        and evidence.get("privateTuyaInputExercised") is False
        and evidence.get("productionAcceptanceClaimed") is False
        and evidence.get("physicalAuthorityCreated") is False
    )
    if not required:
        emit_error("evidence", f"Apple signing success record failed semantic acceptance: {evidence}")
        return 83
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires one counted pre-sudo active-group vector")
            return 84
        return root_probe(args.field_active_group)
    if args.field_active_group or args.field_active_group_count is not None:
        emit_error("arguments", "root-only group arguments are unavailable in parent mode")
        return 84
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
