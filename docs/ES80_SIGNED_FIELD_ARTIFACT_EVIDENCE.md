# ES80 Signed Field Artifact Evidence — V14

## Purpose

The final physical Experiment One build must be a real signed iPhone/installable artifact from the exact accepted Capture composition. Simulator executable evidence cannot be promoted into that role.

`scripts/ci/es80_signed_field_artifact_evidence.py` closes the post-build measurement rung for an already-produced `.ipa`. It verifies and preserves signed-device artifact evidence without granting physical GO.

The producer has one canonical machine-consumable field-build record. Signing/platform inspection metadata is retained separately so richer diagnostic evidence cannot accidentally become a second authority schema.

## Required input

Run the inspector on macOS against the exact `.ipa` proposed for field use and provide the exact accepted lowercase 40-hex source commit:

```sh
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa /absolute/path/Nembra.ipa \
  --expected-source-sha <exact-40-hex-commit> \
  --output-dir /absolute/path/field-evidence
```

The source SHA is an explicit acceptance input. The tool does not guess that a nearby branch, current default branch, old green run, or filename represents the accepted build.

The final output directory must not already exist. The inspector constructs and verifies the complete evidence set in a hidden sibling staging directory on the same filesystem. Only after every retained subject and cross-record digest passes does it rename that completed staging directory into the requested final path. A failure before that publication must not expose a partial final evidence directory or force the operator to repair half-written evidence before retrying.

## Fail-closed checks

Before producing evidence, the inspector requires all of the following:

- the input is one readable IPA/ZIP with exactly one top-level `Payload/*.app`;
- archive extraction rejects absolute paths, `..` traversal, symbolic-link members, duplicate member paths, and case-colliding member paths;
- bundle identifier is exactly `com.jonathangana131.nembra`;
- device platform is `iphoneos`, `CFBundleSupportedPlatforms` contains `iPhoneOS`, and no Simulator platform is admitted;
- `NembraCaptureBuildIdentifier` is valid and exactly `Capture Build V14-<first 12 chars of accepted SHA>`;
- `NembraCaptureBuildInstanceID` is one canonical lowercase UUID-shaped value;
- `NembraCaptureBuildCommitSHA` exactly equals the accepted source SHA;
- `CFBundleExecutable` resolves to one bundle-local executable file;
- `codesign --verify --deep --strict` succeeds on the extracted signed app;
- the signature is not ad-hoc;
- code-signing metadata contains a concrete TeamIdentifier and authority chain;
- no trusted/executable-digest/field-evidence record is embedded inside the signed app bundle.

The inspector never repairs malformed metadata, trims source identities, substitutes Simulator values, or accepts a caller-provided digest instead of hashing the exact artifact bytes.

## Exact retained evidence

A successful atomic publication contains:

- `build-evidence/NembraField.ipa` — byte-for-byte retained copy of the inspected installable artifact;
- `NembraCaptureExternalBuildRecord.json` — the existing closed-world schema-v3 build record containing build label, build-instance rendezvous, exact source SHA, executable SHA-256, Info.plist SHA-256, `ES80-FINGERPRINT-v1`, and procedure `V14`;
- `NembraCaptureFieldBuildEvidenceRecord.json` — the single canonical package-consumable signed-installable evidence record;
- `NembraCaptureSignedFieldArtifactInspection.json` — separate non-authorizing signing/platform inspection metadata.

The retained IPA, external build record, and canonical field-build evidence record are re-hashed before publication. The signing inspection is bound to the exact field-build evidence bytes, exact external build-record bytes, and exact signed installable digest.

## Canonical field-build evidence schema

`NembraCaptureFieldBuildEvidenceRecord.json` schema v1 intentionally matches the package-side closed-world `PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON` contract. Its exact keys are:

- `schemaVersion = 1`;
- `externalBuildRecordSHA256` — SHA-256 of the exact schema-v3 external build-record bytes;
- `signedInstallableSHA256` — SHA-256 of the exact retained `.ipa` bytes;
- `signedInstallableKind = ipa`;
- `buildIdentifier`;
- `buildInstanceID`;
- `sourceCommitSHA`;
- `executableSHA256`;
- `infoPlistSHA256`;
- `experimentRecipeID = ES80-FINGERPRINT-v1`;
- `procedureVersion = V14`.

The canonical field-build record deliberately contains no `authority`, `accepted`, `physicalGO`, signing-team, platform, or UI-controlled field. Exact parsing and equality are evidence rendezvous only, not trust.

## Separate signing inspection

`NembraCaptureSignedFieldArtifactInspection.json` preserves useful observed context such as:

- explicit `signed-field-artifact-inspection-not-field-authorization` vocabulary;
- exact SHA-256 of the canonical field-build evidence record;
- exact SHA-256 of the schema-v3 external build record;
- exact signed-installable SHA-256 and byte count;
- build label / build-instance / source tuple;
- bundle and iPhone platform declarations;
- observed TeamIdentifier and displayed signing authority chain;
- executable and Info.plist digests;
- recipe and procedure identity.

This inspection file is not consumed as the package field-build evidence schema and cannot authorize the physical procedure. It exists so a trusted acceptance pipeline can retain and review signing context without contaminating the closed-world mechanical rendezvous format.

## Relationship to runtime and final authorization

The canonical field-build record must later be matched against:

1. the exact schema-v3 external build-record bytes;
2. the exact running application build identity;
3. the independently accepted signed-installable evidence subjects.

Runtime comparison must include the raw running `Info.plist` SHA-256 as well as build identifier, build-instance ID, source SHA, and executable SHA-256. Dropping the Info.plist dimension would weaken the exact-build rendezvous already earned by the current Capture runtime identity.

Even a perfect three-way software/build match is still not physical GO. Final authority must come from an independently controlled acceptance/signing path whose private key is not in the app or repository, and the package physical gate must consume only the deliberately accepted non-forgeable result.

## Independent acceptance still required

A successful inspection means only that one exact signed IPA passed local structural/signature/build-identity checks and that its exact bytes were retained and measured.

It does **not** prove that:

- the signing team/certificate is an accepted Nembra release authority;
- GitHub or another trusted acceptance service attested the exact retained IPA and records;
- the artifact was installed on the field iPhone;
- the installed executable/Info.plist is the artifact that was independently accepted;
- the package physical execution gate is GO;
- the final runbook is GO;
- a physical AOVOPRO ES80 is authenticated;
- any GATT/Tuya/DP/telemetry semantic is known;
- any command/write is safe or acknowledged.

The next trusted pipeline rung must independently attest/accept the exact retained IPA plus the exact external evidence subjects and bind that accepted result to the package-owned physical field gate. Arbitrary parsed JSON, a matching UUID/SHA spelling, or this script's exit code must never unlock Experiment One.

## Development-only self-test

The script has a platform-independent contract test:

```sh
python3 scripts/ci/es80_signed_field_artifact_evidence.py --self-test
```

It checks canonical SHA/UUID/build-label handling, unsafe and duplicate ZIP member rejection, exact canonical field-record keys, absence of authority-like fields from that record, failure-atomic publication, exact retained-byte re-verification, and refusal to overwrite a completed evidence directory.

That self-test is development evidence only. It does not substitute for running the full inspector on macOS against the final signed field IPA.

## Physical status

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN** until the final composed app has exact-head product acceptance, the exact signed field artifact has independent acceptance, the package field gate is deliberately bound to that authority, and the definitive runbook is explicitly changed to GO.
