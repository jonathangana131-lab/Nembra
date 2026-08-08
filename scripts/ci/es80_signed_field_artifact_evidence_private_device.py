#!/usr/bin/env python3
"""Run the canonical ES80 signed-IPA inspector without placing the field-device UDID in process argv.

The field-device identifier is verification input only. This wrapper accepts only a path to a
private regular file, reads the identifier in-process, and calls the canonical inspector module
with an in-memory argv list. The identifier therefore never becomes an operating-system command
argument and is never written into Nembra evidence outputs.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import stat
import sys


SCRIPT_DIR = Path(__file__).resolve().parent
CANONICAL_INSPECTOR = SCRIPT_DIR / "es80_signed_field_artifact_evidence.py"


def load_canonical_inspector():
    spec = importlib.util.spec_from_file_location(
        "_nembra_es80_signed_field_artifact_evidence",
        CANONICAL_INSPECTOR,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load canonical ES80 signed-field inspector")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_private_device_identifier(path: Path) -> str:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ValueError("intended-device identifier file is unavailable") from error

    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ValueError("intended-device identifier input must be a regular non-symlink file")
    if metadata.st_uid != os.geteuid():
        raise ValueError("intended-device identifier file must be owned by the current user")
    if stat.S_IMODE(metadata.st_mode) & 0o077:
        raise ValueError("intended-device identifier file must not be group/world accessible")
    if metadata.st_size <= 0 or metadata.st_size > 256:
        raise ValueError("intended-device identifier file has an invalid size")

    try:
        raw = path.read_bytes()
        value = raw.decode("utf-8", errors="strict")
    except (OSError, UnicodeDecodeError) as error:
        raise ValueError("intended-device identifier file is not readable canonical UTF-8") from error

    if value != value.strip() or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ValueError("intended-device identifier file must contain one trimmed control-free value")
    if len(value) < 8 or len(value) > 128:
        raise ValueError("intended-device identifier value has an invalid length")
    return value


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument(
        "--intended-device-udid-file",
        required=True,
        type=Path,
        help="private 0600-style file containing the verification-only field-device identifier",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    device_identifier = read_private_device_identifier(args.intended_device_udid_file)
    canonical = load_canonical_inspector()

    # The canonical inspector still owns all evidence semantics. Supplying this list in-process does
    # not change the operating-system process argv, so the raw identifier does not leak via ps/CI
    # command echoing while the exact same provisioning-membership check is exercised.
    return canonical.main(
        [
            "--ipa",
            str(args.ipa),
            "--output-dir",
            str(args.output_dir),
            "--expected-source-sha",
            args.expected_source_sha,
            "--intended-device-udid",
            device_identifier,
        ]
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
