# ES80 Signed Field Artifact Evidence — V14

## Purpose

The final physical Experiment One build must be a real signed iPhone/installable artifact from the exact accepted Capture composition. Simulator executable evidence cannot be promoted into that role.

`scripts/ci/es80_signed_field_artifact_evidence.py` closes the post-build measurement rung for an already-produced `.ipa`. It verifies and preserves signed-device artifact evidence without granting physical GO.

The field artifact must also be usable as the Capture instrument from a normal iPhone Home Screen launch. A Release archive cannot depend on Xcode-only launch arguments or DEBUG environment variables, so the deliberate field build carries `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1` in its signed Info.plist. Nembra treats that exact value as **launch routing only**. It is build-pipeline-constructible metadata and cannot grant physical authority; the package-owned field gate remains the mechanical authority boundary.

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
- `NembraCaptureFieldRecipe` exists and is exactly `ES80-FINGERPRINT-v1`, so the retained Release IPA opens the Capture shell from an ordinary launch rather than silently opening the standard app;
- `CFBundleExecutable` resolves to one bundle-local executable file;
- `codesign --verify --deep --strict` succeeds on the extracted signed app;
- the signature is not ad-hoc;
- code-signing metadata contains a concrete TeamIdentifier and displayed authority chain;
- `embedded.mobileprovision` exists and can be decoded on macOS;
- the provisioning profile contains exactly the code-signing TeamIdentifier and its `com.apple.developer.team-identifier` entitlement matches that team;
- the provisioning profile `application-identifier` binds the exact Nembra bundle identifier;
- the provisioning profile contains at least one registered device, preventing a structurally signed but non-direct-device artifact from being promoted as the field installable;
- the provisioning profile has not expired at inspection time;
- no executable-digest/trusted-field record is embedded inside the signed app bundle.

The inspector never repairs malformed metadata, trims source identities, substitutes Simulator values, accepts a caller-provided artifact digest instead of hashing the exact bytes, or records individual provisioned-device identifiers in the signing inspection.

## One machine-readable field-build contract

A successful run refuses to overwrite an existing evidence set and writes:

- `build-evidence/NembraField.ipa` — byte-for-byte retained copy of the inspected installable artifact;
- `NembraCaptureExternalBuildRecord.json` — closed-world schema-v3 build record containing build label, build-instance rendezvous, exact source SHA, executable SHA-256, Info.plist SHA-256, `ES80-FINGERPRINT-v1`, and procedure `V14`;
- `NembraCaptureFieldBuildEvidenceRecord.json` — the exact schema-v1 signed-installable declaration consumed by `PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON`;
- `NembraCaptureSignedFieldArtifactInspection.json` — separate schema-v2 launch/signing/provisioning inspection metadata that is deliberately **not** the package rendezvous record.

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

It intentionally contains no `physicalGO`, `authorized`, signing-team, provisioning, platform, byte-count, or other extra fields because the package parser is closed-world. The stronger direct-device checks therefore do **not** create or mutate a competing package record schema.

## Separate signing inspection

`NembraCaptureSignedFieldArtifactInspection.json` carries non-authorizing diagnostics including:

- explicit `signed-field-artifact-inspection-not-field-authorization` authority wording;
- SHA-256 of the exact field-build evidence record bytes;
- SHA-256 of the exact external build record and signed IPA;
- IPA byte count;
- bundle and iPhone platform declarations;
- code-signing TeamIdentifier and displayed authority chain;
- exact `NembraCaptureFieldRecipe` launch marker;
- SHA-256 of the exact embedded provisioning-profile bytes;
- provisioning TeamIdentifier and exact application identifier;
- registered-device **count only** (never individual device identifiers/UDIDs);
- provisioning expiration in UTC;
- exact build/source/executable/Info.plist tuple;
- recipe and procedure identity.

The retained IPA is re-hashed after copy. The external build record and field-build evidence record are also re-hashed after write and must match the digests carried by their dependent evidence.

This local launch/signature/provisioning inspection is still not independent release acceptance. It establishes that the proposed artifact is structurally a directly provisioned iPhone Capture candidate; it does not prove installation or authorize the scooter experiment.

## Non-self-referential topology

The external build record, field-build evidence record, and signing inspection all remain outside `Nembra.app`. Keeping final executable/IPA digest evidence external preserves the non-self-referential signed-bundle topology used by Capture provenance.

The signed IPA is the subject being measured; these external records may describe and bind it, but none are embedded back into the signed app whose digest they carry. The Info.plist field-recipe marker is only a launch selector whose exact bytes are already committed by the schema-v3 `infoPlistSHA256`; it never becomes an independent trust root.

## Independent acceptance still required

A successful inspection means only that one exact signed IPA passed the local structural/signature/build-identity/launch/provisioning checks and that its exact bytes were retained and measured.

It does **not** prove that:

- the signing team/certificate/provisioning profile is an accepted Nembra release authority;
- any specific provisioned device is the intended field iPhone;
- GitHub or another trusted acceptance service attested the exact retained IPA and records;
- the artifact was installed on the field iPhone;
- the Capture launch was physically exercised from that device's Home Screen;
- the installed executable/Info.plist are the artifact independently accepted;
- the package physical execution gate is GO;
- the final runbook is GO;
- a physical AOVOPRO ES80 is authenticated;
- any GATT/Tuya/DP/telemetry semantic is known;
- any command/write is safe or acknowledged.

The next trusted pipeline rung must independently attest/accept the exact retained IPA plus the exact external evidence subjects, bind them to the running app through the package-owned runtime rendezvous, and only then deliberately evolve the package-owned physical field gate. Arbitrary parsed JSON, matching UUID/SHA spelling, a field-launch Info.plist marker, a provisioning profile, or this script's exit code must never unlock Experiment One.

## Development-only self-test

The script has a platform-independent contract smoke test for canonical SHA/UUID/build-label handling, the exact field-launch recipe, unsafe/ambiguous ZIP paths, the exact closed-world field-build record key set, and provisioning-profile structural rules:

```sh
python3 scripts/ci/es80_signed_field_artifact_evidence.py --self-test
```

That self-test is development evidence only. It does not substitute for running the full inspector on macOS against the final signed field IPA.

## Physical status

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN** until the final composed app has exact-head product acceptance, the exact signed field artifact has independent acceptance, the package field gate is deliberately bound to that authority, and the definitive runbook is explicitly changed to GO.