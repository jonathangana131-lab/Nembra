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
4. measure and retain the exact produced executable or final installable artifact after signing;
5. create an **external** build record containing build label, build-instance ID, source SHA, exact artifact digest, exact build-metadata digest, recipe ID, and procedure version;
6. independently sign/attest that external record and the exact retained final artifact identity;
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

## Retained evidence + external record

The runner retains immutable copies of the exact measured Simulator executable and generated `Info.plist` under `Artifacts/Xcode27Simulator/build-evidence/`. Each copy is byte-compared against the build output and re-hashed before any provenance record is accepted. This prevents a later reviewer from being left with only a digest string after DerivedData disappears.

`NembraCaptureExternalBuildRecord.json` remains outside the app bundle. Schema v3 carries:

- `schemaVersion = 3`;
- `buildIdentifier`;
- `buildInstanceID`;
- `sourceCommitSHA`;
- `executableSHA256`;
- `infoPlistSHA256`;
- `experimentRecipeID = ES80-FINGERPRINT-v1`;
- `procedureVersion = V14`.

The workflow checks the retained executable and retained `Info.plist` against those exact record digests before attestation. It then requests independent GitHub attestations for the exact external-record bytes and the retained executable file itself. The uploaded QA artifact preserves the retained executable, `Info.plist`, record, runner metadata, screenshots, logs, and xcresult for later re-verification.

The retained Simulator executable is not a substitute for the eventual signed field artifact. A final physical-device pipeline must retain and attest the exact **final signed** field build or installable artifact (for example the accepted `.ipa`) and bind that artifact to the same pre-build build-instance rendezvous. That final pipeline must then receive exact-head product acceptance and a completed external GO record. Simulator evidence cannot be promoted into that role.

## Manifest integration

The stationary-manifest lineage remains the provenance format owner for the captured evidence artifact. Its build fields should come from accepted runtime/build evidence rather than rider-entered strings.

The immutable exact-H capture bytes remain separately SHA-256-bound by the manifest. The build-instance ID should be carried through the eventual accepted artifact/manifest evolution when that schema owner performs the next deliberate version change; it must not be injected as an unknown field into an older closed-world schema.

## Truth boundary

This is **software build provenance infrastructure only**.

It does not prove:

- physical AOVOPRO ES80 identity/authentication;
- RF completeness or physical OFF/ON state;
- GATT/Tuya/DP semantics;
- battery, voltage, current, power, speed, cadence, scale, or signedness;
- command authority or acknowledgement;
- that an embedded Git SHA or UUID is authentic without the independent trusted build/acceptance evidence;
- that a Simulator build is the accepted physical field build.

No application characteristic-value write path is added.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**