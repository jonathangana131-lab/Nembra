#!/usr/bin/env python3
"""Validate the non-authorizing signer rendezvous exported by the running Capture app.

The document contains only the fresh attempt challenge plus the wall-clock attempt start/deadline
needed by the independent signer. It is not a GO decision, signature, capability, device identity,
or physical authorization.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any

SCHEMA = "nembra.es80-authenticated-stationary-signer-rendezvous"
SCHEMA_VERSION = 1
PROCEDURE_ID = "ES80-AUTHENTICATED-STATIONARY-v1"
MAX_DOCUMENT_BYTES = 4_096
MAX_AUTHORIZATION_LIFETIME_MILLISECONDS = 15 * 60 * 1_000
SHA256 = re.compile(r"^[0-9a-f]{64}$")
KEYS = {
    "schema",
    "version",
    "procedureID",
    "attemptChallengeSHA256",
    "attemptStartedAtUnixMilliseconds",
    "authorizationMustExpireByUnixMilliseconds",
}


class SignerRendezvousError(RuntimeError):
    pass


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise SignerRendezvousError("rendezvous contains a duplicate JSON member")
        value[key] = item
    return value


def verify_rendezvous_bytes(data: bytes) -> dict[str, Any]:
    if not data or len(data) > MAX_DOCUMENT_BYTES:
        raise SignerRendezvousError("rendezvous size is invalid")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SignerRendezvousError("rendezvous is malformed JSON") from error
    if not isinstance(value, dict) or set(value) != KEYS:
        raise SignerRendezvousError("rendezvous schema is not closed")
    if canonical_json_bytes(value) != data:
        raise SignerRendezvousError("rendezvous is not canonical JSON")
    if value.get("schema") != SCHEMA or type(value.get("version")) is not int \
            or value["version"] != SCHEMA_VERSION:
        raise SignerRendezvousError("rendezvous schema/version is unsupported")
    if value.get("procedureID") != PROCEDURE_ID:
        raise SignerRendezvousError("rendezvous names the wrong procedure")
    challenge = value.get("attemptChallengeSHA256")
    if not isinstance(challenge, str) or not SHA256.fullmatch(challenge):
        raise SignerRendezvousError("attempt challenge is not a canonical SHA-256")
    started = value.get("attemptStartedAtUnixMilliseconds")
    deadline = value.get("authorizationMustExpireByUnixMilliseconds")
    if type(started) is not int or started <= 0 or type(deadline) is not int:
        raise SignerRendezvousError("attempt chronology is invalid")
    if started > (2**63 - 1) - MAX_AUTHORIZATION_LIFETIME_MILLISECONDS:
        raise SignerRendezvousError("attempt deadline overflows the supported clock")
    if deadline != started + MAX_AUTHORIZATION_LIFETIME_MILLISECONDS:
        raise SignerRendezvousError("attempt deadline does not match the verifier lifetime")
    return value


def _read_exact(path: Path) -> bytes:
    candidate = path.expanduser()
    if not candidate.is_absolute() or not candidate.is_file() or candidate.is_symlink():
        raise SignerRendezvousError("rendezvous path must be one absolute regular non-symlink file")
    data = candidate.read_bytes()
    if not data or len(data) > MAX_DOCUMENT_BYTES:
        raise SignerRendezvousError("rendezvous size is invalid")
    return data


def _self_test() -> None:
    start = 2_000_000
    data = canonical_json_bytes({
        "schema": SCHEMA,
        "version": SCHEMA_VERSION,
        "procedureID": PROCEDURE_ID,
        "attemptChallengeSHA256": "a" * 64,
        "attemptStartedAtUnixMilliseconds": start,
        "authorizationMustExpireByUnixMilliseconds": (
            start + MAX_AUTHORIZATION_LIFETIME_MILLISECONDS
        ),
    })
    verify_rendezvous_bytes(data)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate", type=Path, metavar="RENDEZVOUS")
    args = parser.parse_args(argv)
    if args.self_test == bool(args.validate):
        parser.error("choose exactly one of --self-test or --validate")
    try:
        if args.self_test:
            _self_test()
            print("PASS_NOT_AUTHORITY: signer rendezvous self-test")
        else:
            value = verify_rendezvous_bytes(_read_exact(args.validate))
            print(json.dumps({
                "status": "VALID_NOT_AUTHORITY",
                "attemptChallengeSHA256": value["attemptChallengeSHA256"],
                "attemptStartedAtUnixMilliseconds": value["attemptStartedAtUnixMilliseconds"],
                "authorizationMustExpireByUnixMilliseconds": value[
                    "authorizationMustExpireByUnixMilliseconds"
                ],
            }, sort_keys=True))
    except SignerRendezvousError as error:
        print(f"INVALID_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
