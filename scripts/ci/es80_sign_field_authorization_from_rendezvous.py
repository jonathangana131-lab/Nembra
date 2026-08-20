#!/usr/bin/env python3
"""Delegate one ES80 field-authorization signing request from an app rendezvous document.

This is an orchestration wrapper, not a second signer. It validates the canonical non-authorizing
rendezvous exported by the still-running Capture app, enforces the attempt-relative time window,
and then invokes `es80_field_authorization_envelope.py` through that signer's existing creation
interface. Cryptographic payload construction, build/evidence binding, signing, self-verification,
and no-replace publication remain owned by the existing signer.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
RENDEZVOUS_HELPER = HERE / "es80_field_authorization_rendezvous.py"
SIGNER = HERE / "es80_field_authorization_envelope.py"


def _load_rendezvous_helper():
    spec = importlib.util.spec_from_file_location(
        "es80_field_authorization_rendezvous", RENDEZVOUS_HELPER
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("signer rendezvous validator is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _positive_int(raw: str, label: str) -> int:
    try:
        value = int(raw, 10)
    except ValueError as error:
        raise ValueError(f"{label} must be an integer") from error
    if value <= 0:
        raise ValueError(f"{label} must be positive")
    return value


def _rfc3339_seconds_from_unix_milliseconds(value: int, label: str) -> str:
    # The existing signer intentionally accepts canonical RFC3339 whole seconds and converts those
    # to payload milliseconds. Reject rather than round a caller-supplied sub-second instant so this
    # wrapper cannot silently sign a different chronology than the one it validated.
    if value <= 0 or value % 1_000 != 0:
        raise ValueError(f"{label} must be a positive exact whole-second Unix millisecond instant")
    try:
        instant = datetime.fromtimestamp(value // 1_000, tz=timezone.utc)
    except (OverflowError, OSError, ValueError) as error:
        raise ValueError(f"{label} is outside the supported timestamp range") from error
    return instant.strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_signing_chronology(
    *,
    attempt_started_at: int,
    must_expire_by: int,
    issued_at: int,
    not_before: int,
    expires_at: int,
) -> None:
    if issued_at < attempt_started_at:
        raise ValueError("issued-at precedes the running app attempt")
    if not_before < attempt_started_at:
        raise ValueError("not-before precedes the running app attempt")
    if not_before > issued_at:
        raise ValueError("not-before is later than issued-at")
    if expires_at <= issued_at:
        raise ValueError("expires-at must be later than issued-at")
    if expires_at > must_expire_by:
        raise ValueError("expires-at exceeds the running app attempt deadline")


def build_signer_command(args: argparse.Namespace, rendezvous: dict) -> list[str]:
    # Keep this as a thin delegation. Stable build/evidence values are read and verified by the
    # existing signer from --signed-evidence; duplicating them as caller-selected argv values here
    # would create a second payload authority and previously drifted from the real signer CLI.
    return [
        sys.executable,
        str(SIGNER),
        "--signed-evidence", str(args.signed_evidence),
        "--private-key", str(args.private_key),
        "--openssl", str(args.openssl),
        "--authorization-id", args.authorization_id,
        "--attempt-challenge-sha256", rendezvous["attemptChallengeSHA256"],
        "--issued-at", _rfc3339_seconds_from_unix_milliseconds(
            args.issued_at_unix_ms, "issued-at"
        ),
        "--not-before", _rfc3339_seconds_from_unix_milliseconds(
            args.not_before_unix_ms, "not-before"
        ),
        "--expires-at", _rfc3339_seconds_from_unix_milliseconds(
            args.expires_at_unix_ms, "expires-at"
        ),
        "--output", str(args.output),
    ]


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--rendezvous", type=Path, required=True)
    value.add_argument("--signed-evidence", type=Path, required=True)
    value.add_argument("--private-key", type=Path, required=True)
    value.add_argument("--openssl", type=Path, required=True)
    value.add_argument("--authorization-id", required=True)
    value.add_argument(
        "--issued-at-unix-ms",
        type=lambda raw: _positive_int(raw, "issued-at"),
        required=True,
    )
    value.add_argument(
        "--not-before-unix-ms",
        type=lambda raw: _positive_int(raw, "not-before"),
        required=True,
    )
    value.add_argument(
        "--expires-at-unix-ms",
        type=lambda raw: _positive_int(raw, "expires-at"),
        required=True,
    )
    value.add_argument("--output", type=Path, required=True)
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    helper = _load_rendezvous_helper()
    try:
        rendezvous = helper.verify_rendezvous_bytes(helper._read_exact(args.rendezvous))
        validate_signing_chronology(
            attempt_started_at=rendezvous["attemptStartedAtUnixMilliseconds"],
            must_expire_by=rendezvous["authorizationMustExpireByUnixMilliseconds"],
            issued_at=args.issued_at_unix_ms,
            not_before=args.not_before_unix_ms,
            expires_at=args.expires_at_unix_ms,
        )
        command = build_signer_command(args, rendezvous)
    except (helper.SignerRendezvousError, ValueError) as error:
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2

    completed = subprocess.run(command, check=False)
    if completed.returncode != 0:
        return completed.returncode
    print("SIGNED_ENVELOPE_CREATED_NOT_PHYSICAL_GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
