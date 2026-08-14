#!/usr/bin/python3 -I
"""Administrator-installed privileged entrypoint for Nembra Capture.

SOURCE BYTES ARE NOT PRIVILEGED AUTHORITY MERELY BECAUSE THEY LIVE IN GIT.

This program becomes an authority boundary only after a human administrator installs
reviewed bytes at the compiled canonical broker path and separately installs a root-owned
policy at POLICY_PATH. The field checkout cannot select either path, authorize a source
SHA, authorize a root subject, select the root entry subject, install this broker, or
spend sudo from this program.

The broker authenticates the COMPLETE privileged Python subject bundle against the
independently installed policy before executing the one policy-selected entry subject.
Candidate/helper bytes arrive only as data on stdin. A matching digest in a field-owned
file, Git object database, environment variable, command argument, workflow, or candidate
manifest is never sufficient authority.

The accepted entry subject receives an immutable NEMBRA_APPROVED_ROOT_SUBJECTS mapping
containing only the fully policy-verified bytes. A later production composition must be
source-reviewed to consume privileged helper bytes from that mapping and to reject any
alternate candidate-controlled root loader. The broker itself does not implement product,
device, signing, compiler, filesystem-custody, account-management, or scooter operations.
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
from types import MappingProxyType
from typing import Any, Mapping, Sequence


CANONICAL_BROKER_PATH = Path("/Library/PrivilegedHelperTools/com.nembra.capture-root-broker")
POLICY_PATH = Path("/Library/NembraCaptureAuthority/v1/policy.json")
POLICY_ROOT = Path("/Library/NembraCaptureAuthority/v1")
POLICY_SCHEMA = 1
BUNDLE_SCHEMA = 1
MAX_POLICY_BYTES = 64 * 1024
MAX_BUNDLE_BYTES = 4 * 1024 * 1024
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
            raise BrokerError(f"JSON contains duplicate key: {key}")
        result[key] = value
    return result


def _strict_json_object(raw: bytes, *, label: str, maximum_bytes: int) -> dict[str, Any]:
    _require(0 < len(raw) <= maximum_bytes, f"{label} size is invalid")
    try:
        decoded = raw.decode("utf-8", errors="strict")
        value = json.loads(decoded, object_pairs_hook=_duplicate_rejecting_object)
    except BrokerError:
        raise
    except Exception as error:
        raise BrokerError(f"{label} is not strict UTF-8 JSON") from error
    _require(isinstance(value, dict), f"{label} root must be an object")
    return value


def _parse_policy_bytes(raw: bytes) -> dict[str, Any]:
    policy = _strict_json_object(raw, label="policy", maximum_bytes=MAX_POLICY_BYTES)
    _require(
        set(policy) == {"schema", "authorizedSourceSHA", "entrySubject", "subjects"},
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

    entry_subject = policy["entrySubject"]
    _require(
        isinstance(entry_subject, str) and entry_subject in subjects,
        "policy entry subject is not one authorized subject",
    )
    return policy


def _validate_directory_stat(info: os.stat_result, label: str) -> None:
    _require(stat.S_ISDIR(info.st_mode), f"{label} is not a directory")
    _require(info.st_uid == 0 and info.st_gid == 0, f"{label} is not root:wheel owned")
    _require((stat.S_IMODE(info.st_mode) & 0o022) == 0, f"{label} is group/world writable")


def _validate_broker_stat(info: os.stat_result) -> None:
    _require(stat.S_ISREG(info.st_mode), "installed broker is not one regular file")
    _require(info.st_uid == 0 and info.st_gid == 0, "installed broker is not root:wheel owned")
    _require(stat.S_IMODE(info.st_mode) == 0o555, "installed broker mode must be exactly 0555")


def _validate_installed_broker() -> None:
    invoked_path = Path(os.path.abspath(__file__))
    _require(invoked_path == CANONICAL_BROKER_PATH, "broker is not executing from the canonical installed path")
    for path in (Path("/Library"), CANONICAL_BROKER_PATH.parent):
        try:
            info = os.lstat(path)
        except OSError as error:
            raise BrokerError(f"trusted broker directory is unavailable: {path}") from error
        _validate_directory_stat(info, str(path))
    try:
        broker_info = os.lstat(CANONICAL_BROKER_PATH)
    except OSError as error:
        raise BrokerError("canonical installed broker is unavailable") from error
    _validate_broker_stat(broker_info)


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

    _require(hasattr(os, "O_NOFOLLOW"), "platform lacks O_NOFOLLOW")
    flags = os.O_RDONLY | os.O_NOFOLLOW
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


def _decode_subject_payload(encoded: str, *, name: str) -> bytes:
    _require(isinstance(encoded, str) and encoded != "", f"approved subject {name} transport is empty")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise BrokerError(f"approved subject {name} transport is not strict base64") from error
    _require(0 < len(raw) <= MAX_SUBJECT_BYTES, f"approved subject {name} byte count is invalid")
    return raw


def _parse_and_authorize_bundle(policy: dict[str, Any], raw: bytes) -> Mapping[str, bytes]:
    bundle = _strict_json_object(raw, label="subject bundle", maximum_bytes=MAX_BUNDLE_BYTES)
    _require(
        set(bundle) == {"schema", "sourceSHA", "subjects"},
        "subject bundle contains missing or unknown fields",
    )
    _require(bundle["schema"] == BUNDLE_SCHEMA, "subject bundle schema is not accepted")
    source_sha = bundle["sourceSHA"]
    _require(
        isinstance(source_sha, str) and re.fullmatch(r"[0-9a-f]{40}", source_sha) is not None,
        "subject bundle source SHA is malformed",
    )
    _require(source_sha == policy["authorizedSourceSHA"], "subject bundle source SHA is not administrator-authorized")

    encoded_subjects = bundle["subjects"]
    _require(isinstance(encoded_subjects, dict), "subject bundle subjects must be an object")
    policy_subjects = policy["subjects"]
    _require(
        set(encoded_subjects) == set(policy_subjects),
        "subject bundle must contain exactly the administrator-authorized privileged subject set",
    )

    approved: dict[str, bytes] = {}
    for name in sorted(policy_subjects):
        payload = _decode_subject_payload(encoded_subjects[name], name=name)
        actual = hashlib.sha256(payload).hexdigest()
        expected = policy_subjects[name]["sha256"]
        _require(actual == expected, f"approved subject {name} bytes do not match administrator policy")
        approved[name] = payload
    return MappingProxyType(approved)


def _read_bundle_stdin() -> bytes:
    raw = sys.stdin.buffer.read(MAX_BUNDLE_BYTES + 1)
    _require(0 < len(raw) <= MAX_BUNDLE_BYTES, "subject bundle stdin size is invalid")
    _require(sys.stdin.buffer.read(1) == b"", "subject bundle stdin exceeds maximum size")
    return raw


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


def _execute_approved_python(
    policy: dict[str, Any],
    approved_subjects: Mapping[str, bytes],
    arguments: Sequence[str],
) -> int:
    argv = _validate_subject_arguments(arguments)
    entry_subject = policy["entrySubject"]
    _require(entry_subject in approved_subjects, "administrator entry subject is missing after bundle verification")
    payload = approved_subjects[entry_subject]
    _sanitize_root_environment()
    old_argv = sys.argv
    sys.argv = [f"<nembra-approved:{entry_subject}>", *argv]
    namespace: dict[str, Any] = {
        "__name__": "__main__",
        "__file__": f"<nembra-approved:{entry_subject}>",
        "NEMBRA_AUTHORIZED_SOURCE_SHA": policy["authorizedSourceSHA"],
        "NEMBRA_APPROVED_ROOT_SUBJECTS": approved_subjects,
    }
    try:
        code = compile(payload, f"<nembra-approved:{entry_subject}>", "exec", dont_inherit=True)
        exec(code, namespace)
        return 0
    finally:
        sys.argv = old_argv


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Nembra Capture administrator-rooted privileged broker")
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
        _validate_installed_broker()
        args = _parse(sys.argv[1:] if argv is None else argv)
        policy = _load_installed_policy()
        approved_subjects = _parse_and_authorize_bundle(policy, _read_bundle_stdin())
        return _execute_approved_python(policy, approved_subjects, args.subject_arguments)
    except BrokerError as error:
        print(f"NEMBRA_CAPTURE_ROOT_BROKER_REJECTED: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
