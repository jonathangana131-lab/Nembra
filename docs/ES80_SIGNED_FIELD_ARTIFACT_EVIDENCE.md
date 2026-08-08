# ES80 Signed Field Artifact Evidence — V14

## Purpose

The final physical Experiment One build must be a real signed iPhone/installable artifact from the exact accepted Capture composition. Simulator executable evidence cannot be promoted into that role.

`scripts/ci/es80_signed_field_artifact_evidence.py` closes the post-build measurement rung for an already-produced `.ipa`. It verifies and preserves signed-device artifact evidence without granting physical GO.

The companion `NembraCaptureSignedFieldArtifactEvidence.json` format is **schema v2**. The external build-rendezvous record remains `NembraCaptureExternalBuildRecord.json` **schema v3**. These are intentionally separate responsibilities: schema v3 binds the exact produced build tuple; field-evidence schema v2 adds the signed installable, code-signing, and provisioning-profile evidence needed for a later independently trusted acceptance step.

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
- archive extraction rejects absolute paths, `..` traversal, and symbolic-link members;
- bundle identifier is exactly `com.jonathangana131.nembra`;
- device platform is `iphoneos`, `CFBundleSupportedPlatforms` contains `iPhoneOS`, and no Simulator platform is admitted;
- `NembraCaptureBuildIdentifier` is canonical and exactly `Capture Build V14-<first 12 chars of accepted SHA>`;
- `NembraCaptureBuildInstanceID` is one canonical lowercase UUID-shaped value;
- `NembraCaptureBuildCommitSHA` exactly equals the accepted source SHA;
- `CFBundleExecutable` resolves to one bundle-local executable file;
- `codesign --verify --deep --strict` succeeds on the extracted signed app;
- the signature is not ad-hoc;
- code-signing metadata contains one canonical TeamIdentifier, a nonempty authority chain, and a canonical CDHash;
- `embedded.mobileprovision` exists and decodes with Apple's `security cms` tool;
- the provisioning profile TeamIdentifier contains the code-signing TeamIdentifier;
- the provisioning profile has a UUID and a future ExpirationDate;
- the provisioning profile `application-identifier` is exactly `<TeamIdentifier>.com.jonathangana131.nembra`;
- no executable-digest/trusted-field record is embedded inside the signed app bundle.

The inspector never repairs malformed metadata, trims source identities, substitutes Simulator values, accepts an expired or mismatched profile, or accepts a caller-provided digest instead of hashing the exact artifact bytes.

## Exact retained evidence

A successful run refuses to overwrite an existing evidence set and writes:

- `build-evidence/NembraField.ipa` — byte-for-byte retained copy of the inspected installable artifact;
- `NembraCaptureExternalBuildRecord.json` — closed-world schema-v3 build record containing build label, build-instance rendezvous, exact source SHA, executable SHA-256, Info.plist SHA-256, `ES80-FINGERPRINT-v1`, and procedure `V14`;
- `NembraCaptureSignedFieldArtifactEvidence.json` — closed-world field-evidence schema-v2 companion for the exact installable container, signing context, and provisioning context.

Field-evidence schema v2 records exactly:

- `schemaVersion: 2`;
- `authority: signed-field-artifact-evidence-not-field-authorization`;
- exact build label / build-instance / source tuple;
- bundle identifier;
- iPhone platform name and supported-platform declarations;
- signing TeamIdentifier and displayed authority chain;
- code-directory hash (`CDHash`);
- embedded provisioning-profile UUID;
- provisioning-profile expiration in UTC;
- exact IPA SHA-256 and byte count;
- exact signed executable SHA-256;
- exact Info.plist SHA-256;
- exact SHA-256 of the external schema-v3 build-record bytes;
- exact `ES80-FINGERPRINT-v1` recipe and `V14` procedure identity.

The retained IPA is re-hashed after copy. The external build record is also re-hashed after write and must match the digest carried by the companion evidence.

## Runtime mechanical rendezvous

`PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON` is the package-side strict parser for field-evidence schema v2. It rejects unknown fields, including caller-invented authority fields such as `physicalGO` or `authorized`, and computes the SHA-256 of the exact evidence JSON bytes presented to the parser.

`makeMechanicallyBoundSoftwareExportReference(matching:running:)` is deliberately non-authoritative. It succeeds only when:

1. field evidence names the exact schema-v3 external-record bytes;
2. build label, build-instance ID, source SHA, executable hash, Info.plist hash, recipe, and procedure match that external record exactly; and
3. the external record's runtime binding matches the executable and raw Info.plist identity measured from the application actually running.

Success produces only the existing SoftwareExport comparison reference. It does not verify the Apple signature itself, does not prove that an independently accepted IPA was installed, and cannot mutate `PassiveBluetoothExperimentOneFieldExecutionGate`.

## Relationship to the existing schema-v3 record

This tooling intentionally reuses `NembraCaptureExternalBuildRecord.json` schema v3 rather than introducing a second competing build-rendezvous record. Field-evidence schema v2 adds installable-container/signing/provisioning evidence that schema v3 does not carry.

Neither file is embedded into `Nembra.app`. Keeping final executable/IPA digest evidence external preserves the non-self-referential signed-bundle topology already used by Capture provenance.

## Independent acceptance still required

A successful inspection means only that one exact signed IPA passed the local structural/signature/build-identity/provisioning checks and that its exact bytes were retained and measured.

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

The next trusted pipeline rung must independently attest/accept the exact retained IPA plus the exact evidence-record bytes and bind that accepted result to the deliberate package-owned physical field gate. Arbitrary parsed JSON, a matching UUID/SHA spelling, or this script's exit code must never unlock Experiment One.

## Development-only tests

The script has a platform-independent self-test for canonical SHA/UUID/build-label handling and unsafe ZIP paths:

```sh
python3 scripts/ci/es80_signed_field_artifact_evidence.py --self-test
```

Focused Python tests use an injected signing probe to exercise archive/build/schema-v2 fail-closed behavior without pretending to verify a real Apple signature on a non-macOS host. The real final field candidate still requires the macOS producer against the exact signed IPA.

The package tests separately pin the schema-v2 closed-world parser, exact evidence/external-record byte binding, installed executable + raw Info.plist rendezvous, and the invariant that physical execution remains NO-GO.

## Physical status

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN** until the final composed app has exact-head product acceptance, the exact signed field artifact has independent acceptance, the package field gate is deliberately bound to that authority, and the definitive runbook is explicitly changed to GO.
