# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical path

`scripts/ci/xcode27_signed_field_candidate.sh` is the single producer for a real signed/exported Nembra Capture IPA candidate. It builds from a fresh detached worktree at the exact source SHA and feeds the resulting IPA into the existing canonical inspector `scripts/ci/es80_signed_field_artifact_evidence.py`.

The producer does not define a second field-build schema. The machine-readable subjects remain:

- `NembraCaptureExternalBuildRecord.json` — schema-v3 executable/Info.plist/build rendezvous;
- `NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `NembraCaptureSignedFieldArtifactInspection.json` — separate signing/platform diagnostics with explicit non-authorization wording;
- `build-evidence/NembraField.ipa` — exact retained signed installable.

## Exact export-policy provenance

`NEMBRA_EXPORT_OPTIONS_PLIST` is an external release input. The producer deliberately does not guess an Xcode 27 export method.

Before archive/export it now:

1. creates one unique evidence directory for the source/build-instance;
2. refuses `/`, the repository root, or any pre-existing artifact directory;
3. requires an in-repository artifact directory to already be Git-ignored;
4. copies the supplied export-options plist to `ExportOptions.plist` in the immutable candidate evidence directory;
5. validates that retained snapshot as a plist;
6. rejects a `teamID` in the snapshot that disagrees with `NEMBRA_DEVELOPMENT_TEAM`;
7. hashes the exact retained snapshot;
8. passes that exact snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
9. re-hashes it after export and fails if the bytes changed.

This closes an evidence gap: independent acceptance can now inspect the exact export policy bytes that produced the retained IPA instead of relying on an operator recollection or mutable external file.

## Durable production logs

The candidate directory also retains:

- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- `field-candidate-environment.txt`, including source SHA, build identifier, build-instance ID, requested/verified team, export-options digest, recipe/procedure, and explicit `physical_authorization=not-granted`.

A logging failure is treated as a producer failure rather than silently claiming a complete evidence set without the expected log.

## Exact-source boundary

The invocation checkout must be clean before production. The actual archive/export still occurs from a fresh detached Git worktree at the exact `SOURCE_SHA`, with clean/head checks before and after build. Build products remain outside that source worktree.

Creating the ignored candidate evidence directory in the invocation checkout does not become source identity. The exact source/build-instance values injected into the app remain correlation/provenance only; they are not authorization.

## What success does not prove

A successful producer run does **not** prove:

- independent acceptance of the retained IPA/evidence;
- that the selected export policy is the accepted field installation route;
- that the retained IPA was installed on the intended iPhone;
- that an independently controlled authorization key approved the exact subjects;
- that the production package trust root is configured;
- that the package physical execution gate is GO;
- that the physical runbook is GO;
- physical ES80 identity or any GATT/Tuya/telemetry/command semantic.

No BLE characteristic-value write path or physical authorization is added here.

## Remaining physical gate

The final surviving Capture software head still needs exact-head Apple acceptance and screenshot/accessibility/performance review. That exact source must then produce the real signed IPA, whose retained bytes and records require independent acceptance. Only an independently controlled signed authorization over the exact accepted subjects may then feed the package-owned field gate, followed by deliberate final runbook GO and required exact-head product acceptance.

Until then:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
