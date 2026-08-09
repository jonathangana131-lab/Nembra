#!/usr/bin/env python3
"""Canonical hardened entrypoint for the external V14 ES80 TODAY Final GO record.

This composer is the only executable Final GO authority path. It composes four independent
boundaries before an external procedural GO record can exist:
- owner-commanded default-branch exact-head Xcode acceptance;
- the preserved closed-world signed-candidate/crosscheck foundation;
- a live private field rendezvous that binds human observations to the exact retained IPA,
  provisioning membership, connected intended iPhone, and installed Nembra bundle; and
- failure-atomic, no-replace record publication.

The private intended-device identifier remains local and is never placed in the public Final GO
record. Charger/stationary/READY observations remain explicitly human-observed procedure state, not
machine telemetry. No physical ES80 result is created by this tool.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys
from typing import Any, Callable

MODULE_DIR = Path(__file__).resolve().parent


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, MODULE_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


foundation = _load("nembra_final_go_foundation", "es80_today_final_go_foundation.py")
trusted_xcode = _load(
    "nembra_trusted_capture_xcode_subject",
    "es80_today_trusted_capture_xcode_subject.py",
)
private_rendezvous = _load(
    "nembra_today_private_field_rendezvous",
    "es80_today_private_field_rendezvous.py",
)
publication = _load("nembra_final_go_publication", "es80_today_final_go_publication.py")

FinalGoError = foundation.FinalGoError


def _workflow_blob_sha_at_commit(tooling_repo: Path, commit: str, path: str) -> str:
    """Resolve the workflow blob only through the foundation's closed Git authority boundary."""
    try:
        return foundation._git(tooling_repo, "rev-parse", f"{commit}:{path}").strip().lower()
    except FinalGoError:
        raise
    except (OSError, RuntimeError) as error:
        raise FinalGoError(
            "trusted default-branch workflow Git blob is unavailable from tooling repository"
        ) from error


def build_final_go_record(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    expected_pr_number: int,
    trusted_xcode_run_id: int,
    trusted_xcode_job_id: int,
    trusted_xcode_artifact_id: int,
    trusted_xcode_artifact_archive: Path,
    independent_crosscheck_receipt: Path,
    frozen_source_repo: Path,
    tooling_repo: Path,
    operator_attestation: Path,
    intended_device_udid_file: Path,
    github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]] = foundation._api_get_json,
    now_utc=None,
    private_rendezvous_state_dir: Path | None = None,
    profile_probe: Callable[..., dict[str, Any]] | None = None,
    device_probe: Callable[[str], dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Compose trusted Xcode + live private field authority around the preserved foundation.

    `private_rendezvous_state_dir`, `profile_probe`, and `device_probe` are dependency-injection
    seams for adversarial tests only. The production CLI exposes none of them.
    """

    def trusted_subject_adapter(
        *,
        source: str,
        expected_pr_number: int,
        run_id: int,
        job_id: int,
        artifact_id: int,
        artifact_archive_path: Path,
        github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]],
    ) -> dict[str, Any]:
        try:
            return trusted_xcode.verify_trusted_capture_xcode_subject(
                source_commit_sha=source,
                expected_pr_number=expected_pr_number,
                run_id=run_id,
                job_id=job_id,
                artifact_id=artifact_id,
                artifact_archive_path=artifact_archive_path,
                github_get_json=github_get_json,
                workflow_blob_sha_at_commit=lambda commit, path: _workflow_blob_sha_at_commit(
                    tooling_repo, commit, path
                ),
            )
        except trusted_xcode.TrustedCaptureXcodeError as error:
            raise FinalGoError(str(error)) from error

    def trusted_operator_adapter(
        path: Path,
        candidate: dict[str, Any],
        now,
    ) -> dict[str, Any]:
        arguments: dict[str, Any] = {
            "candidate_root": candidate_root,
            "candidate": candidate,
            "operator_attestation": path,
            "intended_device_udid_file": intended_device_udid_file,
            "operator_validator": foundation.validate_operator_observation,
            "now_utc": now,
            "state_dir": private_rendezvous_state_dir,
        }
        if profile_probe is not None:
            arguments["profile_probe"] = profile_probe
        if device_probe is not None:
            arguments["device_probe"] = device_probe
        try:
            return private_rendezvous.verify_private_field_rendezvous(**arguments)
        except private_rendezvous.PrivateFieldRendezvousError as error:
            raise FinalGoError(str(error)) from error

    original_xcode = foundation._trusted_xcode_subject
    original_operator = foundation._operator_attestation
    foundation._trusted_xcode_subject = trusted_subject_adapter
    foundation._operator_attestation = trusted_operator_adapter
    try:
        record = foundation.build_final_go_record(
            candidate_root=candidate_root,
            expected_source_sha=expected_source_sha,
            expected_pr_number=expected_pr_number,
            trusted_xcode_run_id=trusted_xcode_run_id,
            trusted_xcode_job_id=trusted_xcode_job_id,
            trusted_xcode_artifact_id=trusted_xcode_artifact_id,
            trusted_xcode_artifact_archive=trusted_xcode_artifact_archive,
            independent_crosscheck_receipt=independent_crosscheck_receipt,
            frozen_source_repo=frozen_source_repo,
            tooling_repo=tooling_repo,
            operator_attestation=operator_attestation,
            github_get_json=github_get_json,
            now_utc=now_utc,
        )
    finally:
        foundation._trusted_xcode_subject = original_xcode
        foundation._operator_attestation = original_operator

    subject = record.get("trustedXcodeAcceptance")
    if not isinstance(subject, dict):
        raise FinalGoError("hardened Final GO record lacks trusted Xcode acceptance subject")
    if subject.get("authority") != "default-branch-owner-command-v1":
        raise FinalGoError("hardened Final GO record did not consume default-branch Xcode authority")
    if subject.get("candidateSourceCommitSHA") != record.get("acceptedSourceCommitSHA"):
        raise FinalGoError("hardened Xcode subject candidate source diverged from accepted source")
    if subject.get("workflowSourceCommitSHA") == subject.get("candidateSourceCommitSHA"):
        raise FinalGoError("trusted workflow source must remain independent from candidate source")

    field = record.get("exactRetainedIPAInstallAndRuntimeAttestation")
    if not isinstance(field, dict):
        raise FinalGoError("hardened Final GO record lacks private field rendezvous subject")
    required_field = {
        "authority": private_rendezvous.AUTHORITY,
        "intendedDeviceMembershipVerified": True,
        "connectedDeviceProbeVerified": True,
        "installedBundleIdentifier": foundation.BUNDLE_ID,
        "oneTimeObservationConsumption": "CONSUMED",
        "rawIntendedDeviceIdentifierPublished": False,
        "physicalResultCollected": False,
    }
    for key, expected in required_field.items():
        if field.get(key) != expected:
            raise FinalGoError(f"private field rendezvous {key} mismatch")
    if field.get("preflightHealth") != "READY":
        raise FinalGoError("private field rendezvous preflight is not READY")
    if field.get("chargerState") != "DISCONNECTED":
        raise FinalGoError("private field rendezvous charger is not disconnected")
    if field.get("motionState") != "STATIONARY":
        raise FinalGoError("private field rendezvous setup is not stationary")
    return record


def publish_record_no_replace(output_path: Path, raw: bytes) -> str:
    try:
        return publication.publish_record_no_replace(output_path, raw)
    except publication.FinalGoPublicationError as error:
        raise FinalGoError(str(error)) from error


def _args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-root", required=True, type=Path)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--expected-pr-number", required=True, type=int)
    parser.add_argument("--trusted-xcode-run-id", required=True, type=int)
    parser.add_argument("--trusted-xcode-job-id", required=True, type=int)
    parser.add_argument("--trusted-xcode-artifact-id", required=True, type=int)
    parser.add_argument("--trusted-xcode-artifact-archive", required=True, type=Path)
    parser.add_argument("--independent-crosscheck-receipt", required=True, type=Path)
    parser.add_argument("--frozen-source-repo", required=True, type=Path)
    parser.add_argument("--tooling-repo", required=True, type=Path)
    parser.add_argument("--operator-attestation", required=True, type=Path)
    parser.add_argument(
        "--intended-device-udid-file",
        required=True,
        type=Path,
        help="private mode-0600 file containing the intended field-device identifier",
    )
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _args(sys.argv[1:] if argv is None else argv)
    values = vars(args).copy()
    output = values.pop("output")
    try:
        record = build_final_go_record(**values)
        raw = (json.dumps(record, indent=2, sort_keys=True) + "\n").encode()
        record_sha = publish_record_no_replace(output, raw)
    except (
        FinalGoError,
        private_rendezvous.PrivateFieldRendezvousError,
        FileNotFoundError,
        OSError,
    ) as error:
        print(f"TODAY Final GO: NO-GO: {error}", file=sys.stderr)
        return 2
    print(f"TODAY Final GO record: {output.resolve(strict=True)}")
    print(f"record_sha256={record_sha}")
    print("PHYSICAL RESULT COLLECTED: NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
