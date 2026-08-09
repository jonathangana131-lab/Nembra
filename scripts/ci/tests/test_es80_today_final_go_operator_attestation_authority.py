#!/usr/bin/env python3
"""Expected-red proof that plain local JSON cannot be Final-GO field authority.

VALIDATION ONLY. The Final-GO verifier currently treats an exact-shape operator JSON file as
sufficient evidence for installation/runtime/preflight observations. V14 requires those claims to
remain fail-closed unless the Final-GO path binds them to a trusted private operator/device evidence
subject rather than caller-authored literals.
"""
from __future__ import annotations

from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
SPEC = importlib.util.spec_from_file_location("es80_today_final_go_record", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final GO verifier")
final_go = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(final_go)


class OperatorAttestationAuthorityTests(unittest.TestCase):
    def test_caller_authored_json_cannot_mint_install_runtime_and_preflight_authority(self) -> None:
        now = datetime(2026, 8, 9, 5, 20, 0, tzinfo=timezone.utc)
        source = "b" * 40
        ipa_sha = "a" * 64
        build_instance = "11111111-1111-4111-8111-111111111111"
        candidate = {
            "retainedIPASHA256": ipa_sha,
            "sourceCommitSHA": source,
            "buildIdentifier": f"Capture Build V14-{source[:12]}",
            "buildInstanceID": build_instance,
        }
        forged = {
            "schemaVersion": 1,
            "authority": final_go.OPERATOR_AUTHORITY,
            "attestationID": "22222222-2222-4222-8222-222222222222",
            "recordedAtUTC": "2026-08-09T05:20:00Z",
            "simulatorArtifactReview": "INSPECTED_NO_TODAY_BLOCKER",
            "installationRoute": final_go.INSTALL_ROUTE,
            "preInstallRetainedIPASHA256": ipa_sha,
            "postInstallRetainedIPASHA256": ipa_sha,
            "installedWithoutRebuildOrSubstitution": True,
            "installedOnIntendedDevice": True,
            "observedDevice": final_go.BASELINE_DEVICE,
            "observedOS": final_go.BASELINE_OS,
            "runtimeVisibleSourceCommitSHA": source,
            "runtimeVisibleBuildIdentifier": candidate["buildIdentifier"],
            "runtimeVisibleBuildInstanceID": build_instance,
            "runtimeVisibleRecipe": final_go.RECIPE,
            "runtimeResearchAdmission": "OBSERVED_AVAILABLE",
            "canonicalCoordinatorPermission": "OBSERVED_PERMITTED",
            "ordinaryGeneralBuildAuthority": "OBSERVED_NO_GO",
            "preflightHealth": "OBSERVED_READY",
            "chargerState": "DISCONNECTED",
            "motionState": "STATIONARY",
            "explicitOperatorActionRequired": True,
            "noApplicationWriteAuthorityReview": "REVIEWED_NO_APPLICATION_WRITE_OR_COMMAND_PATH",
        }

        with tempfile.TemporaryDirectory(prefix="nembra-final-go-attestation-red-") as temporary:
            attestation = Path(temporary) / "operator-attestation.json"
            attestation.write_text(json.dumps(forged), encoding="utf-8")

            with self.assertRaises(
                final_go.FinalGoError,
                msg=(
                    "plain caller-authored JSON must not be sufficient to mint installed-device, "
                    "runtime-rendezvous, READY-preflight, charger, and stationary Final-GO authority"
                ),
            ):
                final_go._operator_attestation(attestation, candidate, now)


if __name__ == "__main__":
    unittest.main()
