#!/usr/bin/env python3
"""Portable positive gate for Capture private-input provenance preacceptance.

The normal field path may verify a pre-reviewed canonical provenance record, but it may
not mint or refresh that record from field-owned ignored inputs. The guarded build also
recomputes the canonical record digest from the live inputs so replacing both the inputs
and their local record cannot silently rebind authority after bootstrap.
"""

from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    spec = importlib.util.spec_from_file_location("capture_tuya_private_input_build_guard_gate", GUARD)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load private-input build guard")
    module = importlib.util.module_from_spec(spec)
    # Python 3.9's dataclasses implementation resolves postponed annotations
    # through sys.modules while the class decorator executes. Register the
    # importlib-created module before exec so the hosted macOS/Xcode Python
    # exercises production guard semantics instead of failing in the test loader.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def make_inputs(helper, root: Path):
    sdk = root / "TuyaSDK"
    build = sdk / "Build"
    runtime = root / "TuyaRuntime"
    sources = runtime / "Sources/NembraTuyaPrivateConfig"
    build.mkdir(parents=True)
    sources.mkdir(parents=True)
    lock = root / "Podfile.lock"
    lock.write_text(
        "PODS:\n"
        "  - ThingSmartHomeKit (7.8.0)\n"
        "  - ThingSmartBusinessExtensionKit (7.8.0)\n",
        encoding="utf-8",
    )
    (sdk / "ThingSmartCryption.podspec").write_text("security-podspec-v1\n", encoding="utf-8")
    (build / "libThingSmartCryption.a").write_bytes(b"security-build-A")
    (runtime / "NembraTuyaPrivateConfig.podspec").write_text("identity-podspec-v1\n", encoding="utf-8")
    identity = sources / "NembraTuyaPrivateIdentity.swift"
    identity.write_text('let appKey = "PRIVATE-A"\n', encoding="utf-8")
    inputs = helper.PrivateInputs(
        lockfile=lock,
        security_podspec=sdk / "ThingSmartCryption.podspec",
        security_build=build,
        identity_podspec=runtime / "NembraTuyaPrivateConfig.podspec",
        identity_sources=sources,
    )
    return inputs, identity


class CapturePrivateProvenancePreacceptanceTests(unittest.TestCase):
    def test_normal_bootstrap_cannot_execute_snapshot(self) -> None:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        syntax = subprocess.run(
            ["/bin/bash", "-n", str(BOOTSTRAP)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256", source)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256", source)
        self.assertIn("normal field bootstrap requires the pre-reviewed private-input provenance record", source)
        self.assertIn("REVIEW MODE ONLY: create a candidate record", source)

        review_start = source.index('if [[ "$REVIEW_ONLY" == "1" ]]; then')
        snapshot = source.index('"$PROVENANCE_HELPER" snapshot')
        review_exit = source.index("  exit 0", snapshot)
        self.assertLess(review_start, snapshot)
        self.assertLess(snapshot, review_exit)
        self.assertNotIn('"$PROVENANCE_HELPER" snapshot', source[:review_start])
        self.assertNotIn('"$PROVENANCE_HELPER" snapshot', source[review_exit + len("  exit 0") :])
        self.assertIn('[[ "$PRE_PROVENANCE_SHA256" == "$ACCEPTED_PROVENANCE_SHA256" ]]', source)
        self.assertIn('[[ "$PROVENANCE_SHA256" == "$ACCEPTED_PROVENANCE_SHA256" ]]', source)

    def test_installer_carries_same_preaccepted_digest_into_build_window(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        syntax = subprocess.run(
            ["/bin/bash", "-n", str(INSTALLER)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        required = (
            "NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256",
            'ACCEPTED_TUYA_PROVENANCE_SHA256="$(printf',
            '[[ "$record_sha" == "$ACCEPTED_TUYA_PROVENANCE_SHA256" ]]',
            '--expected-provenance-sha256 "$ACCEPTED_TUYA_PROVENANCE_SHA256"',
            "Normal field mode cannot rebind this authority",
        )
        for fragment in required:
            self.assertIn(fragment, source)
        self.assertEqual(source.count('--expected-provenance-sha256 "$ACCEPTED_TUYA_PROVENANCE_SHA256"'), 1)

    def test_canonical_live_digest_changes_when_only_private_input_changes(self) -> None:
        helper = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-private-provenance-positive-") as temporary:
            inputs, identity = make_inputs(helper, Path(temporary))
            first = inputs.canonical_provenance_sha256()
            self.assertRegex(first, r"^[0-9a-f]{64}$")
            expected_record = helper.provenance._record_text(
                helper.provenance.build_record(
                    lockfile=inputs.lockfile,
                    security_podspec=inputs.security_podspec,
                    security_build=inputs.security_build,
                    identity_podspec=inputs.identity_podspec,
                    identity_sources=inputs.identity_sources,
                )
            ).encode("utf-8")
            self.assertEqual(first, hashlib.sha256(expected_record).hexdigest())

            identity.write_text('let appKey = "PRIVATE-B"\n', encoding="utf-8")
            second = inputs.canonical_provenance_sha256()
            self.assertRegex(second, r"^[0-9a-f]{64}$")
            self.assertNotEqual(first, second)
            with self.assertRaises(helper.BuildGuardError):
                helper._require_accepted_live_inputs(inputs, first, "mutation attack")
            helper._require_accepted_live_inputs(inputs, second, "new separately accepted candidate")

    def test_wrong_or_malformed_accepted_digest_fails_before_build_or_watcher(self) -> None:
        helper = load_guard()

        class Inputs:
            def generation_snapshot(self):
                return ("stable",)
            def canonical_provenance_sha256(self):
                return "a" * 64

        backend_called = False
        popen_called = False

        def backend_factory():
            nonlocal backend_called
            backend_called = True
            raise AssertionError("watcher must not arm before accepted provenance matches")

        def popen_factory(*_args, **_kwargs):
            nonlocal popen_called
            popen_called = True
            raise AssertionError("build must not launch before accepted provenance matches")

        with self.assertRaises(helper.BuildGuardError):
            helper.run_guarded_build(
                Inputs(), ["/usr/bin/true"],
                expected_provenance_sha256="b" * 64,
                backend_factory=backend_factory,
                popen_factory=popen_factory,
            )
        self.assertFalse(backend_called)
        self.assertFalse(popen_called)

        for malformed in ("", "abc", "g" * 64, "a" * 63):
            with self.subTest(digest=malformed), self.assertRaises(helper.BuildGuardError):
                helper._accepted_digest(malformed)

    def test_production_cli_requires_exact_accepted_digest(self) -> None:
        source = GUARD.read_text(encoding="utf-8")
        self.assertIn('parser.add_argument("--expected-provenance-sha256", required=True)', source)
        self.assertIn("canonical_provenance_sha256", source)
        self.assertIn("initial admission", source)
        self.assertIn("armed admission", source)
        self.assertIn("final admission", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
