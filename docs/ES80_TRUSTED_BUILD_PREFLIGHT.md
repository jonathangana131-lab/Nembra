# ES80 trusted field-build preflight

Status: **software provenance prerequisite only — physical Experiment One remains NO-GO.**

Nembra Capture already measures the exact executable bytes that are running and reads the embedded build label/source commit declaration. That runtime identity is useful evidence, but the declaration cannot prove itself. V14 therefore requires an independently generated build record before field preflight may treat the running binary as matching the accepted field build.

## Closed-world record

The accepted build pipeline must place one resource named `NembraCaptureTrustedBuildRecord.json` in the application bundle. Schema v1 contains exactly:

```json
{
  "schemaVersion": 1,
  "buildIdentifier": "Capture Build V14-F1",
  "sourceCommitSHA": "0123456789abcdef0123456789abcdef01234567",
  "executableSHA256": "64-lowercase-hex-digits",
  "experimentRecipeID": "ES80-FINGERPRINT-v1",
  "procedureVersion": "V14"
}
```

Unknown fields fail closed. Missing fields fail closed. The source commit must be one full 40-hex Git SHA. The executable digest must be canonical lowercase SHA-256. The current recipe must be exactly `ES80-FINGERPRINT-v1`, and the current procedure identity is `V14`.

The rider/operator must never type or edit this record.

## Runtime binding

`PassiveBluetoothCaptureBuildPreflight.currentApplication()` performs the production check:

1. `PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()` reads the running app's embedded build label and source-commit declaration and hashes the exact executable bytes visible to the app.
2. `PassiveBluetoothCaptureTrustedBuildRecordReader.currentApplication()` loads only the fixed record resource from `Bundle.main` and validates the closed-world schema.
3. The preflight requires exact equality for build identifier, normalized full source commit, and executable SHA-256.
4. Success returns `PassiveBluetoothCaptureRuntimeBuildBinding` carrying the matched build/procedure identity.

There is intentionally no public production API that accepts a caller-provided URL, dictionary, runtime identity, trusted record, expected digest, recipe, or procedure version. Package-scoped injection exists only for deterministic tests.

## Trust boundary

The executable SHA-256 is direct software evidence about the bytes the application is running. The trusted build record is a build/acceptance-pipeline record that must be generated from the exact accepted checkout/build process and packaged without rider intervention.

This still does **not** make the embedded Git SHA a cryptographic proof that source produced the executable. The accepted build pipeline is the trust anchor for that source-to-build association. If stronger signed/archive identity is later adopted, evolve this boundary deliberately rather than relabeling the current declaration as attestation.

The record also does not prove scooter identity, physical OFF/ON state, RF completeness, GATT/Tuya/DP semantics, telemetry meaning, or command acknowledgement.

## Integration requirement

A final V14 field build still needs pipeline/app-project integration that:

- injects `NembraCaptureBuildIdentifier` and `NembraCaptureBuildCommitSHA` automatically;
- computes the produced app executable SHA-256 from the exact accepted build;
- generates the matching `NembraCaptureTrustedBuildRecord.json` from trusted build metadata;
- packages that record as an app resource;
- preserves the exact accepted recipe/procedure identity;
- exposes a clear preflight blocker when the resource is missing, malformed, or mismatched.

The build-binding result must then be composed with the rest of Capture preflight. It is not the physical execution authority.

## Independent physical lock remains mandatory

`PassiveBluetoothExperimentOneFieldExecutionGate` remains the separate mechanical GO/NO-GO authority. This preflight intentionally does not edit or bypass it. A perfectly matching trusted build record while that gate is NO-GO must still expose **no physical OFF1/ON1/OFF2/ON2 or capture action**.

Only the final composed exact build, after runtime/visual/accessibility/performance/integrity acceptance and an explicit runbook GO record, may deliberately evolve that gate.
