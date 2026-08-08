# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Current production chain

`scripts/ci/xcode27_signed_field_candidate.sh` is the producer for the real signed/exported iPhone Capture candidate.

The final software path is intentionally one chain:

`exact clean source -> detached exact-SHA archive -> signed Xcode export -> exact IPA -> canonical signed-field inspector -> atomic canonical evidence publication`

The producer does not create a second field-build schema, parser, verifier, or authorization vocabulary.

## Required external inputs

A trusted signing Mac running the final accepted source must supply:

- `NEMBRA_DEVELOPMENT_TEAM` — intended Apple TeamIdentifier;
- `NEMBRA_EXPORT_OPTIONS_PLIST` — existing export-options plist for the intended installation route;
- `NEMBRA_INTENDED_FIELD_DEVICE_UDID` — provisioning UDID of the intended field iPhone;
- optional `NEMBRA_ALLOW_PROVISIONING_UPDATES=1` when the trusted signing environment intentionally permits Xcode provisioning updates.

The intended-device UDID is verification-only. The producer passes it as the canonical inspector's `--intended-device-udid` argument and never writes, prints, hashes, or uses it in an artifact filename. The inspector requires that the embedded profile authorize that intended device unless `ProvisionsAllDevices` legitimately applies.

## Release Capture launch routing

The archive stamps:

`NembraCaptureFieldRecipe = ES80-FINGERPRINT-v1`

The merged Release app routing recognizes only that exact marker and enters Nembra Capture on normal Home Screen launch. The marker is build-pipeline-constructible routing data, never physical authority. The package-owned field execution gate remains the authority boundary.

## Producer provenance vs atomic field evidence

Producer provenance and canonical field evidence are deliberately separated under one immutable candidate root:

- `producer/` — export policy snapshot, archive/export logs, canonical-inspector log, and producer environment facts;
- `evidence/` — owned exclusively by `es80_signed_field_artifact_evidence.py` for its failure-atomic, no-replace publication.

The producer never pre-creates `evidence/`. This preserves the canonical inspector's directory-atomic publication contract.

The exact supplied export-options plist is copied to `producer/ExportOptions.plist` before export, validated, SHA-256 measured, and any present `teamID` must match `NEMBRA_DEVELOPMENT_TEAM`. Xcode consumes that retained snapshot rather than the caller's mutable original path. The snapshot is re-hashed after export and any byte drift fails the candidate.

Archive/export console output is retained under `producer/logs/`. The candidate environment records the export-options digest and log locations but never the intended-device UDID.

## Exact source and output safety

The invocation checkout must be clean. The actual archive/export is performed from a fresh detached Git worktree at exact `SOURCE_SHA`, then rechecked after export.

The candidate root is unique per source/build-instance, physically canonicalized before safety decisions, and must not already exist. `/`, the repository root, and non-ignored in-repository output roots are rejected. Existing field-production state is never deleted to make a new run succeed.

## macOS Bash compatibility

The producer runs under `/bin/bash` with `set -u` and avoids optionally empty arrays that can fail on the older Bash shipped by macOS:

- optional provisioning updates use a validated `0|1` plus explicit `run_xcodebuild` branch;
- exported IPA selection uses Python closed-world enumeration and requires exactly one regular top-level `.ipa`.

## Canonical evidence subjects

The inspector remains the sole machine-readable field-artifact evidence producer and publishes:

- `evidence/build-evidence/NembraField.ipa`;
- `evidence/NembraCaptureExternalBuildRecord.json`;
- `evidence/NembraCaptureFieldBuildEvidenceRecord.json`;
- `evidence/NembraCaptureSignedFieldArtifactInspection.json`.

Those records bind exact signed installable/build/runtime subjects and preserve the explicit `signed-field-artifact-inspection-not-field-authorization` boundary.

## What success does not prove

A successful producer run does not prove independent acceptance, successful installation/launch on the intended iPhone, production trust-root configuration, a valid signed GO authorization, package field GO, runbook GO, physical ES80 identity, RF completeness, GATT/Tuya/DP semantics, telemetry semantics, command acknowledgement, or any safe write authority.

No application Bluetooth characteristic-value write path is added here.

## Remaining acceptance rung

After software convergence, require terminal exact-head Xcode 27 product acceptance and inspect the retained UI screenshots/accessibility/performance evidence. Then run this producer on that exact surviving source from the trusted signing Mac. Independently accept the resulting exact IPA plus canonical evidence and running-app rendezvous. Only then may the externally controlled authorization key sign those accepted subjects, the package field gate consume that verified authority, and the runbook deliberately flip to GO for that exact build.

Until every applicable gate is closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
