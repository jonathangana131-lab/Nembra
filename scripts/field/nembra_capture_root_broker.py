#!/usr/bin/python3 -I
"""Administrator-installed privileged entrypoint for Nembra Capture.

SOURCE BYTES ARE NOT PRIVILEGED AUTHORITY MERELY BECAUSE THEY LIVE IN GIT.

This program becomes an authority boundary only after a human administrator installs
reviewed bytes at the canonical root-owned broker path and separately installs a
root-owned policy at POLICY_PATH. The field checkout cannot select a policy path,
authorize a source SHA, authorize a root subject, install this broker, or spend sudo
from this program.

The broker has one intentionally narrow job: authenticate an exact root-executed Python
subject against the independently installed policy, then execute those already-approved
bytes in this root process. Candidate/helper bytes arrive as data. A matching digest in a
field-owned file, Git object database, environment variable, command argument, or workflow
is never sufficient authority.

No device, Bluetooth, Tuya, Apple signing, xcodebuild, APFS, Directory Services, or scooter
operation is implemented here. Those operations remain the responsibility of separately
reviewed policy-approved subjects and their own truth contracts.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
from typing import Any, Sequence


POLICY_PATH = Path("/Library/NembraCaptureAuthority/v1/policy.json")
POLICY_ROOT = Path("/Library/NembraCaptureAuthority/v1")
POLICY_SCHEMA = 1
MAX_POLICY_BYTES = 64 * 1024
MAX_SUBJECT_BYTES = 2 * 1024 * 1024
MAX_SUBJECTS = 16
MAX_ARGUMENTS = 256
MAX_ARGUMENT_BYTES = 64 * 1024
SUBJECT_KIND = "python-root"


class BrokerError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise BrokerError(message)


def _duplicate_rejecting_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise BrokerError(f"policy contains duplicate key: {key}")
        result[key] = value
    return result


def _parse_policy_bytes(raw: bytes) -> dict[str, Any]:
    _require(0 < len(raw) <= MAX_POLICY_BYTES, "policy size is invalid")
    try:
        decoded = raw.decode("utf-8", errors="strict")
        policy = json.loads(decoded, object_pairs_hook=_duplicate_rejecting_object)
    except BrokerError:
        raise
    except Exception as error:
        raise BrokerError("policy is not strict UTF-8 JSON") from error

    _require(isinstance(policy, dict), "policy root must be an object")
    _require(
        set(policy) == {"schema", "authorizedSourceSHA", "subjects"},
        "policy root contains missing or unknown fields",
    )
    _require(policy["schema"] == POLICY_SCHEMA, "policy schema is not accepted")

    source_sha = policy["authorizedSourceSHA"]
    _require(
        isinstance(source_sha, str) and re.fullmatch(r"[0-9a-f]{40}", source_sha) is not None,
        "authorized source SHA is malformed",
    )

    subjects = policy["subjects"]
    _require(isinstance(subjects, dict), "policy subjects must be an object")
    _require(0 < len(subjects) <= MAX_SUBJECTS, "policy subject count is invalid")
    for name, contract in subjects.items():
        _require(
            isinstance(name, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", name) is not None,
            "policy subject name is malformed",
        )
        _require(isinstance(contract, dict), f"policy subject {name} contract is malformed")
        _require(
            set(contract) == {"sha256", "kind"},
            f"policy subject {name} contains missing or unknown fields",
        )
        _require(contract["kind"] == SUBJECT_KIND, f"policy subject {name} kind is not accepted")
        digest = contract["sha256"]
        _require(
            isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
            f"policy subject {name} digest is malformed",
        )
    return policy


def _validate_directory_stat(info: os.stat_result, label: str) -> None:
    _require(stat.S_ISDIR(info.st_mode), f"{label} is not a directory")
    _require(info.st_uid == 0 and info.st_gid == 0, f"{label} is not root:wheel owned")
    _require((stat.S_IMODE(info.st_mode) & 0o022) == 0, f"{label} is group/world writable")


def _validate_policy_stat(info: os.stat_result) -> None:
    _require(stat.S_ISREG(info.st_mode), "policy is not a regular file")
    _require(info.st_uid == 0 and info.st_gid == 0, "policy is not root:wheel owned")
    _require(stat.S_IMODE(info.st_mode) == 0o444, "policy mode must be exactly 0444")


def _load_installed_policy() -> dict[str, Any]:
    _require(POLICY_PATH.parent == POLICY_ROOT, "compiled policy root invariant changed")
    for path in (Path("/Library"), Path("/Library/NembraCaptureAuthority"), POLICY_ROOT):
        try:
            info = os.lstat(path)
        except OSError as error:
            raise BrokerError(f"trusted policy directory is unavailable: {path}") from error
        _validate_directory_stat(info, str(path))

    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(POLICY_PATH, flags)
    except OSError as error:
        raise BrokerError("trusted policy could not be opened without following links") from error
    try:
        info = os.fstat(fd)
        _validate_policy_stat(info)
        raw = os.read(fd, MAX_POLICY_BYTES + 1)
        _require(len(raw) <= MAX_POLICY_BYTES, "policy exceeds maximum size")
        _require(os.read(fd, 1) == b"", "policy changed while being read")
    finally:
        os.close(fd)
    return _parse_policy_bytes(raw)


def _decode_subject_payload(encoded: str) -> bytes:
    _require(isinstance(encoded, str) and encoded != "", "approved subject transport is empty")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise BrokerError("approved subject transport is not strict base64") from error
    _require(0 < len(raw) <= MAX_SUBJECT_BYTES, "approved subject byte count is invalid")
    return raw


def _authorize_subject(
    policy: dict[str, Any],
    *,
    source_sha: str,
    subject_name: str,
    payload: bytes,
) -> bytes:
    _require(re.fullmatch(r"[0-9a-f]{40}", source_sha) is not None, "requested source SHA is malformed")
    _require(source_sha == policy["authorizedSourceSHA"], "requested source SHA is not administrator-authorized")
    subjects = policy["subjects"]
    _require(subject_name in subjects, "requested root subject is not administrator-authorized")
    contract = subjects[subject_name]
    _require(contract["kind"] == SUBJECT_KIND, "requested root subject kind is not executable")
    actual = hashlib.sha256(payload).hexdigest()
    _require(actual == contract["sha256"], "requested root subject bytes do not match administrator policy")
    return payload


def _sanitize_root_environment() -> None:
    preserved: dict[str, str] = {}
    for name in ("SUDO_UID", "SUDO_GID"):
        value = os.environ.get(name)
        if value is not None:
            _require(re.fullmatch(r"[0-9]+", value) is not None, f"{name} is malformed")
            preserved[name] = value
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user is not None:
        _require(re.fullmatch(r"[A-Za-z0-9._-]+", sudo_user) is not None, "SUDO_USER is malformed")
        preserved["SUDO_USER"] = sudo_user

    os.environ.clear()
    os.environ.update(
        {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            **preserved,
        }
    )


def _validate_subject_arguments(arguments: Sequence[str]) -> list[str]:
    _require(len(arguments) <= MAX_ARGUMENTS, "approved subject argument count is excessive")
    total = 0
    result: list[str] = []
    for value in arguments:
        _require(isinstance(value, str), "approved subject argument is not text")
        _require("\x00" not in value, "approved subject argument contains NUL")
        total += len(value.encode("utf-8", errors="strict"))
        _require(total <= MAX_ARGUMENT_BYTES, "approved subject arguments exceed size limit")
        result.append(value)
    return result


def _execute_approved_python(subject_name: str, payload: bytes, arguments: Sequence[str]) -> int:
    argv = _validate_subject_arguments(arguments)
    _sanitize_root_environment()
    old_argv = sys.argv
    sys.argv = [f"<nembra-approved:{subject_name}>", *argv]
    namespace: dict[str, Any] = {
        "__name__": "__main__",
        "__file__": f"<nembra-approved:{subject_name}>",
    }
    try:
        code = compile(payload, f"<nembra-approved:{subject_name}>", "exec", dont_inherit=True)
        exec(code, namespace)
        return 0
    finally:
        sys.argv = old_argv


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Nembra Capture administrator-rooted privileged broker")
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--payload-base64", required=True)
    parser.add_argument("subject_arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    if args.subject_arguments and args.subject_arguments[0] == "--":
        args.subject_arguments = args.subject_arguments[1:]
    return args


def main(argv: Sequence[str] | None = None) -> int:
    try:
        _require(sys.flags.isolated == 1, "privileged broker requires isolated Python (-I)")
        _require(sys.platform == "darwin", "privileged broker requires macOS")
        _require(os.geteuid() == 0 and os.getuid() == 0, "privileged broker requires real/effective uid 0")
        args = _parse(sys.argv[1:] if argv is None else argv)
        policy = _load_installed_policy()
        payload = _decode_subject_payload(args.payload_base64)
        approved = _authorize_subject(
            policy,
            source_sha=args.source_sha.lower(),
            subject_name=args.subject,
            payload=payload,
        )
        return _execute_approved_python(args.subject, approved, args.subject_arguments)
    except BrokerError as error:
        print(f"NEMBRA_CAPTURE_ROOT_BROKER_REJECTED: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
