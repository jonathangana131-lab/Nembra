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
        self.assertIn('failed private content/mode validation', source)
        self.assertNotIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID:?Set', source)
        self.assertNotIn('python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)

        # The verification value is read only inside the runner after a no-follow descriptor open.
        # It must never become an OS-visible child-process argument or environment value.
        self.assertIn('os.O_NOFOLLOW', runner)
        self.assertIn('os.fstat(descriptor)', runner)
        self.assertIn('metadata.st_uid != os.geteuid()', runner)
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

    def test_superseded_raw_udid_environment_is_scrubbed_before_any_child_process(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        scrub = "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID"
        first_child = 'ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"'

        self.assertEqual(
            source.count(scrub),
            1,
            "The superseded raw UDID variable must have one unambiguous scrub point.",
        )
        self.assertLess(
            source.index(scrub),
            source.index(first_child),
            "The raw legacy UDID must be removed before dirname/pwd/uname or any later child can inherit it.",
        )
        raw_name_lines = [
            line.strip()
            for line in source.splitlines()
            if "NEMBRA_INTENDED_FIELD_DEVICE_UDID" in line
            and "NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" not in line
        ]
        self.assertEqual(
            raw_name_lines,
            [scrub],
            "The superseded raw UDID variable may exist only as the immediate environment scrub, never as an input seam.",
        )

    def test_private_input_must_be_owned_by_current_user(self) -> None:
        runner = load_private_runner()

        with tempfile.TemporaryDirectory(prefix="nembra-private-owner-test-") as temporary:
            private_file = Path(temporary) / "device-id"
            private_file.write_text("00008101-001234567890001E", encoding="utf-8")
            private_file.chmod(0o600)
            owner = os.stat(private_file).st_uid

            with mock.patch.object(runner.os, "geteuid", return_value=owner + 1):
                with self.assertRaisesRegex(
                    runner.PrivateInputError,
                    "must be owned by the current user",
                ):
                    runner.read_private_identifier(private_file)

    def test_same_size_in_place_mutation_fails_closed(self) -> None:
        runner = load_private_runner()
        real_fstat = os.fstat

        with tempfile.TemporaryDirectory(prefix="nembra-private-input-test-") as temporary:
            private_file = Path(temporary) / "device-id"
            private_file.write_text("00008101-001234567890001E", encoding="utf-8")
            private_file.chmod(0o600)

            call_count = 0

            def fstat_with_changed_metadata(descriptor):
                nonlocal call_count
                call_count += 1
                metadata = real_fstat(descriptor)
                if call_count != 2:
                    return metadata
                return SimpleNamespace(
                    st_dev=metadata.st_dev,
                    st_ino=metadata.st_ino,
                    st_mode=metadata.st_mode,
                    st_uid=metadata.st_uid,
                    st_gid=metadata.st_gid,
                    st_size=metadata.st_size,
                    st_mtime_ns=metadata.st_mtime_ns + 1,
                    st_ctime_ns=metadata.st_ctime_ns,
                )

            with mock.patch.object(runner.os, "fstat", side_effect=fstat_with_changed_metadata):
                with self.assertRaisesRegex(
                    runner.PrivateInputError,
                    "changed while being read",
                ):
                    runner.read_private_identifier(private_file)

            self.assertEqual(call_count, 2)


if __name__ == "__main__":
    unittest.main()
