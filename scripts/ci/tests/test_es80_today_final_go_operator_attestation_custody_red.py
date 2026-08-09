#!/usr/bin/env python3
"""Expected-red proof that caller-authored JSON can currently mint operator GO authority."""
from __future__ import annotations

from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
FOUNDATION_PATH = CI_DIR / "es80_today_final_go_foundation.py"


def load_foundation():
    spec = importlib.util.spec_from_file_location(
        "nembra_final_go_operator_attestation_custody_red",
        FOUNDATION_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Final GO foundation")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


final_go = load_foundation()


class OperatorAttestationCustodyExpectedRedTests(unittest.TestCase):
    NOW = datetime(2026, 8, 9, 5, 27, 0, tzinfo=timezone.utc)
    SOURCE = "b" * 40
    BUILD = f"Capture Build V14-{SOURCE[:12]}"
    INSTANCE = "12345678-1234-1234-1234-123456789abc"
    IPA_SHA = "a" * 64

    def test_plain_caller_authored_json_cannot_mint_final_go_operator_authority(self):
        candidate = {
            "retainedIPASHA256": self.IPA_SHA,
            "sourceCommitSHA": self.SOURCE,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
        }
        attestation = {
            "schemaVersion": 1,
            "authority": final_go.OPERATOR_AUTHORITY,
            "attestationID": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "recordedAtUTC": self.NOW.isoformat().replace("+00:00", "Z"),
            "simulatorArtifactReview": "INSPECTED_NO_TODAY_BLOCKER",
            "installationRoute": final_go.INSTALL_ROUTE,
            "preInstallRetainedIPASHA256": self.IPA_SHA,
            "postInstallRetainedIPASHA256": self.IPA_SHA,
            "installedWithoutRebuildOrSubstitution": True,
            "installedOnIntendedDevice": True,
            "observedDevice": final_go.BASELINE_DEVICE,
            "observedOS": final_go.BASELINE_OS,
            "runtimeVisibleSourceCommitSHA": self.SOURCE,
            "runtimeVisibleBuildIdentifier": self.BUILD,
            "runtimeVisibleBuildInstanceID": self.INSTANCE,
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
            path = Path(temporary) / "caller-authored-attestation.json"
            path.write_text(json.dumps(attestation, sort_keys=True), encoding="utf-8")

            # Expected V14 contract: arbitrary caller-authored bytes cannot themselves establish
            # install/runtime/rendezvous/operator authority. Current code accepts this exact JSON
            # and promotes it into the GO record; therefore this test is intentionally RED until
            # the attestation boundary gains independent producer/custody evidence or separates
            # human declarations from machine-proven facts.
            with self.assertRaises(final_go.FinalGoError):
                final_go._operator_attestation(path, candidate, self.NOW)


if __name__ == "__main__":
    unittest.main()
