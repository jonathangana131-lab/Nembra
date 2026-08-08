# ES80 Capture Accepted-Build Record — V14

Status: **software provenance artifact contract only / PHYSICAL NO-GO**

This document defines the narrow machine-readable record that the final accepted build process can produce for Nembra Capture preflight. It complements `ES80_CAPTURE_BUILD_IDENTITY.md`.

The record exists so the field app can compare the executable identity it measures at runtime against an independently produced expected tuple. It removes any need for the rider/operator to type a Git SHA, executable hash, recipe ID, or build label.

## Schema v1

Exactly these top-level fields are allowed:

```json
{
  "schemaVersion": 1,
  "buildIdentifier": "Capture Build V14-F1",
  "sourceCommitSHA": "0123456789abcdef0123456789abcdef01234567",
  "executableSHA256": "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd",
  "experimentRecipeID": "ES80-FINGERPRINT-v1",
  "procedureVersion": "V14",
  "toolchainIdentifier": "Xcode 27"
}
```

`PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(_:)` fails closed when:

- the top level is not a JSON object;
- any unknown top-level field is present;
- `schemaVersion` is not exactly the current schema;
- the build identifier is blank, padded, oversized, or contains controls;
- `sourceCommitSHA` is not exactly 40 hexadecimal characters;
- `executableSHA256` is not exactly 64 hexadecimal characters;
- the recipe identifier is not a package-known versioned recipe;
- procedure/toolchain labels are blank, padded, oversized, or contain controls.

Hexadecimal case is normalized only for the source commit and executable digest. Human-readable labels are exact.

## Why unknown fields fail closed

The record is deliberately not a general metadata bag. In particular, schema v1 has no field for claims such as:

- `physicalGo`;
- `verifiedES80`;
- `telemetryVerified`;
- command authority;
- physical identity/authentication.

A producer cannot smuggle those meanings into this parser. Physical authorization remains a separate accepted gate.

## Trust boundary

Successful decoding proves **syntax/schema validity only**.

A caller can construct or copy matching values. Therefore neither the decoded artifact nor an exact tuple match is, by itself, trusted build authority. The final acceptance path must independently establish that the record came from the accepted build process (for example, through an accepted CI/archive/signing chain) before it can participate in any future field GO decision.

The runtime half remains `PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()`:

- embedded build label/SHA are declarations;
- the runtime executable SHA-256 is direct byte identity for the executable visible to the app;
- the external record supplies the expected tuple plus procedure/toolchain context;
- `PassiveBluetoothCaptureBuildRecordComparator` performs only the deterministic field comparison.

Even a byte-for-byte tuple match does **not** prove physical scooter identity, GATT/Tuya semantics, telemetry fields, command acknowledgement, or successful completion of the recipe.

## Current integration state

The package now has the pieces needed to:

1. read the running app's build identity;
2. bind the runtime build label/SHA into the stationary manifest producer without rider input;
3. decode a strict external build record;
4. compare runtime build identity + recipe to that external record.

Still required before physical Experiment One can become GO:

- the app build must inject `NembraCaptureBuildIdentifier` and `NembraCaptureBuildCommitSHA` automatically;
- an accepted build pipeline must actually emit and authenticate the external record for the exact composed app executable;
- app-visible preflight must consume the runtime identity/record comparison and show exact blockers;
- the full Capture lifecycle/controller/app shell must be composed and accepted on one exact head;
- final Xcode 27 / iPhone 12 / iOS 27 runtime, visual, accessibility, performance, and recovery-state gates must pass;
- the physical runbook's blank GO record must be filled only by that accepted final head.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
