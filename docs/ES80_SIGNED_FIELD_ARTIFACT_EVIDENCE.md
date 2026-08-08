# ES80 Signed Field Artifact Evidence — V14

## Purpose

The final physical Experiment One build must be a real signed iPhone/installable artifact from the exact accepted Capture composition. Simulator executable evidence cannot be promoted into that role.

`scripts/ci/es80_signed_field_artifact_evidence.py` closes the post-build measurement rung for an already-produced `.ipa`. It verifies and preserves signed-device artifact evidence without granting physical GO.

## Required input

Run the inspector on macOS against the exact `.ipa` that is proposed for field use and provide the exact accepted lowercase 40-hex source commit:

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
- archive extraction rejects absolute paths, `..` traversal, symbolic-link members, and duplicate normalized ZIP member paths;
- bundle identifier is exactly `com.jonathangana131.nembra`;
- device platform is `iphoneos`, `CFBundleSupportedPlatforms` contains `iPhoneOS`, and no Simulator platform is admitted;
- `NembraCaptureBuildIdentifier` is canonical and exactly `Capture Build V14-<first 12 chars of accepted SHA>`;
- `NembraCaptureBuildInstanceID` is one canonical lowercase UUID-shaped value;
- `NembraCaptureBuildCommitSHA` exactly equals the accepted source SHA;
- `CFBundleExecutable` resolves to one bundle-local executable file;
- `codesign --verify --deep --strict` succeeds on the extracted signed app;
- the signature is not ad-hoc;
- code-signing metadata contains one canonical TeamIdentifier and an authority chain;
- `embedded.mobileprovision` decodes successfully, is unexpired, carries the same TeamIdentifier, and has the exact application identifier for the Nembra bundle;
- the signed app's effective `application-identifier` and developer-team entitlement match the code-signing team, bundle, and provisioning profile;
- no executable-digest/trusted-field record is embedded inside the signed app bundle.

The inspector never repairs malformed metadata, trims source identities, substitutes Simulator values, resolves duplicate archive entries by overwrite order, or accepts a caller-provided digest instead of hashing the exact artifact bytes.

## Exact retained evidence

A successful run refuses to overwrite an existing evidence set and writes:

- `build-evidence/NembraField.ipa` — byte-for-byte retained copy of the inspected installable artifact;
- `NembraCaptureExternalBuildRecord.json` — the existing closed-world schema-v3 build record containing build label, build-instance rendezvous, exact source SHA, executable SHA-256, Info.plist SHA-256, `ES80-FINGERPRINT-v1`, and procedure `V14`;
- `NembraCaptureSignedFieldArtifactEvidence.json` — companion evidence for the installable container and signing context.

The companion field-artifact evidence records:

- an explicit `signed-field-artifact-evidence-not-field-authorization` authority label;
- exact build label / build-instance / source tuple;
- exact IPA SHA-256 and byte count;
- exact signed executable SHA-256;
- exact Info.plist SHA-256;
- exact SHA-256 of the external build-record bytes;
- bundle identifier and iPhone platform declarations;
- signing TeamIdentifier and displayed authority chain;
- exact recipe and procedure identity.

The retained IPA is re-hashed after copy. The external build record is also re-hashed after write and must match the digest carried by the companion evidence.

## Relationship to the existing schema-v3 record

This tool intentionally reuses `NembraCaptureExternalBuildRecord.json` schema v3 rather than introducing a second competing build-rendezvous record. The field-specific companion adds installable-container/signing evidence that schema v3 does not currently carry.

Neither file is embedded into `Nembra.app`. Keeping final executable/IPA digest evidence external preserves the non-self-referential signed-bundle topology already used by Capture provenance.

## Independent acceptance still required

A successful inspection means only that one exact signed IPA passed the local structural/signature/build-identity checks and that its exact bytes were retained and measured.

It does **not** prove that:

- the signing team/certificate is an accepted Nembra release authority;
- GitHub or another trusted acceptance service attested the exact retained IPA and records;
- the artifact was installed on the field iPhone;
- the installed executable is the artifact that was independently accepted;
- the package physical execution gate is GO;
- the final runbook is GO;
- a physical AOVOPRO ES80 is authenticated;
- any GATT/Tuya/DP/telemetry semantic is known;
- any command/write is safe or acknowledged.

The next trusted pipeline rung must independently attest/accept the exact retained IPA plus the exact external evidence subjects and bind that accepted result to the deliberate package-owned physical field gate. Arbitrary parsed JSON, a matching UUID/SHA spelling, a valid local provisioning profile, or this script's exit code must never unlock Experiment One.

## Development-only self-test

The script has a platform-independent contract smoke test for canonical SHA/UUID/build-label handling, unsafe/duplicate ZIP paths, and pure signing-profile/entitlement agreement rules:

```sh
python3 scripts/ci/es80_signed_field_artifact_evidence.py --self-test
```

That self-test is development evidence only. It does not substitute for running the full inspector on macOS against the final signed field IPA.

## Physical status

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN** until the final composed app has exact-head product acceptance, the exact signed field artifact has independent acceptance, the package field gate is deliberately bound to that authority, and the definitive runbook is explicitly changed to GO.
