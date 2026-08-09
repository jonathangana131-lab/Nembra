#!/usr/bin/env python3
"""Green regression: plain caller-authored JSON is never Final-GO field authority."""
from __future__ import annotations

from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_foundation.py"
spec = importlib.util.spec_from_file_location("final_go_foundation", MODULE_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class OperatorAttestationAuthorityTests(unittest.TestCase):
    def test_complete_fresh_local_json_cannot_mint_field_authority(self) -> None:
        source = "b" * 40
        ipa_sha = "a" * 64
        candidate = {
            "retainedIPASHA256": ipa_sha,
            "sourceCommitSHA": source,
            "buildIdentifier": f"Capture Build V14-{source[:12]}",
            "buildInstanceID": "11111111-1111-4111-8111-111111111111",
        }
        forged = {
            "schemaVersion": 1,
            "authority": final_go.OPERATOR_AUTHORITY,
            "attestationID": "22222222-2222-4222-8222-222222222222",
            "recordedAtUTC": "2026-08-09T06:00:00Z",
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
            "runtimeVisibleBuildInstanceID": candidate["buildInstanceID"],
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

        with tempfile.TemporaryDirectory() as temporary:
            attestation = Path(temporary) / "operator-attestation.json"
            attestation.write_text(json.dumps(forged), encoding="utf-8")
            with self.assertRaisesRegex(
                final_go.FinalGoError,
                "caller-authored operator attestation is non-authorizing",
            ):
                final_go._operator_attestation(
                    attestation,
                    candidate,
                    datetime(2026, 8, 9, 6, 0, 0, tzinfo=timezone.utc),
                )

    def test_human_observation_parser_is_explicitly_separate_from_authority(self) -> None:
        self.assertIsNot(
            final_go.validate_operator_observation,
            final_go._operator_attestation,
        )


if __name__ == "__main__":
    unittest.main()
