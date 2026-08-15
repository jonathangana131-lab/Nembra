#!/usr/bin/env python3
"""Expected-red authority oracle for the current Capture compiler input window.

The accepted source SHA and endpoint-clean checks are not enough if the dedicated
build identity still executes xcodebuild with the field-owned checkout as cwd. A
same-UID field actor can transiently replace tracked source after the pre-build
acceptance checks, let the compiler consume those bytes, and restore the accepted
bytes before the post-build endpoint checks.

The private Tuya fingerprint record has the same acceptance problem if bootstrap
regenerates it from whatever live local SDK/identity bytes are present without an
independently preaccepted record digest. An immutable snapshot must bind reviewed
private executable inputs, not merely freeze newly observed bytes.

This test is intentionally red until the current signed-build composition either
consumes a protected accepted source/private-input snapshot or establishes an
equally strong immutable build-input root through the compiler window.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"
BUILD_ORIGIN = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


class CaptureCurrentSourceWindowAuthorityRedTeamTests(unittest.TestCase):
    def test_mutate_consume_restore_defeats_endpoint_equality(self) -> None:
        accepted = b"accepted source\n"
        attacker = b"transient attacker source\n"
        accepted_digest = digest(accepted)

        with tempfile.TemporaryDirectory(prefix="nembra-source-window-red-team-") as temporary:
            subject = Path(temporary) / "Tracked.swift"
            subject.write_bytes(accepted)
            self.assertEqual(digest(subject.read_bytes()), accepted_digest)

            # The field identity mutates after point-in-time acceptance. The
            # consumer sees the transient bytes, then the field identity restores
            # the exact accepted endpoint before a later audit.
            subject.write_bytes(attacker)
            compiler_consumed = subject.read_bytes()
            subject.write_bytes(accepted)

            self.assertEqual(digest(subject.read_bytes()), accepted_digest)
            self.assertEqual(compiler_consumed, attacker)
            self.assertNotEqual(digest(compiler_consumed), accepted_digest)

    def test_current_build_origin_executes_from_live_checkout_cwd(self) -> None:
        source = BUILD_ORIGIN.read_text(encoding="utf-8")
        self.assertIn(
            "cwd=Path(os.getcwd())",
            source,
            "red-team precondition changed: inspect the new build-input root before retaining this oracle",
        )

    def test_current_orchestrator_private_subjects_are_live_checkout_paths(self) -> None:
        source = ORCHESTRATOR.read_text(encoding="utf-8")
        self.assertIn("repo = _absolute_lexical(Path(os.getcwd()))", source)
        self.assertIn("repo / CANONICAL_SDK_RELATIVE", source)
        self.assertIn("repo / CANONICAL_RUNTIME_RELATIVE", source)
        self.assertIn("_PrivateReadLease(private_subjects, repo)", source)
        self.assertNotIn(
            "accepted_input_snapshot",
            source,
            "red-team marker appeared; inspect the implementation instead of assuming this test is still current",
        )

    def test_installer_still_builds_the_checkout_workspace(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("-workspace NembraCapture.xcworkspace", source)
        self.assertNotIn(
            "NEMBRA_PROTECTED_SOURCE_ROOT",
            source,
            "red-team marker appeared; inspect the implementation instead of assuming this test is still current",
        )

    def test_private_fingerprint_record_is_regenerated_without_preaccepted_record_digest(self) -> None:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn('/usr/bin/python3 -I "$PROVENANCE_HELPER" snapshot', source)
        self.assertIn('DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"', source)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256", source)
        self.assertNotIn(
            "NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256",
            source,
            "private provenance gained an explicit accepted digest; inspect the new authority handoff",
        )

    def test_required_invariant_protected_build_input_root(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")
        build_origin = BUILD_ORIGIN.read_text(encoding="utf-8")
        combined = "\n".join((installer, orchestrator, build_origin))

        accepted_snapshot_markers = (
            "NEMBRA_PROTECTED_SOURCE_ROOT",
            "accepted_input_snapshot",
            "readonly_source_mount",
            "protected_source_root",
        )
        live_checkout_cwd = "cwd=Path(os.getcwd())" in build_origin
        has_snapshot = any(marker in combined for marker in accepted_snapshot_markers)

        self.assertTrue(
            has_snapshot and not live_checkout_cwd,
            "EXPECTED RED: current dedicated compiler still consumes the field-owned checkout/private trees; "
            "endpoint SHA/status/provenance checks and a live read lease do not bind the bytes consumed during xcodebuild",
        )

    def test_required_invariant_private_record_is_preaccepted_before_snapshot(self) -> None:
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
        installer = INSTALLER.read_text(encoding="utf-8")
        combined = bootstrap + "\n" + installer
        accepted_private_markers = (
            "NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256",
            "accepted_private_provenance_sha256",
            "accepted_private_input_manifest",
        )
        self.assertTrue(
            any(marker in combined for marker in accepted_private_markers),
            "EXPECTED RED: private SDK/identity fingerprints are regenerated from live local bytes without an independently preaccepted fingerprint-record identity; a future immutable snapshot must bind reviewed private executable inputs, not bless arbitrary field-time bytes",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
