# ES80 Capture Build Identity — V14

## Purpose

V14 requires the first physical Experiment One run to be tied to the **exact Nembra Capture build**, including a human-readable build identifier, one exact produced-build instance, and exact Git SHA, without asking the rider/operator to transcribe those values.

A Git SHA typed into a sidecar is only a declaration. It does not prove that the running binary came from that revision. Likewise, a source SHA alone does not distinguish two separately produced binaries from the same checkout.

`PassiveBluetoothCaptureRuntimeBuildIdentityReader` provides the runtime half of the stronger provenance chain while the trusted build runner produces an independently attestable external build record.

## Runtime identity contract

Production has one public producer:

`PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()`

It:

1. reads `NembraCaptureBuildIdentifier` from the running application's `Bundle.main` metadata;
2. reads `NembraCaptureBuildInstanceID` from the same bundle;
3. requires the build-instance value to be one exact canonical UUID-shaped identifier and normalizes only hexadecimal case;
4. reads `NembraCaptureBuildCommitSHA` from the same bundle;
5. requires the commit to be one exact 40-hex Git SHA and normalizes only hexadecimal case;
6. rejects missing, padded, blank, control-character, oversized, or malformed metadata;
7. requires the main bundle executable to exist as a regular readable file;
8. hashes the exact executable bytes with SHA-256;
9. returns one immutable `PassiveBluetoothCaptureRuntimeBuildIdentity` containing build label, build-instance ID, exact source SHA declaration, and runtime executable digest.

Production callers cannot supply an alternate bundle, arbitrary metadata dictionary, or arbitrary executable bytes to the public producer. Deterministic injection exists only at package scope for tests.

## Build-instance rendezvous

The trusted runner generates a fresh random UUID **before** the build and injects it automatically as `NembraCaptureBuildInstanceID`. The same value is written into the post-build external record together with the exact produced executable digest.

That UUID is deliberately an opaque rendezvous identifier, not evidence of trust by itself. Its value is that the running app and the independently attested post-build record can name the same exact build instance without asking the app bundle to contain the hash of its own final signed executable.

Two builds from the same Git SHA therefore have distinct build-instance IDs even when their human-readable build label is similar.

## What the runtime evidence proves

The executable SHA-256 is a direct digest of the executable bytes visible to the running app. If one executable byte changes, the runtime executable identity changes.

The embedded build label, build-instance ID, and source SHA prove only what metadata the build contains. By themselves they do **not** cryptographically prove that the source checkout produced those executable bytes or that the build is authorized for physical Experiment One.

The build-instance ID also does not authenticate a release merely because its spelling is UUID-shaped. Trust comes from the independently controlled build/acceptance pipeline and the attestation over the external record.

## Why the final executable digest stays external

Do **not** place a record containing SHA-256 of the final signed executable inside the same signed app bundle.

On Apple platforms, bundle resources participate in the code-signing resource seal while the code signature is stored in the Mach-O executable. If a sealed resource contains the hash of that final signed executable, changing the record changes the resource seal/signature, which changes the executable bytes whose hash the record is trying to contain. Adding the record after signing breaks the seal; signing again changes the executable digest again.

The accepted topology is therefore:

1. generate build label + build-instance ID + source SHA before build;
2. embed those non-self-referential declarations in the app;
3. produce/sign the final app artifact;
4. measure the exact produced executable or final installable artifact after signing;
5. create an **external** build record containing build label, build-instance ID, source SHA, exact artifact digest, recipe ID, and procedure version;
6. independently sign/attest that external record and exact final artifact identity;
7. use the shared build-instance ID to correlate app-visible preflight details with the accepted external GO record.

The current Simulator pipeline exercises the same topology with `CODE_SIGNING_ALLOWED=NO`. Simulator attestation remains software evidence only and never authorizes hardware.

## Required build integration

The accepted build owner must inject all three bundle keys automatically from the exact build process:

- `NembraCaptureBuildIdentifier`
- `NembraCaptureBuildInstanceID`
- `NembraCaptureBuildCommitSHA`

The rider/operator must not type any of them into the Capture UI.

The runner must fail closed if the built app does not preserve the exact generated values. It must also fail if an executable-digest provenance record appears inside the app bundle.

The app-visible preflight / `View Details` surface should expose the build label, safely inspectable exact source SHA, and build-instance ID as **software build evidence**. A future field-admission design must not relabel those declarations as physical authorization or recreate the signed-bundle self-reference through another resource.

## External record — current schema v3

The current flagship runner emits `NembraCaptureExternalBuildRecord.json` outside the app bundle with a closed-world schema-v3 shape:

- `schemaVersion = 3`;
- `buildIdentifier`;
- `buildInstanceID`;
- `sourceCommitSHA`;
- `executableSHA256`;
- `infoPlistSHA256`;
- `experimentRecipeID = ES80-FINGERPRINT-v1`;
- `procedureVersion = V14`.

The same runner retains byte-for-byte copies of the exact built executable and generated Info.plist under `Artifacts/Xcode27Simulator/build-evidence/`, byte-compares them back to DerivedData, and re-hashes those retained bytes before accepting the record. `PassiveBluetoothCaptureExternalBuildRecordJSON` requires this schema-v3 vocabulary, and the current flagship composition therefore keeps producer and parser aligned.

The dedicated `Xcode 27 Simulator QA` workflow independently requires the exact schema-v3 key set, re-hashes the retained executable and Info.plist against the record, attests the exact external-record file, and attests the retained executable by path. Those attestations are build-pipeline evidence; they are not physical scooter evidence.

The PR exact-head Xcode command executes the checked-out runner and can establish build/test/UI evidence for one immutable PR head, including the runner's retained-byte checks. It does **not** by itself turn that PR run into the final externally attested physical field build. The dedicated workflow/main acceptance and the eventual signed-device acceptance remain distinct authorities.

A final physical-device pipeline still needs the same pattern applied to the exact **signed** field build or installable artifact, followed by exact-head product acceptance and a completed external GO record. The Simulator record cannot be promoted into that role.

## Manifest integration

The stationary-manifest/final-Share lineage is the provenance format owner for the captured evidence artifact. Its build fields come from package-produced runtime/build evidence rather than rider-entered strings.

The immutable exact-H capture bytes remain separately SHA-256-bound inside that accepted evidence lineage. Build-instance identity is carried by the current package-owned SoftwareExport/final-Share path; unknown fields must never be injected into an older closed-world schema merely to make provenance look richer.

## Truth boundary

This is **software build provenance infrastructure only**.

It does not prove:

- physical AOVOPRO ES80 identity/authentication;
- RF completeness or physical OFF/ON state;
- GATT/Tuya/DP semantics;
- battery, voltage, current, power, speed, cadence, scale, or signedness;
- command authority or acknowledgement;
- that an embedded Git SHA or UUID is authentic without the independent trusted build/acceptance evidence;
- that a Simulator build is the accepted physical field build;
- that a signed physical-device artifact has been installed and accepted.

No application characteristic-value write path is added.

## Current closure boundary

Current flagship software work now has a schema-v3 Simulator producer/parser path and retained executable/Info.plist evidence. The remaining build-provenance blocker before physical GO is **not** another Simulator digest field: it is an independently accepted exact signed iPhone field build/installable artifact, correlated to the same build-instance/source/recipe/procedure tuple and then deliberately admitted by the package field execution gate.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
