#!/usr/bin/env python3
"""Cross-bind one retained-install manifest to independently accepted stable subjects.

This module is deliberately non-authorizing. It does not install an app, verify the post-install
attempt envelope, contact a device, select a signing key, grant OFF1, or establish physical truth.
It only proves that already-authenticated pre-install bytes describe one identical retained subject.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re
from typing import Any

HERE = Path(__file__).resolve().parent
MANIFEST_SCRIPT = HERE / "es80_retained_install_manifest.py"
SPEC = importlib.util.spec_from_file_location("nembra_retained_install_manifest", MANIFEST_SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("retained-install manifest verifier is unavailable")
manifest_contract = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest_contract)

EXTERNAL_SCHEMA_VERSION = 3
FINAL_GO_SCHEMA_VERSION = 1
EVIDENCE_SCHEMA_VERSION = 1
RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
EVIDENCE_KIND = "signed-field-artifact-digests-not-authorization"
SIGNED_INSTALLABLE_KIND = "ipa"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MAX_JSON_BYTES = 1024 * 1024

EXTERNAL_KEYS = {
    "schemaVersion", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
}
FINAL_GO_KEYS = {
    "schemaVersion", "decision", "procedureID", "bundleIdentifier", "sourceCommitSHA",
    "buildIdentifier", "buildInstanceID", "signedInstallableSHA256", "executableSHA256",
    "infoPlistSHA256", "tuyaDependencyLockSHA256", "intendedDevicePseudonymSHA256",
}
EVIDENCE_KEYS = {
    "schemaVersion", "evidenceKind", "procedureID", "bundleIdentifier", "sourceCommitSHA",
    "buildIdentifier", "buildInstanceID", "signedInstallableKind", "signedInstallableSHA256",
    "executableSHA256", "infoPlistSHA256", "tuyaDependencyLockSHA256",
    "externalBuildRecordSHA256", "finalGORecordSHA256", "intendedDevicePseudonymSHA256",
}


class RetainedInstallCrossBindingError(RuntimeError):
    pass


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical_pretty_json(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise RetainedInstallCrossBindingError("subject contains a duplicate JSON member")
        value[key] = item
    return value


def _closed_pretty_json(data: bytes, keys: set[str], label: str) -> dict[str, Any]:
    if not data or len(data) > MAX_JSON_BYTES:
        raise RetainedInstallCrossBindingError(f"{label} size is invalid")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RetainedInstallCrossBindingError(f"{label} is malformed JSON") from error
    if not isinstance(value, dict) or set(value) != keys:
        raise RetainedInstallCrossBindingError(f"{label} schema is not closed")
    if _canonical_pretty_json(value) != data:
        raise RetainedInstallCrossBindingError(f"{label} is not canonical JSON")
    return value


def _digest(value: str, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value) or value == "0" * 64:
        raise RetainedInstallCrossBindingError(f"{label} is not a canonical nonzero SHA-256")
    return value


def verify_cross_binding(
    *,
    install_manifest_data: bytes,
    external_build_record_data: bytes,
    signed_build_evidence_data: bytes,
    final_go_record_data: bytes,
    accepted_install_manifest_sha256: str,
    accepted_retained_ipa_sha256: str,
    accepted_external_build_record_sha256: str,
    accepted_signed_build_evidence_sha256: str,
    accepted_final_go_record_sha256: str,
    accepted_tuya_lock_sha256: str,
    accepted_intended_device_pseudonym_sha256: str,
) -> dict[str, Any]:
    """Return the canonical manifest only when every stable exact-subject binding agrees."""
    accepted_manifest_sha = _digest(
        accepted_install_manifest_sha256, "accepted install-manifest digest"
    )
    if sha256_hex(install_manifest_data) != accepted_manifest_sha:
        raise RetainedInstallCrossBindingError(
            "independently accepted install-manifest digest mismatch"
        )
    manifest = manifest_contract.verify_manifest_bytes(install_manifest_data)
    external = _closed_pretty_json(
        external_build_record_data, EXTERNAL_KEYS, "external build record"
    )
    evidence = _closed_pretty_json(
        signed_build_evidence_data, EVIDENCE_KEYS, "signed build evidence"
    )
    final_go = _closed_pretty_json(final_go_record_data, FINAL_GO_KEYS, "Final-GO record")

    independently_accepted = {
        "retainedIPASHA256": _digest(
            accepted_retained_ipa_sha256, "accepted retained IPA digest"
        ),
        "externalBuildRecordSHA256": _digest(
            accepted_external_build_record_sha256, "accepted external build-record digest"
        ),
        "signedBuildEvidenceSHA256": _digest(
            accepted_signed_build_evidence_sha256, "accepted signed-evidence digest"
        ),
        "finalGORecordSHA256": _digest(
            accepted_final_go_record_sha256, "accepted Final-GO digest"
        ),
        "tuyaDependencyLockSHA256": _digest(
            accepted_tuya_lock_sha256, "accepted Tuya-lock digest"
        ),
        "intendedDevicePseudonymSHA256": _digest(
            accepted_intended_device_pseudonym_sha256,
            "accepted intended-device pseudonym digest",
        ),
    }

    actual_subject_digests = {
        "externalBuildRecordSHA256": sha256_hex(external_build_record_data),
        "signedBuildEvidenceSHA256": sha256_hex(signed_build_evidence_data),
        "finalGORecordSHA256": sha256_hex(final_go_record_data),
    }
    for key, actual in actual_subject_digests.items():
        if actual != independently_accepted[key]:
            raise RetainedInstallCrossBindingError(
                f"independently accepted subject digest mismatch at {key}"
            )

    for key, expected in independently_accepted.items():
        if manifest.get(key) != expected:
            raise RetainedInstallCrossBindingError(f"manifest exact-subject mismatch at {key}")

    if external.get("schemaVersion") != EXTERNAL_SCHEMA_VERSION:
        raise RetainedInstallCrossBindingError("external build-record schema is unsupported")
    if external.get("experimentRecipeID") != RECIPE_ID:
        raise RetainedInstallCrossBindingError("external build record names the wrong recipe")
    if external.get("procedureVersion") != PROCEDURE_VERSION:
        raise RetainedInstallCrossBindingError("external build record names the wrong procedure version")

    build_tuple_keys = (
        "sourceCommitSHA", "buildIdentifier", "buildInstanceID", "executableSHA256",
        "infoPlistSHA256",
    )
    for key in build_tuple_keys:
        if external.get(key) != manifest.get(key):
            raise RetainedInstallCrossBindingError(f"external build tuple mismatch at {key}")

    if evidence.get("schemaVersion") != EVIDENCE_SCHEMA_VERSION:
        raise RetainedInstallCrossBindingError("signed build-evidence schema is unsupported")
    if evidence.get("evidenceKind") != EVIDENCE_KIND:
        raise RetainedInstallCrossBindingError("signed build evidence has an authorizing kind")
    if evidence.get("signedInstallableKind") != SIGNED_INSTALLABLE_KIND:
        raise RetainedInstallCrossBindingError("signed build evidence does not name an IPA")

    evidence_expected = {
        "procedureID": manifest_contract.PROCEDURE_ID,
        "bundleIdentifier": manifest_contract.BUNDLE_IDENTIFIER,
        "signedInstallableSHA256": independently_accepted["retainedIPASHA256"],
        "tuyaDependencyLockSHA256": independently_accepted["tuyaDependencyLockSHA256"],
        "externalBuildRecordSHA256": independently_accepted["externalBuildRecordSHA256"],
        "finalGORecordSHA256": independently_accepted["finalGORecordSHA256"],
        "intendedDevicePseudonymSHA256": independently_accepted[
            "intendedDevicePseudonymSHA256"
        ],
        **{key: manifest[key] for key in build_tuple_keys},
    }
    for key, expected in evidence_expected.items():
        if evidence.get(key) != expected:
            raise RetainedInstallCrossBindingError(f"signed build-evidence mismatch at {key}")

    if final_go.get("schemaVersion") != FINAL_GO_SCHEMA_VERSION:
        raise RetainedInstallCrossBindingError("Final-GO schema is unsupported")
    if final_go.get("decision") != "GO":
        raise RetainedInstallCrossBindingError("Final-GO record does not contain GO")
    final_expected = {
        "procedureID": manifest_contract.PROCEDURE_ID,
        "bundleIdentifier": manifest_contract.BUNDLE_IDENTIFIER,
        "signedInstallableSHA256": independently_accepted["retainedIPASHA256"],
        "tuyaDependencyLockSHA256": independently_accepted["tuyaDependencyLockSHA256"],
        "intendedDevicePseudonymSHA256": independently_accepted[
            "intendedDevicePseudonymSHA256"
        ],
        **{key: manifest[key] for key in build_tuple_keys},
    }
    for key, expected in final_expected.items():
        if final_go.get(key) != expected:
            raise RetainedInstallCrossBindingError(f"Final-GO exact-subject mismatch at {key}")

    return manifest
