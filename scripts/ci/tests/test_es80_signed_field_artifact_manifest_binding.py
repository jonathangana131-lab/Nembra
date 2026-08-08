#!/usr/bin/env python3
"""Expected-red regression for closed-world signed-field evidence-set binding.

The canonical inspector currently cross-binds the retained IPA, external build record,
and field-build evidence, but the signing-inspection companion itself is not covered by
one immutable closed-world evidence-set manifest. Independent acceptance must never
have to trust a mutable pathname/file set whose diagnostic signing facts are outside the
published digest graph.

This regression intentionally fails until the canonical inspector publishes one
canonical manifest that names and SHA-256-binds the complete evidence set.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
INSPECTOR_PATH = REPO_ROOT / "scripts" / "ci" / "es80_signed_field_artifact_evidence.py"
MANIFEST_NAME = "NembraCaptureSignedFieldArtifactManifest.json"


def load_inspector():
    spec = importlib.util.spec_from_file_location("es80_signed_field_artifact_evidence", INSPECTOR_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("could not load canonical signed-field inspector")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    inspector = load_inspector()

    with tempfile.TemporaryDirectory(prefix="nembra-signed-field-manifest-binding-") as temporary:
        root = Path(temporary)
        ipa = root / "candidate.ipa"
        ipa.write_bytes(b"exact retained ipa bytes")

        external_bytes = inspector.canonical_json_bytes({"schemaVersion": 3, "subject": "external"})
        external_sha = hashlib.sha256(external_bytes).hexdigest()
        field_record = {
            "signedInstallableSHA256": sha256(ipa),
            "externalBuildRecordSHA256": external_sha,
        }
        field_bytes = inspector.canonical_json_bytes(field_record)
        signing_inspection = {
            "fieldBuildEvidenceRecordSHA256": hashlib.sha256(field_bytes).hexdigest(),
            "teamIdentifier": "AAAAAAAAAA",
            "provisioningProfileSHA256": "1" * 64,
            "codeDirectoryHash": "2" * 40,
        }
        inspection = {
            "external_bytes": external_bytes,
            "field_build_record": field_record,
            "field_build_bytes": field_bytes,
            "signing_inspection": signing_inspection,
        }

        output = root / "field-evidence"
        paths = inspector.write_outputs(ipa, output, inspection)
        manifest_path = output / MANIFEST_NAME
        assert manifest_path.is_file(), (
            "canonical signed-field publication must emit one closed-world manifest that binds "
            "the complete retained evidence set, including the signing-inspection companion"
        )

        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        assert isinstance(manifest, dict)
        assert manifest.get("schemaVersion") == 1
        artifacts = manifest.get("artifacts")
        assert isinstance(artifacts, list)

        expected = {
            "build-evidence/NembraField.ipa": sha256(paths["retained_ipa"]),
            "NembraCaptureExternalBuildRecord.json": sha256(paths["external_record"]),
            "NembraCaptureFieldBuildEvidenceRecord.json": sha256(paths["field_build_record"]),
            "NembraCaptureSignedFieldArtifactInspection.json": sha256(paths["signing_inspection"]),
        }
        observed = {}
        for item in artifacts:
            assert isinstance(item, dict)
            name = item.get("path")
            digest = item.get("sha256")
            assert isinstance(name, str) and isinstance(digest, str)
            assert name not in observed, f"duplicate manifest artifact path: {name}"
            observed[name] = digest

        assert observed == expected, (
            "signed-field manifest must be closed-world: exact four retained evidence subjects, "
            "each bound to its exact SHA-256 and no unbound extras"
        )

        # The manifest is descriptive acceptance evidence, not field authorization. It must not
        # introduce any authority token, GO bit, trust-root value, or device identifier.
        manifest_text = manifest_path.read_text(encoding="utf-8")
        for forbidden in ("authorized", "fieldGO", "trustRoot", "deviceUDID", "intendedDeviceUDID"):
            assert forbidden not in manifest_text


if __name__ == "__main__":
    main()
