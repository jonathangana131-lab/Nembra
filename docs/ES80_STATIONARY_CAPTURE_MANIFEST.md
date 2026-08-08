# ES80 Stationary Capture Manifest — V14

Status: **software provenance contract only; physical Experiment One remains NO-GO / DO NOT RUN**.

This file documents the V14 stationary-capture sidecar recovered from the accepted #393 format and deliberately evolved to schema v2 on the clean `ES80-FINGERPRINT-v1` recipe spine.

## Why schema v2 exists

Schema v1 bound exact capture bytes, selected CoreBluetooth UUID, declared build commit, setup context, and capture-derived counts, but it had no stable experiment-recipe identity. A copied sidecar therefore could not mechanically answer which accepted Nembra procedure the product intended to follow.

Schema v2 adds one required top-level field:

- `recipeID: "ES80-FINGERPRINT-v1"`

The value comes from `PassiveBluetoothExperimentRecipe.es80FingerprintV1`, whose construction and ordered step list are sealed by `NembraBluetoothCapture`. App/UI code cannot mint the official recipe ID with a shortened or reordered step list.

Recipe identity is **workflow provenance, not evidence**. It does not prove that the operator completed OFF1 -> ON1 -> OFF2 -> ON2, that the physical scooter was in the requested power state, that RF observation was complete, or that any GATT/Tuya/telemetry interpretation is correct.

## Deliberate schema transition

`PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion == 2`.

The V14 verifier accepts schema v2 only. A schema-v1 sidecar is rejected as `unsupportedSchemaVersion(1)` rather than silently inferring `ES80-FINGERPRINT-v1` for an artifact that never recorded a recipe.

This is intentionally fail-closed. No physical ES80 capture has been accepted under schema v1, and the immutable raw capture JSON remains the underlying evidence artifact. If a legitimate historical software-only schema-v1 sidecar needs migration, regenerate a schema-v2 sidecar mechanically from the unchanged raw capture bytes plus the accepted procedure/build/setup declarations; do not hand-edit the old JSON or pretend the missing recipe was recorded originally.

Unknown schema-v2 fields remain rejected. New semantics require another deliberate schema/version change.

## Builder contract

`PassiveBluetoothStationaryCaptureManifestBuilder.make(...)` requires:

- exact versioned passive capture JSON bytes;
- a valid full 40- or 64-hex declared Git commit SHA, normalized lowercase;
- the exact selected CoreBluetooth UUID;
- declared charger state;
- declared `foregroundUnlockedScreenOn` execution context;
- declared stock-app reference setup;
- an official sealed recipe, defaulting to `PassiveBluetoothExperimentRecipe.es80FingerprintV1`.

The default exists so existing mechanical callers cannot accidentally create a recipe-less V14 manifest. The official recipe object itself has a private constructor, so a caller cannot pair the stable ID with arbitrary procedure ordering.

The builder emits:

- `schemaVersion: 2`;
- `experimentKind: stationaryBaseline`;
- `recipeID: ES80-FINGERPRINT-v1`;
- experiment ID and preparation time;
- declared build commit and setup;
- exact source-artifact SHA-256 / byte count / capture session ID / selected UUID;
- target GATT/value counts, stock-app marker count, and known continuity-break count recomputed from the raw capture.

## Exact artifact binding

`verifyCaptureBinding(manifestJSON:captureJSON:)` never trusts serialized capture-derived fields by themselves. It:

1. reads the declared schema version before accepting any other imported claim;
2. rejects anything except current schema v2;
3. enforces the closed-world v2 JSON shape, including required `recipeID`;
4. decodes the stable recipe ID;
5. rebuilds the sidecar from the exact raw capture bytes and the declared context;
6. requires exact equality with the imported manifest.

Changing the raw capture bytes changes the SHA-256 binding even if the decoded JSON would be semantically equivalent. Tampering with selected target, counts, recipe ID, or other reconstructed state fails verification.

SHA-256 here is artifact-integrity/binding evidence only. It does not authenticate the scooter, operator, build binary, account, or physical setup.

## Build identity truth boundary

`nembraBuildCommitSHA` is still a **declared** commit value. Shape validation proves only that it is a full supported hexadecimal SHA. It does not attest that the running binary came from that commit.

The final app-visible Capture instrument should inject the build revision from trusted build metadata automatically rather than asking the rider to type or copy it. Stronger authenticity would require an external trusted build record/signature/attestation. This sidecar does not fake that property.

## Target attribution and continuity

Broad advertisements and connection-only callbacks cannot establish the selected target for this sidecar. The raw capture must contain GATT-attributable evidence for exactly one canonical CoreBluetooth UUID, and the selected UUID must match it.

Connection-only identity remains weaker, but continuity is preserved independently: every event for which `PassiveBluetoothCaptureEvent.breaksByteContinuity` is true increments `continuityBreakCount`. Identity uncertainty therefore cannot erase a known raw-byte gap.

The selected UUID is correlated Bluetooth target evidence only. It is not automatically a permanent or cryptographic AOVOPRO ES80 identity.

## Stock-app consistency

`stockAppReferenceSetup` is declared procedure context while marker count is capture-derived. A declaration of `.none` requires zero raw stock-app markers. Non-`none` values still do not prove refresh timing, simultaneous same-phone observation, or device relationship.

Nembra never claims to sniff another app's private CoreBluetooth exchange.

## App/export integration requirement

This package slice is not app-visible completion. The active Capture shell must eventually consume the manifest mechanically after the canonical controller has earned immutable exact-H completion.

The final product path should:

1. use the accepted `ES80-FINGERPRINT-v1` workflow/evidence producers;
2. obtain exact build identity from product/build plumbing rather than rider transcription;
3. finalize one immutable exact-H capture only after accepted Ready -> >=60 s monotonic Horizon authority;
4. create schema-v2 provenance automatically from those exact bytes and exact selected target;
5. verify the capture binding before presenting completion;
6. expose recipe/build provenance in `VIEW DETAILS` without turning declarations into physical facts;
7. make `SHARE CAPTURE` export the capture and its mechanically bound provenance together so the rider does not hunt for or hand-edit metadata.

Until that app/controller composition is accepted on one exact head, this manifest remains foundation work rather than app-visible closure.

## V14 first physical procedure relationship

The intended first experiment remains:

1. preflight;
2. find scooter;
3. OFF1;
4. ON1;
5. OFF2;
6. ON2;
7. explicit correlated-target confirmation;
8. passive discovery;
9. accepted observation Ready;
10. passive capture;
11. at least 60 seconds of accepted monotonic Ready -> Horizon observation, then exact Horizon commit + immutable seal;
12. integrity check;
13. analyze;
14. share.

The recipe records that intended order. Only the accepted evidence/controller layers can prove the evidence-bearing transitions.

## Explicit non-claims

This lane does not establish:

- physical AOVOPRO ES80 authentication;
- RF completeness or physical OFF/ON attestation;
- permanent scooter identity from a CoreBluetooth UUID;
- Tuya/GATT/DP meaning;
- battery, voltage, current, watts, speed, throttle, regen, or cadence semantics;
- command authorization or acknowledgement;
- authenticated running-build provenance;
- background capture support;
- any characteristic-value write path.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
