#!/usr/bin/env python3
"""Expected-red proof that the independent crosscheck receipt is caller-mintable JSON."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

CI_DIR = Path(__file__).resolve().parents[1]
FOUNDATION_PATH = CI_DIR / "es80_today_final_go_foundation.py"


def load_foundation():
    spec = importlib.util.spec_from_file_location(
        "nembra_final_go_crosscheck_receipt_custody_red",
        FOUNDATION_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Final GO foundation")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


final_go = load_foundation()


class CrosscheckReceiptCustodyExpectedRedTests(unittest.TestCase):
    SOURCE = "a" * 40
    BUILD = f"Capture Build V14-{SOURCE[:12]}"
    INSTANCE = "11111111-2222-3333-4444-555555555555"
    IPA = "3" * 64
    EXTERNAL = "4" * 64
    FIELD = "5" * 64
    INSPECTION = "6" * 64
    EXECUTABLE = "7" * 64
    PLIST = "8" * 64
    TEAM = "ABCDE12345"
    PROFILE = "9" * 64
    PRIVATE_BLOB = "1" * 40
    INSPECTOR_BLOB = "2" * 40

    def candidate(self):
        return {
            "sourceCommitSHA": self.SOURCE,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "retainedIPASHA256": self.IPA,
            "retainedIPAByteCount": 12345,
            "externalBuildRecordSHA256": self.EXTERNAL,
            "fieldBuildEvidenceRecordSHA256": self.FIELD,
            "signedArtifactInspectionSHA256": self.INSPECTION,
            "executableSHA256": self.EXECUTABLE,
            "infoPlistSHA256": self.PLIST,
            "teamIdentifier": self.TEAM,
            "provisioningProfileSHA256": self.PROFILE,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2030-08-09T00:00:00Z",
        }

    def caller_receipt(self):
        candidate = self.candidate()
        return {
            "schemaVersion": 1,
            "authority": final_go.CROSSCHECK_AUTHORITY,
            "status": "PASS_NOT_FINAL_GO",
            "sourceCommitSHA": self.SOURCE,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
            "researchCompileMode": final_go.RESEARCH_COMPILE_MODE,
            "researchCompileAuthority": final_go.RESEARCH_COMPILE_AUTHORITY,
            "researchCompileCondition": final_go.RESEARCH_COMPILE_CONDITION,
            "signedInstallableSHA256": candidate["retainedIPASHA256"],
            "signedInstallableByteCount": candidate["retainedIPAByteCount"],
            "externalBuildRecordSHA256": candidate["externalBuildRecordSHA256"],
            "fieldBuildEvidenceRecordSHA256": candidate["fieldBuildEvidenceRecordSHA256"],
            "signedFieldArtifactInspectionSHA256": candidate["signedArtifactInspectionSHA256"],
            "executableSHA256": candidate["executableSHA256"],
            "infoPlistSHA256": candidate["infoPlistSHA256"],
            "exportOptionsSHA256": "f" * 64,
            "teamIdentifier": candidate["teamIdentifier"],
            "allowProvisioningUpdates": "0",
            "privateRunnerSourceGitBlobClaim": self.PRIVATE_BLOB,
            "canonicalInspectorSourceGitBlobClaim": self.INSPECTOR_BLOB,
            "xcodeVersion": "caller can write anything here",
            "xcodeBuildVersion": "caller can write anything here too",
            "provisioningProfileSHA256": candidate["provisioningProfileSHA256"],
            "provisioningProfileUUID": candidate["provisioningProfileUUID"],
            "provisioningProfileExpirationUTC": candidate["provisioningProfileExpirationUTC"],
            "singleRetainedIPA": True,
            "crossRecordDigestLinksVerified": True,
            "researchCompileTupleVerified": True,
            "producerPhysicalAuthorizationRemainsNotGranted": True,
            "appleSigningInspectionRequired": True,
            "toolBlobClaimsRequireRepositoryCrossCheck": True,
            "exactRetainedIPAInstallHandoffRequired": True,
            "physicalExperimentAuthorization": "not-granted",
        }

    def git_result(self, repository: Path, *arguments: str) -> str:
        subject = arguments[-1]
        if subject == f"{self.SOURCE}^{{commit}}":
            return self.SOURCE
        if subject == f"{self.SOURCE}:{final_go.PRIVATE_RUNNER_PATH}":
            return self.PRIVATE_BLOB
        if subject == f"{self.SOURCE}:{final_go.INSPECTOR_PATH}":
            return self.INSPECTOR_BLOB
        if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}^{{commit}}":
            return final_go.PINNED_CROSSCHECK_COMMIT
        if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}:{final_go.CROSSCHECK_PATH}":
            return final_go.PINNED_CROSSCHECK_BLOB
        raise AssertionError((repository, arguments))

    def test_plain_json_cannot_claim_independent_crosscheck_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = root / "caller-crosscheck.json"
            receipt.write_text(json.dumps(self.caller_receipt(), sort_keys=True), encoding="utf-8")
            source_repo = root / "source-repo"
            tooling_repo = root / "tooling-repo"
            source_repo.mkdir()
            tooling_repo.mkdir()

            # A pinned tool blob proves what code *should* perform the crosscheck; it does not prove
            # that caller-authored PASS JSON was produced by that tool. Current code accepts this
            # record after only validating its claims and Git blob names, so this is intentionally
            # RED until the receipt has independently rooted producer/custody evidence.
            with mock.patch.object(final_go, "_git", side_effect=self.git_result):
                with self.assertRaises(final_go.FinalGoError):
                    final_go._crosscheck_subject(
                        receipt,
                        self.candidate(),
                        source_repo,
                        tooling_repo,
                    )


if __name__ == "__main__":
    unittest.main()
