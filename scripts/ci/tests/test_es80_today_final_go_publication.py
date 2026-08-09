#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_publication.py"
spec = importlib.util.spec_from_file_location("publication", MODULE_PATH)
publication = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(publication)


class FinalGoPublicationTests(unittest.TestCase):
    RAW = b'{"decision":"GO"}\n'

    def test_success_publishes_exact_bytes_and_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            digest = publication.publish_record_no_replace(output, self.RAW)
            self.assertEqual(output.read_bytes(), self.RAW)
            self.assertEqual(digest, publication._sha(self.RAW))
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])

    def test_directory_fsync_failure_after_rename_retracts_go_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            real_fsync = publication.os.fsync
            calls = 0

            def fail_second_fsync(fd: int):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("simulated parent-directory fsync failure after rename")
                return real_fsync(fd)

            with mock.patch.object(publication.os, "fsync", side_effect=fail_second_fsync):
                with self.assertRaisesRegex(OSError, "simulated parent-directory fsync failure"):
                    publication.publish_record_no_replace(output, self.RAW)
            self.assertFalse(output.exists() or output.is_symlink())
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])

    def test_post_publish_byte_verification_failure_retracts_go_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            real_regular = publication._regular
            calls = 0

            def changed_once(path: Path, label: str):
                nonlocal calls
                calls += 1
                value = real_regular(path, label)
                if calls == 2 and label == "published Final GO record":
                    return value + b"substitution"
                return value

            with mock.patch.object(publication, "_regular", side_effect=changed_once):
                with self.assertRaisesRegex(
                    publication.FinalGoPublicationError,
                    "published Final GO record bytes differ",
                ):
                    publication.publish_record_no_replace(output, self.RAW)
            self.assertFalse(output.exists() or output.is_symlink())

    def test_pre_publish_failure_leaves_no_destination_or_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"

            def fail_before_publish(staging: Path, destination: Path):
                raise OSError("simulated pre-publication failure")

            with self.assertRaisesRegex(OSError, "simulated pre-publication failure"):
                publication.publish_record_no_replace(
                    output,
                    self.RAW,
                    publisher=fail_before_publish,
                )
            self.assertFalse(output.exists() or output.is_symlink())
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])

    def test_existing_destination_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            output.write_bytes(b"existing")
            with self.assertRaisesRegex(publication.FinalGoPublicationError, "output already exists"):
                publication.publish_record_no_replace(output, self.RAW)
            self.assertEqual(output.read_bytes(), b"existing")

    def test_changed_destination_is_not_deleted_during_rollback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"

            def publish_then_replace(staging: Path, destination: Path):
                publication._publish_file_no_replace(staging, destination)
                destination.write_bytes(b"attacker-or-external-change")

            with self.assertRaisesRegex(
                publication.FinalGoPublicationError,
                "AMBIGUOUS NO-GO",
            ):
                publication.publish_record_no_replace(
                    output,
                    self.RAW,
                    publisher=publish_then_replace,
                )
            self.assertEqual(output.read_bytes(), b"attacker-or-external-change")

    def test_rollback_failure_moves_exact_bytes_to_non_authoritative_quarantine(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            real_retract = publication._retract_published_record
            real_fsync = publication._fsync_directory
            post_publish_fsync_calls = 0

            def fail_first_parent_fsync(parent: Path):
                nonlocal post_publish_fsync_calls
                post_publish_fsync_calls += 1
                if post_publish_fsync_calls == 1:
                    raise OSError("initial durable publish fsync failed")
                return real_fsync(parent)

            def fail_rollback(destination: Path, raw: bytes):
                self.assertEqual(destination, output)
                self.assertEqual(raw, self.RAW)
                raise OSError("ordinary rollback unavailable")

            with mock.patch.object(publication, "_fsync_directory", side_effect=fail_first_parent_fsync), \
                 mock.patch.object(publication, "_retract_published_record", side_effect=fail_rollback):
                with self.assertRaisesRegex(
                    publication.FinalGoPublicationError,
                    "bytes quarantined",
                ):
                    publication.publish_record_no_replace(output, self.RAW)

            self.assertFalse(output.exists() or output.is_symlink())
            quarantined = list(root.glob(".FinalGO.json.QUARANTINED-NO-GO.*"))
            self.assertEqual(len(quarantined), 1)
            self.assertEqual(quarantined[0].read_bytes(), self.RAW)
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])
            self.assertIsNotNone(real_retract)


if __name__ == "__main__":
    unittest.main()
