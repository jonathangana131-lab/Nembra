# ES80 Capture Build Identity — V14

## Purpose

V14 requires the first physical Experiment One run to be tied to the **exact Nembra Capture build**, including a human-readable build identifier and exact Git SHA, without asking the rider/operator to transcribe those values.

A Git SHA typed into a sidecar is only a declaration. It does not prove that the running binary came from that revision.

`PassiveBluetoothCaptureRuntimeBuildIdentityReader` adds the narrow runtime half of the stronger provenance chain.

## Runtime identity contract

Production has one public producer:

`PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()`

It:

1. reads `NembraCaptureBuildIdentifier` from the running application's `Bundle.main` metadata;
2. reads `NembraCaptureBuildCommitSHA` from the same bundle;
3. requires the commit to be one exact 40-hex Git SHA and normalizes only hexadecimal case;
4. rejects missing, padded, blank, control-character, or oversized build labels;
5. requires the main bundle executable to exist as a regular readable file;
6. hashes the exact executable bytes with SHA-256;
7. returns one immutable `PassiveBluetoothCaptureRuntimeBuildIdentity` containing build label, exact source SHA declaration, and runtime executable digest.

Production callers cannot supply an alternate bundle, arbitrary metadata dictionary, or arbitrary executable bytes to the public producer. Deterministic injection exists only at package scope for tests.

## What this proves

The executable SHA-256 is a direct digest of the executable bytes visible to the running app. If one executable byte changes, the runtime executable identity changes.

The embedded build label and source SHA prove only what metadata the build contains. By themselves they do **not** cryptographically prove that the source checkout produced those executable bytes.

The final accepted build pipeline must therefore provide an independent trusted build record that binds:

- exact checked-out Git SHA;
- accepted human-readable Capture build identifier;
- exact built executable digest (or a stronger signed/archive artifact identity);
- Xcode/toolchain and final build artifact needed by the V14 GO record.

Physical preflight can then compare the runtime-produced identity to that independently produced record. A mismatch or missing embedded field is NO-GO.

## Required app/build integration

This package slice intentionally does not edit the high-contention V14 app/project/scheme owned by the active Capture shell lane.

The accepted app/build owner must inject both bundle keys automatically from the exact build process:

- `NembraCaptureBuildIdentifier`
- `NembraCaptureBuildCommitSHA`

The rider/operator must not type either value into the Capture UI.

The app-visible preflight / `View Details` surface should consume `currentApplication()` and show the build label plus full or safely inspectable exact SHA. The final provenance producer should consume the same runtime identity rather than asking for a parallel build declaration.

## Manifest integration

The incumbent stationary-manifest lineage (#522 / accepted successor) remains the provenance format owner. This build-identity slice does not create a second sidecar schema.

When the manifest/app composition is ready, its build fields should come from the accepted runtime identity/build-record comparison, not from a rider-entered string. The immutable exact-H capture bytes remain separately SHA-256-bound by the manifest.

## Truth boundary

This is **software build provenance infrastructure only**.

It does not prove:

- physical AOVOPRO ES80 identity/authentication;
- RF completeness or physical OFF/ON state;
- GATT/Tuya/DP semantics;
- battery, voltage, current, power, speed, cadence, scale, or signedness;
- command authority or acknowledgement;
- that an embedded Git SHA is authentic without the independent trusted build record.

No application characteristic-value write path is added.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
