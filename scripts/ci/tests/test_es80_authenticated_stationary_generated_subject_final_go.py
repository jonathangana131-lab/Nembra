#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = "1" * 40
DIGEST = "2" * 64
BLOB = "3" * 40


class FakeBase:
    INSTALLER = "scripts/field/install_one_time_capture.command"
    BUNDLE = "com.jonathangana131.nembra.capturelearn"
    PROC = "ES80-AUTHENTICATED-STATIONARY-v1"
    DEVICE = "iPhone 12"
    PRODUCT = "iPhone13,2"

    class GoError(RuntimeError):
        pass

    @staticmethod
    def pos(value, label):
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise RuntimeError(label)
        return value

    @staticmethod
    def canon(value, label):
        if not isinstance(value, str) or len(value) != 40 or any(c not in "0123456789abcdefABCDEF" for c in value):
            raise RuntimeError(label)
        return value.lower()

    @staticmethod
    def obj(raw, label):
        del label
        return json.loads(raw)

    @staticmethod
    def sha(raw):
        return hashlib.sha256(raw).hexdigest()

    @staticmethod
    def installer_environment(device, device_digest, accepted_lock):
        del device, device_digest, accepted_lock
        return {
            "PATH": "/usr/bin:/bin",
            "HOME": "/tmp/safe-home",
            "USER": "field",
            "LOGNAME": "field",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "BASH_ENV": "/dev/null",
            "ENV": "/dev/null",
            "NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE": "/tmp/device",
            "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256": "4" * 64,
            "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256": "5" * 64,
        }


class GeneratedSubjectFinalGoTests(unittest.TestCase):
    def _review_get(self, digest=DIGEST, *, user="jonathangana131-lab", association="OWNER"):
        body = json.dumps(
            {
                "schemaVersion": 1,
                "authority": MODULE.REVIEW_AUTHORITY,
                "sourceCommitSHA": SOURCE,
                MODULE.GENERATED_KEY: digest,
                "verdict": "accepted",
            },
            separators=(",", ":"),
        )

        def get(path):
            self.assertEqual(path, "/pulls/2612/reviews/77")
            return b"{}", {
                "id": 77,
                "state": "APPROVED",
                "commit_id": SOURCE,
                "user": {"login": user},
                "author_association": association,
                "submitted_at": "2026-08-11T04:00:00Z",
                "node_id": "PRR_generated",
                "body": body,
            }

        return get

    def test_review_accepts_one_exact_lowercase_generated_subject(self):
        result = MODULE.generated_subject_review(
            2612,
            77,
            SOURCE,
            get=self._review_get(),
            base=FakeBase,
        )
        self.assertEqual(result[MODULE.GENERATED_KEY], DIGEST)
        self.assertEqual(result["authority"], MODULE.REVIEW_AUTHORITY)
        self.assertEqual(result["reviewer"], "jonathangana131-lab")

    def test_review_rejects_uppercase_digest_even_when_bytes_are_same(self):
        with self.assertRaises(MODULE.GeneratedSubjectGoError):
            MODULE.generated_subject_review(
                2612,
                77,
                SOURCE,
                get=self._review_get(DIGEST.upper()),
                base=FakeBase,
            )

    def test_review_rejects_non_owner_custody(self):
        with self.assertRaises(MODULE.GeneratedSubjectGoError):
            MODULE.generated_subject_review(
                2612,
                77,
                SOURCE,
                get=self._review_get(user="attacker", association="CONTRIBUTOR"),
                base=FakeBase,
            )

    def test_generated_digest_is_added_to_closed_installer_environment_only(self):
        observed = {}

        def fake_run(command, **kwargs):
            observed["command"] = command
            observed["env"] = dict(kwargs["env"])
            return SimpleNamespace(returncode=0, stdout="SDK-INTEGRATED CAPTURE LAUNCHED\n")

        def fake_git(repo, *args):
            del repo
            if args == ("rev-parse", "HEAD"):
                return SOURCE
            if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                return ""
            raise AssertionError(args)

        FakeBase.git = staticmethod(fake_git)
        runner = MODULE._generated_installer(FakeBase, DIGEST)
        with mock.patch.dict(
            os.environ,
            {
                MODULE.GENERATED_ENV: "f" * 64,
                "NEMBRA_TUYA_APP_SECRET": "must-not-cross",
                "BASH_ENV": "/tmp/hostile",
            },
            clear=False,
        ), mock.patch.object(MODULE.subprocess, "run", side_effect=fake_run):
            result = runner(Path("/tmp"), SOURCE, Path("/tmp/device"), "4" * 64, "5" * 64)

        self.assertEqual(result["result"], "success")
        self.assertEqual(observed["env"][MODULE.GENERATED_ENV], DIGEST)
        self.assertNotIn("NEMBRA_TUYA_APP_SECRET", observed["env"])
        self.assertEqual(observed["env"]["BASH_ENV"], "/dev/null")
        self.assertEqual(observed["command"][:5], ["/bin/bash", "--noprofile", "--norc", "-p", "/tmp/scripts/field/install_one_time_capture.command"])

    def test_candidate_authority_requires_exact_reviewed_generated_graph_and_enforcement_files(self):
        with tempfile.TemporaryDirectory(prefix="nembra-generated-subject-final-go-") as temporary:
            root = Path(temporary)
            contents = {
                "Scripts/bootstrap_capture_tuya_sdk.sh": (
                    MODULE.GENERATED_ENV
                    + "\ncapture_cocoapods_build_subject.py\n"
                    + "generated CocoaPods build subject does not match\n"
                ),
                "Scripts/capture_cocoapods_build_subject.py": "nembra-cocoapods-generated-build-subject-v1\n",
                "Scripts/capture_tuya_private_input_provenance.py": "provenance\n",
                "Scripts/capture_tuya_private_input_build_guard.py": "inputs.pods\ninputs.workspace\n",
                "scripts/field/install_one_time_capture.command": "bootstrap_capture_tuya_sdk.sh\ncapture_tuya_private_input_build_guard.py\n",
            }
            for relative, content in contents.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")

            def fake_git(repo, *args):
                self.assertEqual(repo, root)
                if args == ("rev-parse", "HEAD"):
                    return SOURCE
                if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                    return ""
                if args[0] == "rev-parse" and args[1].startswith("HEAD:"):
                    return BLOB
                if args[:3] == ("hash-object", "--no-filters", "--"):
                    return BLOB
                raise AssertionError(args)

            FakeBase.git = staticmethod(fake_git)
            accepted = MODULE.candidate_generated_authority(
                root,
                SOURCE,
                DIGEST,
                base=FakeBase,
                derive_subject=lambda _: DIGEST,
            )
            self.assertEqual(accepted[MODULE.GENERATED_KEY], DIGEST)
            self.assertEqual(set(accepted["gitBlobs"]), set(MODULE.GENERATED_AUTHORITY_PATHS))

            with self.assertRaises(MODULE.GeneratedSubjectGoError):
                MODULE.candidate_generated_authority(
                    root,
                    SOURCE,
                    DIGEST,
                    base=FakeBase,
                    derive_subject=lambda _: "6" * 64,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
