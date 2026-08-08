#!/usr/bin/env python3
"""Invoke the canonical signed-field inspector without exposing the intended device ID in OS argv.

The intended-device identifier is verification-only input. This wrapper accepts only an absolute
path to a private one-value file, reads the identifier inside this Python process, and calls the
incumbent `es80_signed_field_artifact_evidence.py` module directly with an in-memory argument list.
The raw identifier is never placed in this process's command line, environment, artifact names, or
output.

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


def _open_private_file_without_symlinks(path: Path) -> int:
    """Open an absolute file path while refusing symlinks in every path component."""
    if (
        not hasattr(os, "O_NOFOLLOW")
        or not hasattr(os, "O_DIRECTORY")
        or os.open not in os.supports_dir_fd
    ):
        raise PrivateInputError("this platform cannot enforce component-wise no-follow private input")
    if not path.is_absolute() or path.anchor != os.sep:
        raise PrivateInputError("intended-device verification file path must be one canonical absolute path")

    components = path.parts[1:]
    if not components or any(component in ("", ".", "..") for component in components):
        raise PrivateInputError("intended-device verification file path is not canonical")

    close_on_exec = os.O_CLOEXEC if hasattr(os, "O_CLOEXEC") else 0
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | close_on_exec
    file_flags = os.O_RDONLY | os.O_NOFOLLOW | close_on_exec

    try:
        parent_descriptor = os.open(os.sep, directory_flags)
    except OSError as exc:
        raise PrivateInputError("private verification path root could not be opened safely") from exc

    try:
        for component in components[:-1]:
            try:
                next_descriptor = os.open(component, directory_flags, dir_fd=parent_descriptor)
            except OSError as exc:
                raise PrivateInputError(
                    "intended-device verification path contains an unsafe directory component"
                ) from exc
            os.close(parent_descriptor)
            parent_descriptor = next_descriptor

        try:
            return os.open(components[-1], file_flags, dir_fd=parent_descriptor)
        except OSError as exc:
            raise PrivateInputError(
                "intended-device verification file is not a readable regular non-symlink file"
            ) from exc
    finally:
        os.close(parent_descriptor)


def read_private_identifier(path: Path) -> str:
    """Read one opaque identifier through a stable no-follow descriptor without repairing bytes."""
    descriptor = _open_private_file_without_symlinks(path)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise PrivateInputError("intended-device verification input must be one regular file")
        if metadata.st_uid != os.geteuid():
            raise PrivateInputError("intended-device verification file must be owned by the current user")
        if metadata.st_nlink != 1:
            raise PrivateInputError("intended-device verification file must have exactly one hard link")
        if metadata.st_size < 1 or metadata.st_size > MAX_IDENTIFIER_BYTES:
            raise PrivateInputError("intended-device verification input has an invalid bounded size")
        if metadata.st_mode & 0o077:
            raise PrivateInputError("intended-device verification file must not be accessible by group/other")

        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            raw = handle.read(MAX_IDENTIFIER_BYTES + 1)
        metadata_after = os.fstat(descriptor)
        stability_before = (
            metadata.st_dev,
            metadata.st_ino,
            metadata.st_size,
            metadata.st_mtime_ns,
            metadata.st_ctime_ns,
        )
        stability_after = (
            metadata_after.st_dev,
            metadata_after.st_ino,
            metadata_after.st_size,
            metadata_after.st_mtime_ns,
            metadata_after.st_ctime_ns,
        )
        if len(raw) != metadata.st_size or stability_after != stability_before:
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
    if value in os.fspath(path):
        raise PrivateInputError("intended-device verification file path must not contain the raw identifier")
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
        print("ERROR: canonical signed-field inspector rejected the field candidate", file=sys.stderr)
        return 2


def self_test() -> None:
    expected = "00008101-001234567890001E"
    with tempfile.TemporaryDirectory(prefix="nembra-private-device-input-") as temporary:
        root = Path(temporary).resolve(strict=True)
        private_file = root / "device-id"
        private_file.write_text(expected, encoding="utf-8")
        private_file.chmod(0o600)
        assert read_private_identifier(private_file) == expected

        cases: list[tuple[Path, str]] = []
        newline_file = root / "newline"
        newline_file.write_text(expected + "\n", encoding="utf-8")
        newline_file.chmod(0o600)
        cases.append((newline_file, "trailing newline"))

        permissive_file = root / "permissive"
        permissive_file.write_text(expected, encoding="utf-8")
        permissive_file.chmod(0o644)
        cases.append((permissive_file, "group/other-readable permissions"))

        identifier_named_file = root / expected
        identifier_named_file.write_text(expected, encoding="utf-8")
        identifier_named_file.chmod(0o600)
        cases.append((identifier_named_file, "raw identifier in path"))

        oversized = root / "oversized"
        oversized.write_bytes(b"x" * (MAX_IDENTIFIER_BYTES + 1))
        oversized.chmod(0o600)
        cases.append((oversized, "oversized input"))

        for path, description in cases:
            try:
                read_private_identifier(path)
            except PrivateInputError:
                pass
            else:
                raise AssertionError(f"verification input with {description} must fail closed")

        try:
            read_private_identifier(Path("relative-device-id"))
        except PrivateInputError:
            pass
        else:
            raise AssertionError("relative verification input path must fail closed")

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

        real_parent = root / "real-parent"
        real_parent.mkdir()
        ancestor_file = real_parent / "device-id"
        ancestor_file.write_text(expected, encoding="utf-8")
        ancestor_file.chmod(0o600)
        symlink_parent = root / "symlink-parent"
        try:
            symlink_parent.symlink_to(real_parent, target_is_directory=True)
        except (OSError, NotImplementedError):
            symlink_parent = None
        if symlink_parent is not None:
            try:
                read_private_identifier(symlink_parent / "device-id")
            except PrivateInputError:
                pass
            else:
                raise AssertionError("symlinked verification-input ancestor must fail closed")

        hardlink_file = root / "hardlink-source"
        hardlink_file.write_text(expected, encoding="utf-8")
        hardlink_file.chmod(0o600)
        hardlink_alias = root / "hardlink-alias"
        try:
            os.link(hardlink_file, hardlink_alias)
        except OSError:
            hardlink_alias = None
        if hardlink_alias is not None:
            try:
                read_private_identifier(hardlink_file)
            except PrivateInputError:
                pass
            else:
                raise AssertionError("multiply-linked verification input must fail closed")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, help="exact already-produced signed Nembra .ipa")
    parser.add_argument("--output-dir", type=Path, help="fresh directory for immutable inspector evidence")
    parser.add_argument("--expected-source-sha", help="exact accepted lowercase 40-hex source commit")
    parser.add_argument(
        "--intended-device-udid-file",
        type=Path,
        help="canonical absolute path to a private mode-0600 verification-only intended device ID",
    )
    parser.add_argument(
        "--validate-private-input-only",
        action="store_true",
        help="validate the private intended-device input without producing artifact evidence",
    )
    parser.add_argument("--self-test", action="store_true", help="run private-input boundary checks")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        self_test()
        print("private signed-field inspector runner self-test: PASS")
        return 0

    if args.validate_private_input_only:
        if args.intended_device_udid_file is None:
            raise PrivateInputError("--validate-private-input-only requires --intended-device-udid-file")
        if args.ipa is not None or args.output_dir is not None or args.expected_source_sha is not None:
            raise PrivateInputError("private-input-only validation must not include artifact-inspection arguments")
        read_private_identifier(args.intended_device_udid_file)
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
