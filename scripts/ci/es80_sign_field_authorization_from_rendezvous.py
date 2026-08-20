#!/usr/bin/env python3
"""Delegate one ES80 field-authorization signing request from an app rendezvous document.

This is an orchestration wrapper, not a second signer. It validates the canonical non-authorizing
rendezvous exported by the still-running Capture app, enforces the attempt-relative time window,
and then invokes `es80_field_authorization_envelope.py` with the extracted challenge.
Cryptographic payload construction, signed-evidence parsing, signing, self-verification, and
no-replace publication remain owned by the existing signer.
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


def timestamp_unix_milliseconds(raw: str, label: str) -> int:
    """Parse the same UTC RFC3339-style timestamps accepted by the existing signer."""
    if not raw or not raw.endswith("Z"):
        raise ValueError(f"{label} must be an explicit UTC timestamp ending in Z")
    try:
        value = datetime.fromisoformat(raw[:-1] + "+00:00")
    except ValueError as error:
        raise ValueError(f"{label} is not a valid UTC timestamp") from error
    if value.tzinfo is None or value.utcoffset() != timezone.utc.utcoffset(value):
        raise ValueError(f"{label} must resolve to UTC")
    milliseconds = int(value.timestamp() * 1_000)
    if milliseconds <= 0:
        raise ValueError(f"{label} must be after the Unix epoch")
    return milliseconds


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
    """Use only the existing signer's real creation surface; do not duplicate evidence facts."""
    return [
        sys.executable,
        str(SIGNER),
        "--signed-evidence", str(args.signed_evidence),
        "--private-key", str(args.private_key),
        "--openssl", str(args.openssl),
        "--output", str(args.output),
        "--authorization-id", args.authorization_id,
        "--attempt-challenge-sha256", rendezvous["attemptChallengeSHA256"],
        "--issued-at", args.issued_at,
        "--not-before", args.not_before,
        "--expires-at", args.expires_at,
    ]


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--rendezvous", type=Path, required=True)
    value.add_argument("--signed-evidence", type=Path, required=True)
    value.add_argument("--private-key", type=Path, required=True)
    value.add_argument("--openssl", type=Path, required=True)
    value.add_argument("--authorization-id", required=True)
    value.add_argument("--issued-at", required=True)
    value.add_argument("--not-before", required=True)
    value.add_argument("--expires-at", required=True)
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
            issued_at=timestamp_unix_milliseconds(args.issued_at, "issued-at"),
            not_before=timestamp_unix_milliseconds(args.not_before, "not-before"),
            expires_at=timestamp_unix_milliseconds(args.expires_at, "expires-at"),
        )
    except (helper.SignerRendezvousError, RuntimeError, ValueError) as error:
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2

    completed = subprocess.run(build_signer_command(args, rendezvous), check=False)
    if completed.returncode != 0:
        return completed.returncode
    print("SIGNED_ENVELOPE_CREATED_NOT_PHYSICAL_GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
