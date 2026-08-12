#!/usr/bin/env python3
"""Root-captured, root-sealed receipt authority for the Apple-signing preflight.

The accepted signing oracle still executes as the real field account so its keychain
context is truthful. This supervisor runs as root, captures that exact oracle's
stdout/stderr directly, applies the raw-identity backstop, and publishes the
canonical receipt into a root-owned namespace that the field account cannot mutate
or replace after the run.

Validation only: this helper does not bootstrap Tuya, run xcodebuild, provision or
register a device, use CoreDevice, install/launch an app, use Bluetooth, or touch a
scooter.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import stat
import subprocess
import sys

SUCCESS_MARKER = "NEMBRA_FIELD_UID_APPLE_SIGNING_JSON="
ERROR_MARKER = "NEMBRA_FIELD_UID_APPLE_SIGNING_ERROR="
RECEIPT_MARKER = "NEMBRA_FIELD_APPLE_SIGNING_PREFLIGHT_RECEIPT="
RAW_IDENTITY_PATTERN = re.compile(r"Apple Development:\s*[^<\s]")


class SealError(RuntimeError):
    pass


def git_blob_id(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def raw_identity_present(text: str) -> bool:
    return RAW_IDENTITY_PATTERN.search(text) is not None


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def credentials(uid: int, gid: int, groups: list[int]) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise SealError("field credential transition requires positive non-root UID/GID")
    normalized = sorted({int(group) for group in groups if int(group) != gid})
    if any(group <= 0 for group in normalized):
        raise SealError("field credential transition contains root/invalid supplementary authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def require_root_oracle(path: Path, expected_blob: str) -> None:
    info = path.lstat()
    if path.is_symlink() or not stat.S_ISREG(info.st_mode):
        raise SealError("accepted oracle execution subject is not one real regular file")
    if info.st_uid != 0 or info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o555:
        raise SealError("accepted oracle execution subject lost root 0555 custody")
    raw = path.read_bytes()
    if git_blob_id(raw) != expected_blob:
        raise SealError("accepted oracle execution subject no longer matches its Git blob")


def require_safe_receipt_parent(output: Path) -> Path:
    if not output.is_absolute() or output.name in {"", ".", ".."}:
        raise SealError("canonical receipt path must be one named absolute child")
    if os.path.lexists(output):
        raise SealError("canonical receipt path must not pre-exist")
    parent = output.parent
    if str(parent.resolve(strict=True)) != str(parent):
        raise SealError("canonical receipt parent must already be one real absolute path")
    info = parent.lstat()
    if parent.is_symlink() or not stat.S_ISDIR(info.st_mode) or info.st_uid != 0:
        raise SealError("canonical receipt parent must be one root-owned real directory")
    mode = stat.S_IMODE(info.st_mode)
    caller_writable = bool(mode & (stat.S_IWGRP | stat.S_IWOTH))
    if caller_writable and not bool(mode & stat.S_ISVTX):
        raise SealError("caller-writable receipt parent must be root-owned sticky")
    return parent


def write_root_file(path: Path, raw: bytes, mode: int = 0o444) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(path, flags, mode)
    try:
        with os.fdopen(fd, "wb", closefd=False) as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        os.close(fd)
    os.chown(path, 0, 0)
    os.chmod(path, mode)
    info = path.lstat()
    if path.is_symlink() or not stat.S_ISREG(info.st_mode):
        raise SealError(f"canonical receipt file is not regular: {path.name}")
    if info.st_uid != 0 or info.st_gid != 0 or stat.S_IMODE(info.st_mode) != mode:
        raise SealError(f"canonical receipt file metadata is invalid: {path.name}")


def run_field_attack(
    argv: list[str],
    *,
    uid: int,
    gid: int,
    groups: list[int],
    environment: dict[str, str],
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        argv,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        **credentials(uid, gid, groups),
    )


def seal_receipt(args: argparse.Namespace) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise SealError("canonical Apple-signing receipt sealer requires root on macOS")
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        raise SealError(f"missing exact pre-sudo field identity: {error}") from error
    if (sudo_uid, sudo_gid, sudo_user) != (args.field_uid, args.field_gid, args.field_user):
        raise SealError("root receipt sealer is not bound to the exact invoking field identity")
    if args.field_uid <= 0 or args.field_gid <= 0:
        raise SealError("field identity must be non-root")
    try:
        account = pwd.getpwuid(args.field_uid)
    except KeyError as error:
        raise SealError("field UID has no local account") from error
    if account.pw_name != args.field_user or account.pw_gid != args.field_gid:
        raise SealError("field identity does not match the local account")

    try:
        parsed_groups = json.loads(args.field_groups_json)
    except json.JSONDecodeError as error:
        raise SealError("field supplementary-group vector is malformed JSON") from error
    if not isinstance(parsed_groups, list) or any(not isinstance(group, int) for group in parsed_groups):
        raise SealError("field supplementary-group vector must contain only integers")
    field_groups = sorted({group for group in parsed_groups if group != args.field_gid})
    if any(group <= 0 for group in field_groups):
        raise SealError("field supplementary-group vector contains root/invalid authority")
    directory_groups = set(os.getgrouplist(account.pw_name, args.field_gid))
    if not set(field_groups).issubset(directory_groups):
        raise SealError("captured field groups exceed current Directory Services membership")

    if not re.fullmatch(r"[0-9a-f]{40}", args.source_sha):
        raise SealError("accepted source SHA is malformed")
    if not re.fullmatch(r"[0-9a-f]{40}", args.script_blob):
        raise SealError("accepted preflight blob is malformed")
    if not re.fullmatch(r"[0-9a-f]{40}", args.oracle_blob):
        raise SealError("accepted oracle blob is malformed")

    oracle = Path(args.oracle)
    require_root_oracle(oracle, args.oracle_blob)
    output = Path(args.output_dir)
    parent = require_safe_receipt_parent(output)

    field_environment = {
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
    }
    completed = subprocess.run(
        ["/usr/bin/python3", "-B", "-I", str(oracle)],
        env=field_environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        **credentials(args.field_uid, args.field_gid, field_groups),
    )
    probe_rc = int(completed.returncode)
    probe_text = (completed.stdout or b"").decode("utf-8", errors="replace")
    if raw_identity_present(probe_text):
        probe_text = "ERROR: preflight output was suppressed because raw Apple identity text escaped the oracle.\n"
        probe_rc = 90

    success_count = sum(line.startswith(SUCCESS_MARKER) for line in probe_text.splitlines())
    red_count = sum(line.startswith(ERROR_MARKER) for line in probe_text.splitlines())
    evidence_shape_valid = (probe_rc == 0 and success_count == 1 and red_count == 0) or (
        probe_rc != 0 and success_count == 0 and red_count >= 1
    )
    if not evidence_shape_valid:
        probe_text = (
            "NEMBRA_FIELD_UID_APPLE_SIGNING_ERROR="
            + json.dumps(
                {
                    "kind": "receipt-evidence-shape",
                    "message": "oracle output/return-code shape was ambiguous and was suppressed",
                    "physicalAuthorityCreated": False,
                },
                sort_keys=True,
            )
            + "\n"
        )
        probe_rc = 91
        success_count = 0
        red_count = 1

    probe_raw = probe_text.encode("utf-8")
    rc_raw = f"{probe_rc}\n".encode("ascii")
    created = False
    try:
        os.mkdir(output, 0o700)
        created = True
        os.chown(output, 0, 0)
        os.chmod(output, 0o700)
        info = output.lstat()
        if output.is_symlink() or not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_gid != 0:
            raise SealError("canonical receipt namespace lost root directory custody")

        probe_path = output / "probe-output.txt"
        rc_path = output / "probe-return-code.txt"
        manifest_path = output / "preflight-manifest.json"
        sums_path = output / "SHA256SUMS.txt"
        write_root_file(probe_path, probe_raw)
        write_root_file(rc_path, rc_raw)

        before_probe = probe_path.read_bytes()
        before_rc = rc_path.read_bytes()
        replacement = output.with_name(output.name + ".field-replace")
        if os.path.lexists(replacement):
            raise SealError("field-replacement negative target already exists")

        append_attack = run_field_attack(
            ["/bin/sh", "-c", 'printf "FIELD_RECEIPT_MUTATION\\n" >> "$1"', "sh", str(probe_path)],
            uid=args.field_uid,
            gid=args.field_gid,
            groups=field_groups,
            environment=field_environment,
        )
        rename_attack = run_field_attack(
            ["/bin/mv", str(output), str(replacement)],
            uid=args.field_uid,
            gid=args.field_gid,
            groups=field_groups,
            environment=field_environment,
        )
        if append_attack.returncode == 0 or probe_path.read_bytes() != before_probe:
            raise SealError("field identity retained mutation authority over canonical receipt bytes")
        if rename_attack.returncode == 0 or not output.is_dir() or os.path.lexists(replacement):
            raise SealError("field identity retained replacement authority over canonical receipt namespace")
        if rc_path.read_bytes() != before_rc:
            raise SealError("canonical return-code bytes changed during field attack")

        manifest = {
            "schemaVersion": 2,
            "authority": "capture-field-apple-signing-context-preflight-only",
            "exactSourceSHA": args.source_sha,
            "acceptedPreflightGitBlob": args.script_blob,
            "acceptedOracleGitBlob": args.oracle_blob,
            "fieldUID": args.field_uid,
            "fieldPrimaryGID": args.field_gid,
            "fieldSupplementaryGroups": field_groups,
            "probeReturnCode": probe_rc,
            "successEvidencePresent": success_count == 1,
            "redEvidencePresent": red_count >= 1,
            "identityDetailsRedacted": True,
            "canonicalReceiptSealed": True,
            "receiptOwnerUID": 0,
            "receiptOwnerGID": 0,
            "fieldAppendMutationDenied": append_attack.returncode != 0,
            "fieldNamespaceReplacementDenied": rename_attack.returncode != 0,
            "tuyaBootstrapExercised": False,
            "privateTuyaInputExercised": False,
            "xcodebuildExercised": False,
            "automaticProvisioningExercised": False,
            "deviceDiscoveryExercised": False,
            "coreDeviceExercised": False,
            "deviceInstallExercised": False,
            "bluetoothExercised": False,
            "physicalAuthorityCreated": False,
            "probeOutputSHA256": sha256(probe_raw),
        }
        manifest_raw = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
        write_root_file(manifest_path, manifest_raw)

        summed = {
            "probe-output.txt": probe_raw,
            "probe-return-code.txt": rc_raw,
            "preflight-manifest.json": manifest_raw,
        }
        sums_raw = "".join(
            f"{sha256(raw)}  {name}\n" for name, raw in summed.items()
        ).encode("ascii")
        write_root_file(sums_path, sums_raw)

        os.chown(output, 0, 0)
        os.chmod(output, 0o555)
        final_info = output.lstat()
        if output.is_symlink() or final_info.st_uid != 0 or final_info.st_gid != 0:
            raise SealError("canonical receipt namespace final owner is invalid")
        if stat.S_IMODE(final_info.st_mode) != 0o555:
            raise SealError("canonical receipt namespace final mode is not 0555")
        require_safe_parent_again = parent.lstat()
        parent_mode = stat.S_IMODE(require_safe_parent_again.st_mode)
        if parent.is_symlink() or require_safe_parent_again.st_uid != 0:
            raise SealError("canonical receipt parent changed during publication")
        if parent_mode & (stat.S_IWGRP | stat.S_IWOTH) and not parent_mode & stat.S_ISVTX:
            raise SealError("canonical receipt parent became caller-replaceable")
        for path in (probe_path, rc_path, manifest_path, sums_path):
            info = path.lstat()
            if path.is_symlink() or info.st_uid != 0 or info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o444:
                raise SealError(f"canonical receipt file final metadata is invalid: {path.name}")
        if probe_path.read_bytes() != probe_raw or rc_path.read_bytes() != rc_raw:
            raise SealError("canonical receipt evidence changed after final seal")
        if manifest_path.read_bytes() != manifest_raw or sums_path.read_bytes() != sums_raw:
            raise SealError("canonical receipt manifest/hash set changed after final seal")
    except BaseException:
        if created:
            try:
                os.chmod(output, 0o700)
                shutil.rmtree(output)
            except OSError:
                pass
        raise

    sys.stdout.write(probe_text)
    if probe_text and not probe_text.endswith("\n"):
        sys.stdout.write("\n")
    print(RECEIPT_MARKER + str(output))
    return probe_rc


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--oracle", required=True)
    parser.add_argument("--oracle-blob", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--script-blob", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--field-uid", type=int, required=True)
    parser.add_argument("--field-gid", type=int, required=True)
    parser.add_argument("--field-user", required=True)
    parser.add_argument("--field-groups-json", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return seal_receipt(args)
    except (OSError, SealError, subprocess.SubprocessError) as error:
        print(
            ERROR_MARKER
            + json.dumps(
                {
                    "kind": "receipt-seal",
                    "message": str(error),
                    "physicalAuthorityCreated": False,
                },
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 92


if __name__ == "__main__":
    raise SystemExit(main())
