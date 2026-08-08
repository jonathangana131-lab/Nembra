#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
PRIVATE_RUNNER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_private_runner.py"
REPOSITORY_ROOT = PRIVATE_RUNNER.resolve().parents[2]


def load_private_runner():
    spec = importlib.util.spec_from_file_location("nembra_private_field_runner_test", PRIVATE_RUNNER)
    if spec is None or spec.loader is None:
        raise AssertionError("could not load private signed-field runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_through_private_path_only_input(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        runner = PRIVATE_RUNNER.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute private mode-0600 file containing the verification-only intended field iPhone UDID.}"',
            source,
        )
        self.assertIn('es80_signed_field_artifact_private_runner.py', source)
        self.assertIn(
            '--validate-intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertEqual(source.count('--repository-root "$ROOT"'), 2)
        self.assertIn('_open_private_identifier_without_symlink_components(path, repository_root)', runner)
        self.assertIn('(next_metadata.st_dev, next_metadata.st_ino) == repository_identity', runner)
        self.assertIn('failed private content/mode validation', source)
        self.assertNotIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID:?Set', source)
        self.assertNotIn('python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)

        # The retired raw-value variable must be scrubbed before dirname/uname/Python/Git/Xcode or
        # any other child process can inherit a stale caller-provided device identifier.
        executable_lines = [
            line.strip()
            for line in source.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertGreaterEqual(len(executable_lines), 2)
        self.assertEqual(executable_lines[0], "set -euo pipefail")
        self.assertEqual(executable_lines[1], "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID")
        self.assertNotIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID=', source)

        # The verification value is read only after each caller path component is opened without
        # following symlinks. The accepted file must remain external, singly linked, and private.
        self.assertIn('os.O_NOFOLLOW', runner)
        self.assertIn('os.O_DIRECTORY', runner)
        self.assertIn('os.open not in os.supports_dir_fd', runner)
        self.assertIn('dir_fd=parent_descriptor', runner)
        self.assertIn('os.fstat(descriptor)', runner)
        self.assertIn('metadata.st_uid != os.geteuid()', runner)
        self.assertIn('metadata.st_nlink != 1', runner)
        self.assertIn('value in os.fspath(path)', runner)
        self.assertIn('_stable_file_identity(final_metadata)', runner)
        self.assertIn('_stable_file_identity(metadata)', runner)
        self.assertIn('inspector.main(inspector_arguments)', runner)
        self.assertIn('--validate-intended-device-udid-file', runner)
        self.assertNotIn('subprocess', runner)
        self.assertNotIn('os.environ', runner)

        # The intended device remains an admission input, not artifact provenance. Do not serialize,
        # echo, hash, or derive an output path from the private verification file or its contents.
        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('field_device_udid=', source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"', source)
        self.assertNotIn('ARTIFACTS_DIR="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)
        self.assertNotIn('BUILD_INSTANCE_ID="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)

    def test_private_input_must_be_owned_by_current_user(self) -> None:
        runner = load_private_runner()

        with tempfile.TemporaryDirectory(prefix="nembra-private-owner-test-") as temporary:
            private_file = Path(temporary).resolve(strict=True) / "device-id"
            private_file.write_text("00008101-001234567890001E", encoding="utf-8")
            private_file.chmod(0o600)
            owner = os.stat(private_file).st_uid

            with mock.patch.object(runner.os, "geteuid", return_value=owner + 1):
                with self.assertRaisesRegex(
                    runner.PrivateInputError,
                    "must be owned by the current user",
                ):
                    runner.read_private_identifier(private_file, REPOSITORY_ROOT)

    def test_repository_contained_private_input_fails_closed(self) -> None:
        runner = load_private_runner()
        with tempfile.TemporaryDirectory(dir=REPOSITORY_ROOT, prefix=".nembra-private-boundary-test-") as temporary:
            private_file = Path(temporary) / "ignored-device-id"
            private_file.write_text("00008101-001234567890001E", encoding="utf-8")
            private_file.chmod(0o600)
            try:
                with self.assertRaisesRegex(
                    runner.PrivateInputError,
                    "must live outside the Nembra repository",
                ):
                    runner.read_private_identifier(private_file, REPOSITORY_ROOT)
            finally:
                private_file.unlink(missing_ok=True)

    def test_relative_private_input_path_fails_closed(self) -> None:
        runner = load_private_runner()
        with self.assertRaisesRegex(
            runner.PrivateInputError,
            "canonical absolute path",
        ):
            runner.read_private_identifier(Path("device-id"), REPOSITORY_ROOT)

    def test_same_size_in_place_mutation_fails_closed(self) -> None:
        runner = load_private_runner()
        real_fstat = os.fstat

        with tempfile.TemporaryDirectory(prefix="nembra-private-input-test-") as temporary:
            private_file = Path(temporary).resolve(strict=True) / "device-id"
            private_file.write_text("00008101-001234567890001E", encoding="utf-8")
            private_file.chmod(0o600)

            private_inode = os.stat(private_file).st_ino
            private_fstat_count = 0

            def fstat_with_changed_metadata(descriptor):
                nonlocal private_fstat_count
                metadata = real_fstat(descriptor)
                if metadata.st_ino != private_inode:
                    return metadata
                private_fstat_count += 1
                if private_fstat_count != 2:
                    return metadata
                return SimpleNamespace(
                    st_dev=metadata.st_dev,
                    st_ino=metadata.st_ino,
                    st_mode=metadata.st_mode,
                    st_uid=metadata.st_uid,
                    st_gid=metadata.st_gid,
                    st_nlink=metadata.st_nlink,
                    st_size=metadata.st_size,
                    st_mtime_ns=metadata.st_mtime_ns + 1,
                    st_ctime_ns=metadata.st_ctime_ns,
                )

            with mock.patch.object(runner.os, "fstat", side_effect=fstat_with_changed_metadata):
                with self.assertRaisesRegex(
                    runner.PrivateInputError,
                    "changed while being read",
                ):
                    runner.read_private_identifier(private_file, REPOSITORY_ROOT)

            self.assertEqual(private_fstat_count, 2)

    def test_symlinked_ancestor_directory_fails_closed(self) -> None:
        runner = load_private_runner()
        expected = "00008101-001234567890001E"
        with tempfile.TemporaryDirectory(prefix="nembra-private-ancestor-test-") as temporary:
            root = Path(temporary).resolve(strict=True)
            real_parent = root / "real-parent"
            real_parent.mkdir()
            private_file = real_parent / "device-id"
            private_file.write_text(expected, encoding="utf-8")
            private_file.chmod(0o600)
            symlink_parent = root / "symlink-parent"
            symlink_parent.symlink_to(real_parent, target_is_directory=True)
            with self.assertRaisesRegex(runner.PrivateInputError, "unsafe directory component"):
                runner.read_private_identifier(symlink_parent / "device-id", REPOSITORY_ROOT)

    def test_multiply_linked_private_input_fails_closed(self) -> None:
        runner = load_private_runner()
        expected = "00008101-001234567890001E"
        with tempfile.TemporaryDirectory(prefix="nembra-private-hardlink-test-") as temporary:
            root = Path(temporary).resolve(strict=True)
            private_file = root / "device-id"
            private_file.write_text(expected, encoding="utf-8")
            private_file.chmod(0o600)
            alias = root / "device-id-alias"
            os.link(private_file, alias)
            with self.assertRaisesRegex(runner.PrivateInputError, "exactly one hard link"):
                runner.read_private_identifier(private_file, REPOSITORY_ROOT)

    def test_visible_private_path_cannot_contain_raw_identifier(self) -> None:
        runner = load_private_runner()
        expected = "00008101-001234567890001E"
        with tempfile.TemporaryDirectory(prefix="nembra-private-path-test-") as temporary:
            root = Path(temporary).resolve(strict=True)
            private_file = root / expected
            private_file.write_text(expected, encoding="utf-8")
            private_file.chmod(0o600)
            with self.assertRaisesRegex(runner.PrivateInputError, "path must not contain the raw identifier"):
                runner.read_private_identifier(private_file, REPOSITORY_ROOT)


if __name__ == "__main__":
    unittest.main()
