#!/usr/bin/env python3
"""Invoke the canonical signed-field inspector without exposing the intended device ID in OS argv.

The intended-device identifier is verification-only input. This wrapper accepts only a path to a
private one-value file, reads the identifier inside this Python process, and calls the incumbent
`es80_signed_field_artifact_evidence.py` module directly with an in-memory argument list. The raw
identifier is never placed in this process's command line, environment, artifact names, or output.

This is still evidence production only. It cannot authorize physical Experiment One.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import stat
import sys
import tempfile
from pathlib import Path
from types import ModuleType

MAX_IDENTIFIER_BYTES = 128
INSPECTOR_NAME = "es80_signed_field_artifact_evidence.py"


class PrivateInputError(RuntimeError):
    pass


def _stable_file_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def read_private_identifier(path: Path) -> str:
    """Read one opaque identifier through one no-follow descriptor without repairing the bytes."""
    if not hasattr(os, "O_NOFOLLOW"):
        raise PrivateInputError("this platform cannot enforce no-follow private verification input")

    flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC

    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        raise PrivateInputError("intended-device verification file is not a readable regular file") from exc

    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise PrivateInputError("intended-device verification input must be one regular non-symlink file")
        if before.st_size < 1 or before.st_size > MAX_IDENTIFIER_BYTES:
            raise PrivateInputError("intended-device verification input has an invalid bounded size")
        if before.st_mode & 0o077:
            raise PrivateInputError("intended-device verification file must not be accessible by group/other")
        if hasattr(os, "geteuid") and before.st_uid != os.geteuid():
            raise PrivateInputError("intended-device verification file must be owned by the current user")

        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            raw = handle.read(MAX_IDENTIFIER_BYTES + 1)
        after = os.fstat(descriptor)
        if len(raw) != before.st_size or _stable_file_identity(after) != _stable_file_identity(before):
            raise PrivateInputError("intended-device verification file changed while being read")
    finally:
        os.close(descriptor)

    try:
        value = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise PrivateInputError("intended-device verification input must be valid UTF-8") from exc

    if not value or value != value.strip():
        raise PrivateInputError("intended-device verification input must be one exact nonblank value")
    if any(ord(character) < 33 or ord(character) == 127 for character in value):
        raise PrivateInputError("intended-device verification input contains a forbidden character")
    if len(value.encode("utf-8")) > MAX_IDENTIFIER_BYTES:
        raise PrivateInputError("intended-device verification input exceeds the bounded size")
    return value


def load_canonical_inspector() -> ModuleType:
    inspector_path = Path(__file__).resolve().with_name(INSPECTOR_NAME)
    try:
        metadata = inspector_path.lstat()
    except OSError as exc:
        raise PrivateInputError("canonical signed-field inspector is missing") from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise PrivateInputError("canonical signed-field inspector must be one regular non-symlink file")

    spec = importlib.util.spec_from_file_location("nembra_signed_field_artifact_evidence", inspector_path)
    if spec is None or spec.loader is None:
        raise PrivateInputError("canonical signed-field inspector could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not callable(getattr(module, "main", None)) or not hasattr(module, "EvidenceError"):
        raise PrivateInputError("canonical signed-field inspector does not expose the expected contract")
    return module


def run_inspector(args: argparse.Namespace) -> int:
    intended_device_identifier = read_private_identifier(args.intended_device_udid_file)
    inspector = load_canonical_inspector()

    # The raw identifier exists only in this process's memory. `main(argv)` consumes this explicit
    # list directly; `sys.argv` and the OS process table continue to contain only the private-file path.
    inspector_arguments = [
        "--ipa",
        str(args.ipa),
        "--output-dir",
        str(args.output_dir),
        "--expected-source-sha",
        args.expected_source_sha,
        "--intended-device-udid",
        intended_device_identifier,
    ]
    try:
        return int(inspector.main(inspector_arguments))
    except inspector.EvidenceError:
        # Do not echo the inspector exception here: future inspector diagnostics must never be able
        # to accidentally serialize the verification-only identifier supplied in memory.
        print("ERROR: canonical signed-field inspector rejected the field candidate", file=sys.stderr)
        return 2


def self_test() -> None:
    expected = "00008101-001234567890001E"
    with tempfile.TemporaryDirectory(prefix="nembra-private-device-input-") as temporary:
        root = Path(temporary)

        private_file = root / "device-id"
        private_file.write_text(expected, encoding="utf-8")
        private_file.chmod(0o600)
        assert read_private_identifier(private_file) == expected

        newline_file = root / "newline"
        newline_file.write_text(expected + "\n", encoding="utf-8")
        newline_file.chmod(0o600)
        try:
            read_private_identifier(newline_file)
        except PrivateInputError:
            pass
        else:
            raise AssertionError("verification input with trailing newline must fail closed")

        permissive_file = root / "permissive"
        permissive_file.write_text(expected, encoding="utf-8")
        permissive_file.chmod(0o644)
        try:
            read_private_identifier(permissive_file)
        except PrivateInputError:
            pass
        else:
            raise AssertionError("group/other-readable verification input must fail closed")

        symlink_file = root / "symlink"
        try:
            symlink_file.symlink_to(private_file)
        except (OSError, NotImplementedError):
            symlink_file = None
        if symlink_file is not None:
            try:
                read_private_identifier(symlink_file)
            except PrivateInputError:
                pass
            else:
                raise AssertionError("symlink verification input must fail closed")

        oversized = root / "oversized"
        oversized.write_bytes(b"x" * (MAX_IDENTIFIER_BYTES + 1))
        oversized.chmod(0o600)
        try:
            read_private_identifier(oversized)
        except PrivateInputError:
            pass
        else:
            raise AssertionError("oversized verification input must fail closed")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, help="exact already-produced signed Nembra .ipa")
    parser.add_argument("--output-dir", type=Path, help="fresh directory for immutable inspector evidence")
    parser.add_argument("--expected-source-sha", help="exact accepted lowercase 40-hex source commit")
    parser.add_argument(
        "--intended-device-udid-file",
        type=Path,
        help="private mode-0600 file containing the verification-only intended field-device identifier",
    )
    parser.add_argument(
        "--check-private-input",
        action="store_true",
        help="validate only the private intended-device input without reading or inspecting an IPA",
    )
    parser.add_argument("--self-test", action="store_true", help="run platform-independent private-input checks")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        self_test()
        print("private signed-field inspector runner self-test: PASS")
        return 0

    if args.check_private_input:
        if args.intended_device_udid_file is None:
            raise PrivateInputError("--check-private-input requires --intended-device-udid-file")
        read_private_identifier(args.intended_device_udid_file)
        print("private intended-device verification input: PASS")
        return 0

    missing = [
        name
        for name, value in (
            ("--ipa", args.ipa),
            ("--output-dir", args.output_dir),
            ("--expected-source-sha", args.expected_source_sha),
            ("--intended-device-udid-file", args.intended_device_udid_file),
        )
        if value is None
    ]
    if missing:
        raise PrivateInputError(f"required arguments missing: {', '.join(missing)}")

    return run_inspector(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PrivateInputError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
