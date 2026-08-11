#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
REVIEW_HELPER = REPOSITORY / "Scripts/capture_tuya_private_input_review.py"
GUARD_HELPER = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
AUTHORITY_ENV = "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


review = load("capture_private_review_closure_2709", REVIEW_HELPER)
guard = load("capture_private_guard_closure_2709", GUARD_HELPER)


class PrivateInputReviewAuthorityClosureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-review-closure-")
        self.root = Path(self.temporary.name)
        self.sdk = self.root / "TuyaSDK"
        self.runtime = self.root / "TuyaRuntime"
        self.security_build = self.sdk / "Build"
        self.identity_sources = self.runtime / "Sources/NembraTuyaPrivateConfig"
        self.security_build.mkdir(parents=True)
        self.identity_sources.mkdir(parents=True)
        os.chmod(self.sdk, 0o700)
        os.chmod(self.runtime, 0o700)
        os.chmod(self.security_build, 0o700)
        os.chmod(self.runtime / "Sources", 0o700)
        os.chmod(self.identity_sources, 0o700)

        self.lockfile = self.root / "Podfile.lock"
        self.lockfile.write_text(
            "PODS:\n  - ThingSmartHomeKit (7.8.0)\n  - ThingSmartBusinessExtensionKit (7.8.0)\n",
            encoding="utf-8",
        )
        self.security_podspec = self.sdk / "ThingSmartCryption.podspec"
        self.security_podspec.write_text("security-podspec-v1", encoding="utf-8")
        self.security_binary = self.security_build / "ThingSmartCryption.bin"
        self.security_binary.write_bytes(b"REVIEWED-SECURITY-A")
        self.identity_podspec = self.runtime / "NembraTuyaPrivateConfig.podspec"
        self.identity_podspec.write_text("private-config-v1", encoding="utf-8")
        self.identity_source = self.identity_sources / "NembraTuyaPrivateIdentity.swift"
        self.identity_source.write_text(
            'private let encodedAppKey = "SYNTHETIC-APPKEY-A"\n'
            'private let encodedAppSecret = "SYNTHETIC-APPSECRET-A"\n',
            encoding="utf-8",
        )
        self.record = self.runtime / "ResolvedTuyaDependencyProvenance.txt"
        self.key = self.runtime / "PrivateInputReviewKey.bin"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def paths(self) -> dict[str, Path]:
        return {
            "lockfile": self.lockfile,
            "security_podspec": self.security_podspec,
            "security_build": self.security_build,
            "identity_podspec": self.identity_podspec,
            "identity_sources": self.identity_sources,
        }

    def create_review(self) -> str:
        current = review.provenance.build_record(**self.paths())
        return review.create_review(
            record_path=self.record,
            key_path=self.key,
            current=current,
        )

    def verify(self, accepted: str) -> str:
        return review.verify_review_paths(
            record_path=self.record,
            key_path=self.key,
            accepted=accepted,
            **self.paths(),
        )

    def test_reviewed_generation_round_trips_with_private_local_key(self) -> None:
        accepted = self.create_review()
        self.assertRegex(accepted, r"^[0-9a-f]{64}$")
        self.assertEqual(self.verify(accepted), accepted)
        self.assertEqual(stat.S_IMODE(self.record.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.key.stat().st_mode), 0o600)
        self.assertEqual(self.key.stat().st_nlink, 1)
        self.assertEqual(self.key.stat().st_size, review.KEY_BYTES)

        recorded = review.provenance.read_record(self.record)
        self.assertNotIn(accepted, set(recorded.values()))
        self.assertNotIn("SYNTHETIC-APPKEY-A", accepted)
        self.assertNotIn("SYNTHETIC-APPSECRET-A", accepted)

    def test_stable_private_security_replacement_is_rejected(self) -> None:
        accepted = self.create_review()
        self.security_binary.write_bytes(b"SUBSTITUTED-SECURITY-B")
        with self.assertRaises(review.provenance.ProvenanceError):
            self.verify(accepted)

    def test_stable_private_identity_replacement_is_rejected(self) -> None:
        accepted = self.create_review()
        self.identity_source.write_text(
            'private let encodedAppKey = "SUBSTITUTED-B"\n'
            'private let encodedAppSecret = "SUBSTITUTED-B"\n',
            encoding="utf-8",
        )
        with self.assertRaises(review.provenance.ProvenanceError):
            self.verify(accepted)

    def test_attacker_cannot_self_authorize_by_rewriting_record_and_key(self) -> None:
        accepted_a = self.create_review()
        self.security_binary.write_bytes(b"SUBSTITUTED-SECURITY-B")
        self.identity_source.write_text(
            'private let encodedAppKey = "SUBSTITUTED-B"\n',
            encoding="utf-8",
        )
        accepted_b = self.create_review()
        self.assertNotEqual(accepted_b, accepted_a)
        with self.assertRaises(review.PrivateReviewError):
            self.verify(accepted_a)
        self.assertEqual(self.verify(accepted_b), accepted_b)

    def test_key_alias_or_broad_permissions_fail_closed(self) -> None:
        accepted = self.create_review()
        os.chmod(self.key, 0o644)
        with self.assertRaises(review.PrivateReviewError):
            self.verify(accepted)

        os.chmod(self.key, 0o600)
        alias = self.runtime / "review-key-alias.bin"
        os.link(self.key, alias)
        with self.assertRaises(review.PrivateReviewError):
            self.verify(accepted)

    def test_guard_requires_external_private_authority(self) -> None:
        inputs = guard.PrivateInputs(
            lockfile=Path("/tmp/lock"),
            security_podspec=Path("/tmp/security.podspec"),
            security_build=Path("/tmp/security-build"),
            identity_podspec=Path("/tmp/runtime/NembraTuyaPrivateConfig.podspec"),
            identity_sources=Path("/tmp/runtime/Sources/NembraTuyaPrivateConfig"),
        )
        with mock.patch.dict(os.environ, {AUTHORITY_ENV: ""}, clear=False):
            with self.assertRaisesRegex(guard.BuildGuardError, "must remain available"):
                guard._verify_accepted_private_input_subject(inputs)

    def test_guard_rejects_change_during_external_authority_rebind(self) -> None:
        inputs = guard.PrivateInputs(
            lockfile=Path("/tmp/lock"),
            security_podspec=Path("/tmp/security.podspec"),
            security_build=Path("/tmp/security-build"),
            identity_podspec=Path("/tmp/runtime/NembraTuyaPrivateConfig.podspec"),
            identity_sources=Path("/tmp/runtime/Sources/NembraTuyaPrivateConfig"),
        )
        accepted = "a" * 64
        with mock.patch.dict(os.environ, {AUTHORITY_ENV: accepted}, clear=False), mock.patch.object(
            guard.PrivateInputs,
            "generation_snapshot",
            autospec=True,
            side_effect=("reviewed-generation", "substituted-generation"),
        ), mock.patch.object(
            guard,
            "_verify_accepted_private_input_subject",
            return_value=None,
        ):
            with self.assertRaisesRegex(guard.BuildGuardError, "changed while external field-build authority was rebound"):
                guard._authority_bound_initial_snapshot(
                    inputs,
                    require_accepted_generated_subject=False,
                    require_accepted_private_subject=True,
                )

    def test_run_guarded_build_uses_authority_bound_snapshot_before_watchers(self) -> None:
        source = GUARD_HELPER.read_text(encoding="utf-8")
        authority_line = "initial_snapshot = _authority_bound_initial_snapshot("
        watcher_line = "watched = _open_watched_inputs(watch_paths, backend)"
        child_line = "process = popen_factory(list(command))"
        self.assertIn(authority_line, source)
        self.assertLess(source.index(authority_line), source.index(watcher_line))
        self.assertLess(source.index(watcher_line), source.index(child_line))
        self.assertIn("require_accepted_private_subject=True", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
