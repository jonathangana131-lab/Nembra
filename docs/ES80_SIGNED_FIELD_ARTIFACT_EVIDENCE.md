# ES80 Signed Field Artifact Evidence — V14

## Purpose

The final physical Experiment One build must be a real signed iPhone/installable artifact from the exact accepted Capture composition. Simulator executable evidence cannot be promoted into that role.

`scripts/ci/es80_signed_field_artifact_evidence.py` closes the post-build measurement rung for an already-produced `.ipa`. It verifies and preserves signed-device artifact evidence without granting physical GO.

## Required input

Run the inspector on macOS against the exact `.ipa` proposed for field use and provide the exact accepted lowercase 40-hex source commit:

```sh
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa /absolute/path/Nembra.ipa \
  --expected-source-sha <exact-40-hex-commit> \
  --output-dir /absolute/path/field-evidence
```

The source SHA is an explicit acceptance input. The tool does not guess that a nearby branch, current default branch, old green run, or filename represents the accepted build.

## Fail-closed checks

Before producing evidence, the inspector requires all of the following:

- the input is one readable IPA/ZIP with exactly one top-level `Payload/*.app`;
- archive extraction rejects absolute paths, `..` traversal, symbolic-link members, duplicate member paths, and case-fold collisions that could extract ambiguously on macOS;
- bundle identifier is exactly `com.jonathangana131.nembra`;
- device platform is `iphoneos`, `CFBundleSupportedPlatforms` contains `iPhoneOS`, and no Simulator platform is admitted;
- `NembraCaptureBuildIdentifier` is canonical and exactly `Capture Build V14-<first 12 chars of accepted SHA>`;
- `NembraCaptureBuildInstanceID` is one canonical lowercase UUID-shaped value;
- `NembraCaptureBuildCommitSHA` exactly equals the accepted source SHA;
- `CFBundleExecutable` resolves to one bundle-local executable file;
- `codesign --verify --deep --strict --all-architectures` succeeds on the extracted signed app;
- the signature is not ad-hoc and its signing identifier is exactly `com.jonathangana131.nembra`;
- code-signing metadata contains a canonical 10-character Apple TeamIdentifier, a canonical CDHash, and a displayed authority chain;
- `embedded.mobileprovision` exists and can be decoded by macOS `security cms -D`;
- the provisioning profile contains the same TeamIdentifier as the code signature;
- the provisioning profile has a nonblank UUID and is not expired at inspection time;
- the provisioning profile entitlement `application-identifier` is exactly `<TeamIdentifier>.com.jonathangana131.nembra`;
- when present, the profile entitlement `com.apple.developer.team-identifier` matches the code-signing TeamIdentifier;
- no executable-digest/trusted-field record is embedded inside the signed app bundle.

The inspector never repairs malformed metadata, trims source identities, substitutes Simulator values, or accepts a caller-provided artifact digest instead of hashing the exact bytes.

## One machine-readable field-build contract

A successful run refuses to overwrite an existing evidence set and writes:

- `build-evidence/NembraField.ipa` — byte-for-byte retained copy of the inspected installable candidate;
- `NembraCaptureExternalBuildRecord.json` — closed-world schema-v3 build record containing build label, build-instance rendezvous, exact source SHA, executable SHA-256, Info.plist SHA-256, `ES80-FINGERPRINT-v1`, and procedure `V14`;
- `NembraCaptureFieldBuildEvidenceRecord.json` — the exact schema-v1 signed-installable declaration consumed by `PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON`;
- `NembraCaptureSignedFieldArtifactInspection.json` — separate signing/platform/provisioning inspection metadata that is deliberately **not** the package rendezvous record.

`NembraCaptureFieldBuildEvidenceRecord.json` contains exactly:

- `schemaVersion = 1`;
- SHA-256 of the exact external build-record bytes;
- SHA-256 of the exact retained signed IPA bytes as `signedInstallableSHA256`;
- `signedInstallableKind = ipa`;
- build identifier;
- build-instance ID;
- exact source SHA;
- exact executable SHA-256;
- exact raw Info.plist SHA-256;
- `ES80-FINGERPRINT-v1`;
- procedure `V14`.

It intentionally contains no `physicalGO`, `authorized`, signing-team, platform, byte-count, provisioning, or other extra fields because the package parser is closed-world. This gives the package one unambiguous field-build evidence contract instead of two competing authority-adjacent formats.

## Separate signing inspection

`NembraCaptureSignedFieldArtifactInspection.json` is schema v2 and carries non-authorizing diagnostics including:

- explicit `signed-field-artifact-inspection-not-field-authorization` authority wording;
- SHA-256 of the exact field-build evidence record bytes;
- SHA-256 of the exact external build record and signed IPA;
- IPA byte count;
- bundle and iPhone platform declarations;
- code-signing TeamIdentifier, displayed authority chain, and CDHash;
- SHA-256 of the exact embedded provisioning-profile bytes;
- provisioning-profile UUID and expiration timestamp;
- the exact accepted provisioning `application-identifier`;
- exact build/source/executable/Info.plist tuple;
- recipe and procedure identity.

The retained IPA is re-hashed after copy. The external build record and field-build evidence record are also re-hashed after write and must match the digests carried by their dependent evidence.

These signing/provisioning facts remain inspection evidence, not package authority. The inspector proves the relationships it can observe locally; it does not decide that a particular team/certificate/profile is the independently accepted Nembra release authority, prove that the profile authorizes a particular field iPhone, or prove that installation succeeded on that device. Any additional signed-entitlement/device-eligibility policy belongs in the trusted field-candidate acceptance rung and must not create a competing package record schema.

## Non-self-referential topology

The external build record, field-build evidence record, and signing inspection all remain outside `Nembra.app`. Keeping final executable/IPA digest evidence external preserves the non-self-referential signed-bundle topology used by Capture provenance.

The signed IPA is the subject being measured; these external records may describe and bind it, but none are embedded back into the signed app whose digest they carry.

## Independent acceptance still required

A successful inspection means only that one exact signed IPA passed the local structural/signature/provisioning/build-identity checks and that its exact bytes were retained and measured.

It does **not** prove that:

- the signing team/certificate/provisioning profile is the independently accepted Nembra release authority;
- the profile authorizes the exact field iPhone or that installation on that device succeeded;
- GitHub or another trusted acceptance service attested the exact retained IPA and records;
- the installed executable/Info.plist are the artifact independently accepted;
- the package physical execution gate is GO;
- the final runbook is GO;
- a physical AOVOPRO ES80 is authenticated;
- any GATT/Tuya/DP/telemetry semantic is known;
- any command/write is safe or acknowledged.

The next trusted pipeline rung must independently attest/accept the exact retained IPA plus the exact external evidence subjects, bind them to the running app through the package-owned runtime rendezvous, and only then deliberately evolve the package-owned physical field gate. Arbitrary parsed JSON, matching UUID/SHA spelling, or this script's exit code must never unlock Experiment One.

## Development-only self-test

The script has a platform-independent contract smoke test for canonical SHA/UUID/build-label handling, unsafe/ambiguous ZIP paths, the exact closed-world field-build record key set, and fail-closed provisioning-profile relationship checks including wrong team, expiration, wrong app identifier, and wrong team entitlement:

```sh
python3 scripts/ci/es80_signed_field_artifact_evidence.py --self-test
```

That self-test is development evidence only. It does not substitute for running the full inspector on macOS against the final signed field IPA.

## Physical status

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN** until the final composed app has exact-head product acceptance, the exact signed field artifact has independent acceptance, the package field gate is deliberately bound to that authority, and the definitive runbook is explicitly changed to GO.
