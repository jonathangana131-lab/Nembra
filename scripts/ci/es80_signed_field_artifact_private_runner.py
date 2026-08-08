#!/usr/bin/env python3
"""Invoke the canonical signed-field inspector through private inputs and one frozen IPA subject.

The intended-device identifier is verification-only input. This wrapper accepts only a path to a
private one-value file, reads the identifier inside this Python process, and calls the incumbent
`es80_signed_field_artifact_evidence.py` module directly with an in-memory argument list. The raw
identifier is never placed in this process's command line, environment, artifact names, or output.

Before canonical inspection begins, the candidate IPA is copied through one no-follow descriptor
into a private attempt-local snapshot. That snapshot remains the sole IPA pathname visible to the
canonical inspector for digesting, extraction/signing/provisioning inspection, and retained evidence
publication. Later mutation or replacement of the caller-owned IPA path therefore cannot make field
evidence describe bytes different from the bytes the production inspection actually consumed.

This is still evidence production only. It cannot authorize physical Experiment One.
"""

from __future__ import annotations

import argparse
import io
import importlib.util
import os
import stat
import sys
import tempfile
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from pathlib import Path
from types import ModuleType
from typing import Iterator

MAX_IDENTIFIER_BYTES = 128
INSPECTOR_NAME = "es80_signed_field_artifact_evidence.py"
SNAPSHOT_CHUNK_BYTES = 1024 * 1024


class PrivateInputError(RuntimeError):
    pass


def _no_follow_read_flags() -> int:
    if not hasattr(os, "O_NOFOLLOW"):
        raise PrivateInputError("this platform cannot enforce no-follow private input")
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    return flags


def _source_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def read_private_identifier(path: Path) -> str:
    """Read one opaque identifier through one no-follow descriptor without repairing the bytes."""
    try:
        descriptor = os.open(path, _no_follow_read_flags())
    except OSError as exc:
        raise PrivateInputError("intended-device verification file is not a readable regular file") from exc

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise PrivateInputError("intended-device verification input must be one regular non-symlink file")
        if metadata.st_size < 1 or metadata.st_size > MAX_IDENTIFIER_BYTES:
            raise PrivateInputError("intended-device verification input has an invalid bounded size")
        if metadata.st_mode & 0o077:
            raise PrivateInputError("intended-device verification file must not be accessible by group/other")

        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            raw = handle.read(MAX_IDENTIFIER_BYTES + 1)
        if len(raw) != metadata.st_size:
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


@contextmanager
def private_ipa_snapshot(path: Path) -> Iterator[Path]:
    """Freeze the caller's IPA bytes into the sole private subject used by production inspection."""
    try:
        source_descriptor = os.open(path, _no_follow_read_flags())
    except OSError as exc:
        raise PrivateInputError("signed field candidate IPA is not a readable regular file") from exc

    try:
        before = os.fstat(source_descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise PrivateInputError("signed field candidate IPA must be one regular non-symlink file")
        if before.st_size < 1:
            raise PrivateInputError("signed field candidate IPA must not be empty")

        with tempfile.TemporaryDirectory(prefix="nembra-private-signed-field-subject-") as temporary:
            snapshot = Path(temporary) / "inspection-subject.ipa"
            destination_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            if hasattr(os, "O_CLOEXEC"):
                destination_flags |= os.O_CLOEXEC
            try:
                destination_descriptor = os.open(snapshot, destination_flags, 0o600)
            except OSError as exc:
                raise PrivateInputError("private signed field candidate snapshot could not be created") from exc

            copied = 0
            try:
                while True:
                    chunk = os.read(source_descriptor, SNAPSHOT_CHUNK_BYTES)
                    if not chunk:
                        break
                    view = memoryview(chunk)
                    while view:
                        written = os.write(destination_descriptor, view)
                        if written <= 0:
                            raise PrivateInputError(
                                "signed field candidate IPA snapshot write made no progress"
                            )
                        copied += written
                        view = view[written:]
                os.fsync(destination_descriptor)
            except OSError as exc:
                raise PrivateInputError("signed field candidate IPA could not be snapshotted privately") from exc
            finally:
                os.close(destination_descriptor)

            after = os.fstat(source_descriptor)
            if _source_identity(after) != _source_identity(before) or copied != before.st_size:
                raise PrivateInputError(
                    "signed field candidate IPA changed while its exact subject was frozen"
                )

            snapshot.chmod(0o400)
            snapshot_metadata = snapshot.lstat()
            if not stat.S_ISREG(snapshot_metadata.st_mode) or stat.S_ISLNK(snapshot_metadata.st_mode):
                raise PrivateInputError("private signed field candidate snapshot is not one regular file")
            if snapshot_metadata.st_size != copied:
                raise PrivateInputError("private signed field candidate snapshot has an unexpected size")
            yield snapshot
    finally:
        os.close(source_descriptor)


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


def invoke_inspector_redacted(inspector: ModuleType, inspector_arguments: list[str]) -> int:
    """Invoke inspector while containing every output path that can observe the private argv."""
    inspector_stdout = io.StringIO()
    inspector_stderr = io.StringIO()
    try:
        with redirect_stdout(inspector_stdout), redirect_stderr(inspector_stderr):
            return int(inspector.main(inspector_arguments))
    except (Exception, SystemExit):
        # The in-memory argv intentionally contains the verification-only identifier. Inspector-owned
        # stdout/stderr is never replayed because future parsing/diagnostics may echo argument values.
        # SystemExit is included because argparse writes its diagnostic before raising it. Genuine
        # operator interruption (KeyboardInterrupt) still propagates because it is not caught here.
        print("ERROR: canonical signed-field inspector rejected the field candidate", file=sys.stderr)
        return 2


def run_inspector(args: argparse.Namespace) -> int:
    intended_device_identifier = read_private_identifier(args.intended_device_udid_file)
    inspector = load_canonical_inspector()

    with private_ipa_snapshot(args.ipa) as ipa_snapshot:
        # The raw identifier exists only in this process's memory. `main(argv)` consumes this explicit
        # list directly, while the inspector sees only the frozen private IPA subject—not the mutable
        # caller-owned candidate path. The OS process table still carries neither private raw value.
        inspector_arguments = [
            "--ipa",
            str(ipa_snapshot),
            "--output-dir",
            str(args.output_dir),
            "--expected-source-sha",
            args.expected_source_sha,
            "--intended-device-udid",
            intended_device_identifier,
        ]
        return invoke_inspector_redacted(inspector, inspector_arguments)


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

        original_ipa = b"exact signed candidate bytes"
        replacement_ipa = b"different bytes placed at caller path later"
        ipa_path = root / "candidate.ipa"
        ipa_path.write_bytes(original_ipa)
        with private_ipa_snapshot(ipa_path) as snapshot:
            assert snapshot != ipa_path
            assert snapshot.read_bytes() == original_ipa
            assert stat.S_IMODE(snapshot.stat().st_mode) == 0o400
            ipa_path.write_bytes(replacement_ipa)
            assert snapshot.read_bytes() == original_ipa
        assert not snapshot.exists()

        ipa_symlink = root / "candidate-link.ipa"
        try:
            ipa_symlink.symlink_to(ipa_path)
        except (OSError, NotImplementedError):
            ipa_symlink = None
        if ipa_symlink is not None:
            try:
                with private_ipa_snapshot(ipa_symlink):
                    pass
            except PrivateInputError:
                pass
            else:
                raise AssertionError("symlink IPA input must fail closed")

    class ExplodingInspector:
        def main(self, argv: list[str]) -> int:
            if expected not in argv:
                raise AssertionError("redaction self-test did not supply the exact private value")
            raise RuntimeError(f"future diagnostic accidentally included {expected}")

    ordinary_stderr = io.StringIO()
    with redirect_stderr(ordinary_stderr):
        result = invoke_inspector_redacted(
            ExplodingInspector(),
            ["--intended-device-udid", expected],
        )
    assert result == 2
    assert expected not in ordinary_stderr.getvalue()
    assert "future diagnostic" not in ordinary_stderr.getvalue()

    class SystemExitInspector:
        def main(self, argv: list[str]) -> int:
            print(f"argparse rejected {expected}", file=sys.stderr)
            raise SystemExit(2)

    system_exit_stderr = io.StringIO()
    with redirect_stderr(system_exit_stderr):
        result = invoke_inspector_redacted(
            SystemExitInspector(),
            ["--intended-device-udid", expected],
        )
    assert result == 2
    assert expected not in system_exit_stderr.getvalue()
    assert "argparse rejected" not in system_exit_stderr.getvalue()
    assert system_exit_stderr.getvalue().strip() == "ERROR: canonical signed-field inspector rejected the field candidate"

    class NoisySuccessInspector:
        def main(self, argv: list[str]) -> int:
            print(f"stdout accidentally included {expected}")
            print(f"stderr accidentally included {expected}", file=sys.stderr)
            return 0

    noisy_stdout = io.StringIO()
    noisy_stderr = io.StringIO()
    with redirect_stdout(noisy_stdout), redirect_stderr(noisy_stderr):
        result = invoke_inspector_redacted(
            NoisySuccessInspector(),
            ["--intended-device-udid", expected],
        )
    assert result == 0
    assert expected not in noisy_stdout.getvalue()
    assert expected not in noisy_stderr.getvalue()


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
    parser.add_argument("--self-test", action="store_true", help="run platform-independent private-input checks")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        self_test()
        print("private signed-field inspector runner self-test: PASS")
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
