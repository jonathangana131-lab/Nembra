#!/usr/bin/env python3
"""Adversarial signed-field evidence publication custody regression.

The signed-field inspector must bind staging and final publication to one admitted output-parent
filesystem subject. A pathname/symlink ancestor swap must never allow publication of attacker-owned
bytes from a different directory under the staging basename.

This test is intentionally expected-red until the production publication path uses descriptor/inode
custody (or an equivalently strong primitive) across staging -> final no-replace publication.
"""

from __future__ import annotations

import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
TOOL_PATH = REPO_ROOT / "scripts" / "ci" / "es80_signed_field_artifact_evidence.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("nembra_es80_signed_field_artifact_evidence", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-field evidence tool")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class SignedFieldArtifactOutputParentCustodyTests(unittest.TestCase):
    def test_parent_symlink_swap_cannot_redirect_staging_publication(self) -> None:
        tool = load_tool()

        with tempfile.TemporaryDirectory(prefix="nembra-field-parent-custody-") as temporary:
            root = Path(temporary)
            trusted_parent = root / "trusted-parent"
            attacker_parent = root / "attacker-parent"
            trusted_parent.mkdir()
            attacker_parent.mkdir()
            alias = root / "evidence-parent"
            alias.symlink_to(trusted_parent, target_is_directory=True)

            ipa_path = root / "candidate.ipa"
            ipa_path.write_bytes(b"exact retained ipa")
            external_bytes = tool.canonical_json_bytes({"schemaVersion": 3})
            field_build_record = {
                "signedInstallableSHA256": tool.sha256_file(ipa_path),
                "externalBuildRecordSHA256": hashlib.sha256(external_bytes).hexdigest(),
            }
            field_build_bytes = tool.canonical_json_bytes(field_build_record)
            signing_inspection = {
                "fieldBuildEvidenceRecordSHA256": hashlib.sha256(field_build_bytes).hexdigest(),
            }
            inspection = {
                "external_bytes": external_bytes,
                "field_build_record": field_build_record,
                "field_build_bytes": field_build_bytes,
                "signing_inspection": signing_inspection,
            }

            output_dir = alias / "field-evidence"
            original_publish = tool.publish_directory_no_replace

            def retarget_then_publish(staging_dir: Path, requested_output: Path) -> None:
                # The current implementation carries staging/final authority as pathnames. Simulate
                # a same-UID actor replacing the output-parent symlink after staging is complete,
                # then pre-create a same-basename directory under the replacement parent.
                attacker_staging = attacker_parent / staging_dir.name
                attacker_staging.mkdir()
                (attacker_staging / "attacker-marker.txt").write_text("not Nembra evidence\n")
                alias.unlink()
                alias.symlink_to(attacker_parent, target_is_directory=True)
                original_publish(staging_dir, requested_output)

            tool.publish_directory_no_replace = retarget_then_publish
            try:
                with self.assertRaises(tool.EvidenceError):
                    tool.write_outputs(ipa_path, output_dir, inspection)
            finally:
                tool.publish_directory_no_replace = original_publish

            self.assertFalse((attacker_parent / "field-evidence").exists())
            self.assertFalse((trusted_parent / "field-evidence").exists())


if __name__ == "__main__":
    unittest.main()
